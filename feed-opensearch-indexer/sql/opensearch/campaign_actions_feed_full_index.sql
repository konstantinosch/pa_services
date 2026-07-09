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
ORDER BY
  ca.`created_at` ASC,
  ca.`index` ASC;
