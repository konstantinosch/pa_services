import argparse
import csv
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import requests


SERVICE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SQL_FILE = SERVICE_DIR / "sql" / "opensearch" / "campaign_actions_feed_full_index.sql"
DEFAULT_INDEX_FILE = SERVICE_DIR / "opensearch" / "campaign_actions_feed.index.json"


def env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "y", "on")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Load campaign action documents from the source MySQL database into OpenSearch."
    )
    parser.add_argument("--sql-file", default=str(DEFAULT_SQL_FILE))
    parser.add_argument("--index-file", default=str(DEFAULT_INDEX_FILE))
    parser.add_argument("--mysql-command", default=os.getenv("SOURCE_MYSQL_BIN", "mysql"))
    parser.add_argument("--mysql-sudo", action="store_true", default=env_bool("SOURCE_MYSQL_SUDO", True))
    parser.add_argument("--mysql-host", default=os.getenv("SOURCE_MYSQL_HOST", "localhost"))
    parser.add_argument("--mysql-port", default=os.getenv("SOURCE_MYSQL_PORT", "3306"))
    parser.add_argument("--mysql-user", default=os.getenv("SOURCE_MYSQL_USER", ""))
    parser.add_argument("--mysql-password", default=os.getenv("SOURCE_MYSQL_PASSWORD", ""))
    parser.add_argument("--mysql-database", default=os.getenv("SOURCE_MYSQL_DATABASE", "deedspot"))
    parser.add_argument("--opensearch-url", default=os.getenv("OPENSEARCH_URL", "http://localhost:9200"))
    parser.add_argument("--opensearch-username", default=os.getenv("OPENSEARCH_USERNAME", ""))
    parser.add_argument("--opensearch-password", default=os.getenv("OPENSEARCH_PASSWORD", ""))
    parser.add_argument("--index", default=os.getenv("OPENSEARCH_INDEX", "campaign_actions_feed"))
    parser.add_argument("--page-size", type=int, default=int(os.getenv("OPENSEARCH_LOADER_PAGE_SIZE", "10000")))
    parser.add_argument("--start-created-at", type=int, default=0)
    parser.add_argument("--start-index", type=int, default=0)
    parser.add_argument("--max-pages", type=int, default=0, help="0 means no limit.")
    parser.add_argument("--reset-index", action="store_true")
    parser.add_argument("--create-index", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def load_base_sql(path):
    sql = Path(path).read_text(encoding="utf-8").strip()
    sql = re.sub(r";\s*$", "", sql)
    sql = re.sub(
        r"\bORDER\s+BY\s+ca\.`created_at`\s+ASC\s*,\s*ca\.`index`\s+ASC\s*$",
        "",
        sql,
        flags=re.IGNORECASE | re.DOTALL,
    ).strip()
    return sql


def build_page_sql(base_sql, last_created_at, last_index, page_size):
    return f"""
SELECT
  q.`created_at`,
  q.`index`,
  q.`campaign_index`,
  q.`tags`
FROM (
{base_sql}
) q
WHERE
  q.`created_at` IS NOT NULL
  AND (
    q.`created_at` > {int(last_created_at)}
    OR (
      q.`created_at` = {int(last_created_at)}
      AND q.`index` > {int(last_index)}
    )
  )
ORDER BY
  q.`created_at` ASC,
  q.`index` ASC
LIMIT {int(page_size)}
"""


def mysql_rows(args, sql):
    mysql_cmd = [
        args.mysql_command,
        "--batch",
        "--raw",
        "--skip-column-names",
    ]

    if args.mysql_sudo:
        cmd = ["sudo", *mysql_cmd, args.mysql_database, "--execute", sql]
    else:
        if not args.mysql_user:
            raise RuntimeError("SOURCE_MYSQL_USER is required unless SOURCE_MYSQL_SUDO=1")
        cmd = [
            *mysql_cmd,
            "--host",
            args.mysql_host,
            "--port",
            str(args.mysql_port),
            "--user",
            args.mysql_user,
            args.mysql_database,
            "--execute",
            sql,
        ]

    env = os.environ.copy()
    if args.mysql_password:
        env["MYSQL_PWD"] = args.mysql_password

    result = subprocess.run(
        cmd,
        env=env,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "mysql command failed")

    rows = []
    reader = csv.reader(result.stdout.splitlines(), delimiter="\t")

    for fields in reader:
        if len(fields) != 4:
            raise RuntimeError(f"Unexpected mysql row shape: {fields}")

        created_at, index, campaign_index, tags = fields
        try:
            parsed_tags = json.loads(tags) if tags else []
        except json.JSONDecodeError:
            parsed_tags = []

        rows.append(
            {
                "created_at": int(created_at),
                "index": int(index),
                "campaign_index": int(campaign_index),
                "tags": parsed_tags,
            }
        )

    return rows


def opensearch_auth(args):
    if args.opensearch_username:
        return (args.opensearch_username, args.opensearch_password)
    return None


def request_ok(response):
    return 200 <= response.status_code < 300


def reset_or_create_index(args):
    base = args.opensearch_url.rstrip("/")
    index_url = f"{base}/{args.index}"

    if args.reset_index:
        response = requests.delete(index_url, auth=opensearch_auth(args), timeout=30)
        if response.status_code not in (200, 404):
            raise RuntimeError(f"Delete index failed: {response.status_code} {response.text}")

    if args.reset_index or args.create_index:
        mapping = json.loads(Path(args.index_file).read_text(encoding="utf-8"))
        response = requests.put(index_url, json=mapping, auth=opensearch_auth(args), timeout=30)
        if response.status_code not in (200, 400):
            raise RuntimeError(f"Create index failed: {response.status_code} {response.text}")
        if response.status_code == 400 and "resource_already_exists_exception" not in response.text:
            raise RuntimeError(f"Create index failed: {response.status_code} {response.text}")


def bulk_index(args, rows):
    if not rows:
        return 0

    lines = []
    for row in rows:
        lines.append(json.dumps({"index": {"_index": args.index, "_id": row["index"]}}, separators=(",", ":")))
        lines.append(json.dumps(row, separators=(",", ":")))

    body = "\n".join(lines) + "\n"
    url = f"{args.opensearch_url.rstrip('/')}/_bulk"
    response = requests.post(
        url,
        data=body.encode("utf-8"),
        headers={"Content-Type": "application/x-ndjson"},
        auth=opensearch_auth(args),
        timeout=60,
    )

    if not request_ok(response):
        raise RuntimeError(f"Bulk request failed: {response.status_code} {response.text}")

    payload = response.json()
    if payload.get("errors"):
        failures = [item for item in payload.get("items", []) if item.get("index", {}).get("error")]
        sample = json.dumps(failures[:3], indent=2)
        raise RuntimeError(f"Bulk index contained item errors. Sample: {sample}")

    return len(rows)


def main():
    args = parse_args()

    if args.page_size <= 0:
        raise RuntimeError("--page-size must be positive")

    print(
        f"source_db={args.mysql_database} opensearch_url={args.opensearch_url} "
        f"index={args.index} dry_run={args.dry_run}",
        flush=True,
    )

    base_sql = load_base_sql(args.sql_file)
    if not args.dry_run:
        reset_or_create_index(args)

    total = 0
    page = 0
    last_created_at = args.start_created_at
    last_index = args.start_index

    while True:
        if args.max_pages and page >= args.max_pages:
            break

        sql = build_page_sql(base_sql, last_created_at, last_index, args.page_size)
        rows = mysql_rows(args, sql)

        if not rows:
            break

        if not args.dry_run:
            bulk_index(args, rows)

        page += 1
        total += len(rows)
        last = rows[-1]
        last_created_at = last["created_at"]
        last_index = last["index"]

        print(
            f"page={page} rows={len(rows)} total={total} "
            f"cursor=({last_created_at},{last_index})",
            flush=True,
        )

        if len(rows) < args.page_size:
            break

    print(
        f"done total={total} final_cursor=({last_created_at},{last_index}) "
        f"index={args.index}",
        flush=True,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
