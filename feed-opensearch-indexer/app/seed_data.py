import random
import string
import mysql.connector
from app.config import MYSQL_CONFIG

TOTAL_ITEMS = 5000
BATCH_SIZE = 500


def random_text(length=20):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def main():
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    cur = conn.cursor()

    print(f"Seeding {TOTAL_ITEMS} items...")

    item_values = []
    job_values = []

    for i in range(1, TOTAL_ITEMS + 1):
        title = f"Item {i} {random_text(5)}"
        body = f"Body {random_text(20)}"
        category = random.choice(["demo", "finance", "ops", "sales"])
        status = random.choice(["open", "closed", "pending"])

        item_values.append((title, body, category, status))

        # We will assume auto-increment IDs → use LAST_INSERT_ID trick later
        # but simpler approach: insert items first, then jobs

        if len(item_values) >= BATCH_SIZE:
            cur.executemany("""
                INSERT INTO items (title, body, category, status)
                VALUES (%s, %s, %s, %s)
            """, item_values)

            conn.commit()
            item_values.clear()

    # flush remaining
    if item_values:
        cur.executemany("""
            INSERT INTO items (title, body, category, status)
            VALUES (%s, %s, %s, %s)
        """, item_values)
        conn.commit()

    print("Items inserted.")

    # Now create jobs for ALL items
    print("Creating jobs...")

    cur.execute("SELECT item_id FROM items")
    all_ids = [row[0] for row in cur.fetchall()]

    job_batch = []

    for item_id in all_ids:
        job_batch.append(("item", str(item_id), "I", 0))

        if len(job_batch) >= BATCH_SIZE:
            cur.executemany("""
                INSERT INTO search_index_jobs (entity_type, entity_id, action, priority)
                VALUES (%s, %s, %s, %s)
            """, job_batch)
            conn.commit()
            job_batch.clear()

    if job_batch:
        cur.executemany("""
            INSERT INTO search_index_jobs (entity_type, entity_id, action, priority)
            VALUES (%s, %s, %s, %s)
        """, job_batch)
        conn.commit()

    print("Jobs inserted.")

    cur.close()
    conn.close()
    print("Done.")


if __name__ == "__main__":
    main()