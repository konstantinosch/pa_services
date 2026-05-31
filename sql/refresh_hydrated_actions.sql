-- Refresh ram_hydrated_actions from the live hydration join.
--
-- Caller must provide these session variables:
--   @recent_days
--   @ram_heap_target_bytes
--   @ram_heap_safety_pct
--   @ram_estimated_bytes_per_row

SET @ram_row_cap = CAST(
  FLOOR((@ram_heap_target_bytes * @ram_heap_safety_pct / 100) / @ram_estimated_bytes_per_row)
  AS UNSIGNED
);

-- MEMORY table max size is fixed when the table is created.
-- Hydration RAM is a one-dimensional lookup keyed by action_index.
SET SESSION max_heap_table_size = @ram_heap_target_bytes;

DROP TABLE IF EXISTS `ram_hydrated_actions_next`;

CREATE TABLE `ram_hydrated_actions_next` (
  `action_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `action_photo_index` int unsigned DEFAULT NULL,
  `post_content` varchar(4096) DEFAULT NULL,
  `post_shares_no` int unsigned NOT NULL DEFAULT 0,
  `post_comments_no` int unsigned NOT NULL DEFAULT 0,
  `post_image_url` varchar(2048) DEFAULT NULL,
  `campaign_id` varchar(191) DEFAULT NULL,
  `campaign_photo_index` int unsigned DEFAULT NULL,
  `campaign_photo_url` varchar(2048) DEFAULT NULL,
  `campaign_beneficiary_photo_url` varchar(2048) DEFAULT NULL,
  `campaign_file_url` varchar(2048) DEFAULT NULL,
  `campaign_status` varchar(64) DEFAULT NULL,
  `campaign_public_title` varchar(512) DEFAULT NULL,
  `campaign_title` varchar(512) DEFAULT NULL,
  `campaign_total_collected_funds` decimal(15,4) DEFAULT NULL,
  `campaign_total_target_amount` decimal(15,4) DEFAULT NULL,
  `campaign_target_amount` decimal(15,4) DEFAULT NULL,
  `campaign_quick_donations_no` int unsigned NOT NULL DEFAULT 0,

  PRIMARY KEY (`action_index`) USING HASH
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

SET @insert_ram_hydrated_actions_sql = CONCAT(
  'INSERT INTO `ram_hydrated_actions_next` (',
  '  `action_index`,',
  '  `created_at`,',
  '  `campaign_index`,',
  '  `action_photo_index`,',
  '  `post_content`,',
  '  `post_shares_no`,',
  '  `post_comments_no`,',
  '  `post_image_url`,',
  '  `campaign_id`,',
  '  `campaign_photo_index`,',
  '  `campaign_photo_url`,',
  '  `campaign_beneficiary_photo_url`,',
  '  `campaign_file_url`,',
  '  `campaign_status`,',
  '  `campaign_public_title`,',
  '  `campaign_title`,',
  '  `campaign_total_collected_funds`,',
  '  `campaign_total_target_amount`,',
  '  `campaign_target_amount`,',
  '  `campaign_quick_donations_no`',
  ') ',
  'SELECT ',
  '  ca.`index` AS `action_index`,',
  '  ca.`created_at`,',
  '  ca.`campaign_index`,',
  '  ca.`photo_index` AS `action_photo_index`,',
  '  LEFT(ca.`content`, 4096) AS `post_content`,',
  '  COALESCE(ca.`total_shares`, 0) AS `post_shares_no`,',
  '  COALESCE(ca.`total_comments`, 0) AS `post_comments_no`,',
  '  action_file.`path` AS `post_image_url`,',
  '  c.`id` AS `campaign_id`,',
  '  c.`photo_index` AS `campaign_photo_index`,',
  '  c.`photo_url` AS `campaign_photo_url`,',
  '  c.`beneficiary_photo_url` AS `campaign_beneficiary_photo_url`,',
  '  campaign_file.`path` AS `campaign_file_url`,',
  '  c.`status` AS `campaign_status`,',
  '  c.`public_title` AS `campaign_public_title`,',
  '  c.`title` AS `campaign_title`,',
  '  c.`total_collected_funds` AS `campaign_total_collected_funds`,',
  '  c.`total_target_amount` AS `campaign_total_target_amount`,',
  '  c.`target_amount` AS `campaign_target_amount`,',
  '  COALESCE(c.`total_quick_donations`, 0) AS `campaign_quick_donations_no` ',
  'FROM `campaign_actions` ca ',
  'INNER JOIN `campaigns` c ',
  '  ON c.`index` = ca.`campaign_index` ',
  'LEFT JOIN `files` action_file ',
  '  ON action_file.`index` = ca.`photo_index` ',
  'LEFT JOIN `files` campaign_file ',
  '  ON campaign_file.`index` = c.`photo_index` ',
  'WHERE ',
  '  ca.`created_at` >= UNIX_TIMESTAMP(NOW() - INTERVAL ', @recent_days, ' DAY) ',
  '  AND ca.`feed_visible` = 1 ',
  'ORDER BY ca.`created_at` DESC, ca.`index` DESC ',
  'LIMIT ', @ram_row_cap
);

PREPARE insert_ram_hydrated_actions FROM @insert_ram_hydrated_actions_sql;
EXECUTE insert_ram_hydrated_actions;
DEALLOCATE PREPARE insert_ram_hydrated_actions;

CREATE TABLE IF NOT EXISTS `ram_hydrated_actions` LIKE `ram_hydrated_actions_next`;

DROP TABLE IF EXISTS `ram_hydrated_actions_old`;

RENAME TABLE
  `ram_hydrated_actions` TO `ram_hydrated_actions_old`,
  `ram_hydrated_actions_next` TO `ram_hydrated_actions`;

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
  'hydrated_actions',
  UNIX_TIMESTAMP(),
  @recent_days,
  COUNT(*),
  COALESCE(MIN(`created_at`), 0),
  COALESCE(MAX(`created_at`), 0),
  @ram_heap_target_bytes,
  @ram_row_cap
FROM `ram_hydrated_actions`;

DROP TABLE IF EXISTS `ram_hydrated_actions_old`;
