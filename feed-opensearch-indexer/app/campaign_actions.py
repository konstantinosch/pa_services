import json


ENTITY_TYPE = "campaign_action"


CAMPAIGN_ACTION_DOCUMENT_SQL = """
SELECT
  ca.`created_at`,
  ca.`index`,
  ca.`campaign_index`,
  COALESCE(ctags.`tags`, JSON_ARRAY()) AS `tags`
FROM `campaign_actions` ca
LEFT JOIN (
  SELECT
    ct.`campaign_index`,
    JSON_ARRAYAGG(ct.`tag_index`) AS `tags`
  FROM `campaigns_tags` ct
  INNER JOIN `campaign_tags` t
    ON t.`index` = ct.`tag_index`
  GROUP BY
    ct.`campaign_index`
) ctags
  ON ctags.`campaign_index` = ca.`campaign_index`
WHERE
  ca.`feed_visible` = 1
  AND ca.`index` = %s
"""


def parse_tags(value):
    if value is None or value == "":
        return []

    if isinstance(value, list):
        return value

    if isinstance(value, bytes):
        value = value.decode("utf-8")

    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []

    return []


def campaign_action_document_from_row(row):
    if row is None:
        return None

    return {
        "created_at": int(row["created_at"]),
        "index": int(row["index"]),
        "campaign_index": int(row["campaign_index"]),
        "tags": parse_tags(row["tags"]),
    }
