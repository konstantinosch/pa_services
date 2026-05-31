-- Refresh ram_campaign_actions from campaign_actions.
--
-- Caller must provide these session variables:
--   @recent_days
--   @ram_heap_target_bytes
--   @ram_heap_safety_pct
--   @ram_estimated_bytes_per_row

SET @uint_max = 4294967295;
SET @ram_row_cap = CAST(
  FLOOR((@ram_heap_target_bytes * @ram_heap_safety_pct / 100) / @ram_estimated_bytes_per_row)
  AS UNSIGNED
);

-- MEMORY table max size is fixed when the table is created.
-- Build from a safety-budgeted newest-first row cap so RAM stays bounded.
SET SESSION max_heap_table_size = @ram_heap_target_bytes;

DROP TABLE IF EXISTS `ram_campaign_actions_next`;

CREATE TABLE `ram_campaign_actions_next` (
  `index` int unsigned NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `sort_created_at` int unsigned NOT NULL,
  `sort_index` int unsigned NOT NULL,
  `feed_visible` tinyint unsigned NOT NULL,

  PRIMARY KEY (`index`),
  KEY `idx_ram_ca_campaign_feed_created` (`campaign_index`, `feed_visible`, `sort_created_at`, `sort_index`) USING BTREE,
  KEY `idx_ram_ca_feed_created_campaign` (`feed_visible`, `sort_created_at`, `sort_index`, `campaign_index`) USING BTREE
) ENGINE=MEMORY DEFAULT CHARSET=latin1;

SET @insert_ram_campaign_actions_sql = CONCAT(
  'INSERT INTO `ram_campaign_actions_next` (',
  '  `index`,',
  '  `campaign_index`,',
  '  `created_at`,',
  '  `sort_created_at`,',
  '  `sort_index`,',
  '  `feed_visible`',
  ') ',
  'SELECT ',
  '  ca.`index`,',
  '  ca.`campaign_index`,',
  '  ca.`created_at`,',
  '  ', @uint_max, ' - ca.`created_at`,',
  '  ', @uint_max, ' - ca.`index`,',
  '  ca.`feed_visible` ',
  'FROM `campaign_actions` ca ',
  'WHERE ',
  '  ca.`created_at` >= UNIX_TIMESTAMP(NOW() - INTERVAL ', @recent_days, ' DAY) ',
  '  AND ca.`feed_visible` = 1 ',
  'ORDER BY ca.`created_at` DESC, ca.`index` DESC ',
  'LIMIT ', @ram_row_cap
);

PREPARE insert_ram_campaign_actions FROM @insert_ram_campaign_actions_sql;
EXECUTE insert_ram_campaign_actions;
DEALLOCATE PREPARE insert_ram_campaign_actions;

CREATE TABLE IF NOT EXISTS `ram_campaign_actions` LIKE `ram_campaign_actions_next`;

DROP TABLE IF EXISTS `ram_campaign_actions_old`;

RENAME TABLE
  `ram_campaign_actions` TO `ram_campaign_actions_old`,
  `ram_campaign_actions_next` TO `ram_campaign_actions`;

REPLACE INTO `ram_state` (
  `name`,
  `refreshed_at`,
  `recent_days`,
  `rows_count`,
  `min_created_at`,
  `max_created_at`,
  `ram_heap_target_bytes`,
  `ram_row_cap`
)
SELECT
  'campaign_actions',
  UNIX_TIMESTAMP(),
  @recent_days,
  COUNT(*),
  COALESCE(MIN(`created_at`), 0),
  COALESCE(MAX(`created_at`), 0),
  @ram_heap_target_bytes,
  @ram_row_cap
FROM `ram_campaign_actions`;

DROP TABLE IF EXISTS `ram_campaign_actions_old`;
