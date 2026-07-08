CREATE DATABASE indexer_demo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'indexer'@'localhost' IDENTIFIED BY 'indexerpass';

GRANT ALL PRIVILEGES ON indexer_demo.* TO 'indexer'@'localhost';

FLUSH PRIVILEGES;
EXIT;