DROP TABLE IF EXISTS `ram_state`;

CREATE TABLE `ram_state` (
  `name` varchar(64) NOT NULL,
  `refreshed_at` int unsigned NOT NULL,
  `recent_days` int unsigned NOT NULL,
  `rows_count` int unsigned NOT NULL,
  `min_created_at` int unsigned NOT NULL,
  `max_created_at` int unsigned NOT NULL,
  `ram_heap_target_bytes` bigint unsigned NOT NULL,
  `ram_row_cap` int unsigned NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=MEMORY DEFAULT CHARSET=latin1;
