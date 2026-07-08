-- MySQL dump 10.13  Distrib 8.0.19, for Win64 (x86_64)
--
-- Host: localhost    Database: deedspot
-- ------------------------------------------------------
-- Server version	8.4.8-0ubuntu1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `analytics`
--

DROP TABLE IF EXISTS `analytics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `analytics` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `user_id` int unsigned DEFAULT NULL,
  `messenger_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `campaign_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `messenger_index` int unsigned DEFAULT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `type` enum('visit','share','donation','like') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT 'visit',
  `entity` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `points` int unsigned DEFAULT '0',
  `amount` decimal(18,4) DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `user_id` (`user_id`),
  KEY `messenger_id` (`messenger_id`),
  KEY `campaign_id` (`campaign_id`),
  KEY `analytics_ibfk_1` (`messenger_index`),
  KEY `analytics_ibfk_2` (`campaign_index`),
  CONSTRAINT `analytics_ibfk_1` FOREIGN KEY (`messenger_index`) REFERENCES `benefactors` (`index`) ON UPDATE CASCADE,
  CONSTRAINT `analytics_ibfk_2` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=347 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `bank_accounts`
--

DROP TABLE IF EXISTS `bank_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `bank_accounts` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `code` varchar(50) DEFAULT NULL,
  `country_id` int unsigned DEFAULT NULL,
  `currency_id` int unsigned DEFAULT NULL,
  `account_number` varchar(50) DEFAULT NULL,
  `iban` char(34) DEFAULT NULL,
  `swift_code` char(11) DEFAULT NULL,
  `account_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_type` enum('savings','business') DEFAULT 'business',
  `currency` char(3) DEFAULT 'EUR',
  `balance` decimal(18,4) DEFAULT '0.0000',
  `accounting_balance` decimal(18,4) DEFAULT '0.0000',
  `status` enum('active','inactive','closed') DEFAULT 'active',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `bank_accounts_ibfk_1` (`currency_id`),
  KEY `bank_accounts_ibfk_2` (`country_id`),
  CONSTRAINT `bank_accounts_ibfk_1` FOREIGN KEY (`currency_id`) REFERENCES `currencies` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `bank_accounts_ibfk_2` FOREIGN KEY (`country_id`) REFERENCES `countries` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactor_categories`
--

DROP TABLE IF EXISTS `benefactor_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactor_categories` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactor_favorites`
--

DROP TABLE IF EXISTS `benefactor_favorites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactor_favorites` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `benefactor_favorites_ibfk_1` (`benefactor_index`),
  KEY `benefactor_favorites_ibfk_2` (`campaign_index`),
  CONSTRAINT `benefactor_favorites_ibfk_1` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`),
  CONSTRAINT `benefactor_favorites_ibfk_2` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=167 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactor_feed_settings`
--

DROP TABLE IF EXISTS `benefactor_feed_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactor_feed_settings` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `action_type` varchar(250) DEFAULT NULL,
  `show_in_feed` tinyint unsigned DEFAULT '0',
  `receive_notification` tinyint unsigned DEFAULT '0',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `benefactor_index` (`benefactor_index`),
  CONSTRAINT `benefactor_feed_settings_ibfk_1` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=316 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactor_liked_actions`
--

DROP TABLE IF EXISTS `benefactor_liked_actions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactor_liked_actions` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `campaign_action_index` int unsigned NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `benefactor_index` (`benefactor_index`),
  KEY `campaign_action_index` (`campaign_action_index`),
  CONSTRAINT `benefactor_liked_actions_ibfk_1` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`),
  CONSTRAINT `benefactor_liked_actions_ibfk_2` FOREIGN KEY (`campaign_action_index`) REFERENCES `campaign_actions` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactors`
--

DROP TABLE IF EXISTS `benefactors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactors` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `external_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `user_index` int unsigned DEFAULT NULL,
  `type_index` int unsigned DEFAULT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `bg_image_index` int unsigned DEFAULT NULL,
  `country_index` int unsigned DEFAULT NULL,
  `category_index` int unsigned DEFAULT NULL,
  `category_id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `bg_image_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `company_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address1` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address2` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `tax_id_number` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mobile` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `contact_person` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` enum('company','person','association','organization') DEFAULT NULL,
  `status` enum('interested','benefactor') DEFAULT NULL,
  `onboarding_completed` tinyint unsigned DEFAULT '0',
  `donation_type` enum('cash','sponsorship') DEFAULT NULL,
  `social_media` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `account_iban` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_beneficiary` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `user_index` (`user_index`),
  KEY `is_active` (`is_active`),
  KEY `country_index` (`country_index`),
  KEY `created_by` (`created_by`),
  KEY `photo_index` (`photo_index`),
  KEY `benefactors_ibfk_5` (`category_index`),
  KEY `bg_image_index` (`bg_image_index`),
  CONSTRAINT `benefactors_ibfk_1` FOREIGN KEY (`user_index`) REFERENCES `users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `benefactors_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `benefactors_ibfk_3` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `benefactors_ibfk_4` FOREIGN KEY (`country_index`) REFERENCES `countries` (`id`),
  CONSTRAINT `benefactors_ibfk_5` FOREIGN KEY (`category_index`) REFERENCES `benefactor_categories` (`index`),
  CONSTRAINT `benefactors_ibfk_6` FOREIGN KEY (`bg_image_index`) REFERENCES `files` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=56612 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `benefactors_campaign_tags`
--

DROP TABLE IF EXISTS `benefactors_campaign_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `benefactors_campaign_tags` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `tag_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `benefactors_campaign_tags_id_uindex` (`id`),
  UNIQUE KEY `benefactors_campaign_tags_benefactor_tag_uindex` (`benefactor_index`,`tag_index`),
  KEY `benefactors_campaign_tags_tag_index_index` (`tag_index`),
  CONSTRAINT `benefactors_campaign_tags_benefactor_index_fk` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `benefactors_campaign_tags_tag_index_fk` FOREIGN KEY (`tag_index`) REFERENCES `campaign_tags` (`index`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=6665 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `beneficiaries`
--

DROP TABLE IF EXISTS `beneficiaries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `beneficiaries` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `user_index` int unsigned DEFAULT NULL,
  `beneficiary_admin_index` int unsigned DEFAULT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `bg_image_index` int unsigned DEFAULT NULL,
  `country_index` int unsigned DEFAULT NULL,
  `photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `bg_image_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `public_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mother_first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mother_last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `father_first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `father_last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `age_range` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `age` tinyint unsigned DEFAULT NULL,
  `date_of_birth` date DEFAULT NULL,
  `type` enum('social-store','to-campaign','no-campaign','other') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `applicant_first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `applicant_last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_iban` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_beneficiary` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `region` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `area` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `postal_code` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone2` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mobile` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mother_phone` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `father_phone` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `request_short` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `needs_short` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `condition_name` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `case_type` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `help_received` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `info` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `verification_status` enum('unverified','pending','verified','rejected') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT 'unverified',
  `is_public` tinyint unsigned DEFAULT '0',
  `show_public_age` tinyint unsigned DEFAULT '1',
  `show_public_area` tinyint unsigned DEFAULT '1',
  `show_public_name` tinyint unsigned DEFAULT '1',
  `show_avatar` tinyint unsigned DEFAULT '1',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `user_index` (`user_index`),
  KEY `is_active` (`is_active`),
  KEY `country_index` (`country_index`),
  KEY `created_by` (`created_by`),
  KEY `photo_index` (`photo_index`),
  KEY `beneficiary_admin_index` (`beneficiary_admin_index`),
  KEY `bg_image_index` (`bg_image_index`),
  CONSTRAINT `beneficiaries_ibfk_1` FOREIGN KEY (`user_index`) REFERENCES `users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `beneficiaries_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `beneficiaries_ibfk_3` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `beneficiaries_ibfk_4` FOREIGN KEY (`country_index`) REFERENCES `countries` (`id`),
  CONSTRAINT `beneficiaries_ibfk_5` FOREIGN KEY (`beneficiary_admin_index`) REFERENCES `beneficiary_administrators` (`index`),
  CONSTRAINT `beneficiaries_ibfk_6` FOREIGN KEY (`bg_image_index`) REFERENCES `files` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=409 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `beneficiary_administrators`
--

DROP TABLE IF EXISTS `beneficiary_administrators`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `beneficiary_administrators` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `user_index` int unsigned DEFAULT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mobile` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `user_index` (`user_index`),
  KEY `photo_index` (`photo_index`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  KEY `beneficiary_administrators_ibfk_4` (`modified_by`),
  KEY `beneficiary_administrators_ibfk_5` (`deleted_by`),
  CONSTRAINT `beneficiary_administrators_ibfk_1` FOREIGN KEY (`user_index`) REFERENCES `users` (`id`),
  CONSTRAINT `beneficiary_administrators_ibfk_2` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `beneficiary_administrators_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `beneficiary_administrators_ibfk_4` FOREIGN KEY (`modified_by`) REFERENCES `users` (`id`),
  CONSTRAINT `beneficiary_administrators_ibfk_5` FOREIGN KEY (`deleted_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `beneficiary_files`
--

DROP TABLE IF EXISTS `beneficiary_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `beneficiary_files` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `beneficiary_index` int unsigned NOT NULL,
  `file_index` int unsigned DEFAULT NULL,
  `file_url` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `type` varchar(255) DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `beneficiary_files_ibfk_1` (`beneficiary_index`),
  KEY `beneficiary_files_ibfk_2` (`file_index`),
  KEY `beneficiary_files_ibfk_3` (`created_by`),
  CONSTRAINT `beneficiary_files_ibfk_1` FOREIGN KEY (`beneficiary_index`) REFERENCES `beneficiaries` (`index`),
  CONSTRAINT `beneficiary_files_ibfk_2` FOREIGN KEY (`file_index`) REFERENCES `files` (`index`),
  CONSTRAINT `beneficiary_files_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `calendar_reminders`
--

DROP TABLE IF EXISTS `calendar_reminders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `calendar_reminders` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `campaign_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `date` int unsigned NOT NULL,
  `days_before` int unsigned NOT NULL DEFAULT '0',
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `status` enum('active','completed') NOT NULL DEFAULT 'active',
  `notification_at` int unsigned NOT NULL,
  `notification_sent_at` int unsigned DEFAULT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `calendar_reminders_id_uindex` (`id`),
  KEY `calendar_reminders_campaign_index_index` (`campaign_index`),
  KEY `calendar_reminders_campaign_id_index` (`campaign_id`),
  KEY `calendar_reminders_status_index` (`status`),
  KEY `calendar_reminders_date_index` (`date`),
  KEY `calendar_reminders_notify_pending_index` (`notification_at`,`notification_sent_at`),
  KEY `calendar_reminders_created_by_index` (`created_by`),
  CONSTRAINT `calendar_reminders_campaign_index_fk` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_action_comments`
--

DROP TABLE IF EXISTS `campaign_action_comments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_action_comments` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_action_index` int unsigned NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `content` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `status` enum('pending','approved','rejected') DEFAULT 'pending',
  `moderation_response` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_action_comments_id_uindex` (`id`),
  KEY `campaign_action_comments_action_index_index` (`campaign_action_index`),
  KEY `campaign_action_comments_benefactor_index_index` (`benefactor_index`),
  CONSTRAINT `campaign_action_comments_ibfk_1` FOREIGN KEY (`campaign_action_index`) REFERENCES `campaign_actions` (`index`),
  CONSTRAINT `campaign_action_comments_ibfk_2` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=18 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_actions`
--

DROP TABLE IF EXISTS `campaign_actions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_actions` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `title` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `content` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `content_eng` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `video_embed_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `social_link` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `used_in_socials` tinyint unsigned DEFAULT '1',
  `is_pinned` tinyint unsigned DEFAULT '0',
  `total_likes` int unsigned NOT NULL DEFAULT '0',
  `total_shares` int unsigned NOT NULL DEFAULT '0',
  `total_comments` int unsigned NOT NULL DEFAULT '0',
  `type` enum('internal','external') DEFAULT NULL,
  `internal_type` enum('contact','suggested-update','internal-update','text-suggestion','text-draft') DEFAULT NULL,
  `external_type` enum('new-campaign','campaign-continuation','continuation-with-update','campaign-video','campaign-completion','external-update','thank-you-video','obituary','sponsored-ad') DEFAULT NULL,
  `status` enum('open','closed') DEFAULT 'open',
  `advertisement_channel` enum('meta','google','tiktok','newsletter') DEFAULT NULL,
  `daily_budget` double DEFAULT NULL,
  `start_date` int unsigned DEFAULT NULL,
  `end_date` int unsigned DEFAULT NULL,
  `ad_campaign_name` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ad_campaign_type` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `campaign_actions_ibfk_1` (`campaign_index`),
  KEY `campaign_actions_ibfk_2` (`photo_index`),
  KEY `campaign_actions_ibfk_3` (`created_by`),
  CONSTRAINT `campaign_actions_ibfk_1` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `campaign_actions_ibfk_2` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `campaign_actions_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=814 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_comments`
--

DROP TABLE IF EXISTS `campaign_comments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_comments` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `content` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `status` enum('pending','approved','rejected') DEFAULT 'pending',
  `moderation_response` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_comments_id_uindex` (`id`),
  KEY `campaign_comments_campaign_index_index` (`campaign_index`),
  KEY `campaign_comments_benefactor_index_index` (`benefactor_index`),
  CONSTRAINT `campaign_comments_ibfk_1` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `campaign_comments_ibfk_2` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_files`
--

DROP TABLE IF EXISTS `campaign_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_files` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `document_index` int unsigned NOT NULL,
  `title` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` enum('files','gallery') DEFAULT 'files',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `campaign_files_ibfk_1` (`created_by`),
  KEY `campaign_files_ibfk_2` (`campaign_index`),
  KEY `campaign_files_ibfk_3` (`document_index`),
  CONSTRAINT `campaign_files_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `campaign_files_ibfk_2` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `campaign_files_ibfk_3` FOREIGN KEY (`document_index`) REFERENCES `files` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=1445 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_financial_goals`
--

DROP TABLE IF EXISTS `campaign_financial_goals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_financial_goals` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `campaign_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `total_amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `order_index` int unsigned NOT NULL,
  `status` enum('active','reached','completed') NOT NULL DEFAULT 'active',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_financial_goals_id_uindex` (`id`),
  UNIQUE KEY `campaign_financial_goals_campaign_order_uindex` (`campaign_index`,`order_index`),
  KEY `campaign_financial_goals_campaign_index_index` (`campaign_index`),
  KEY `campaign_financial_goals_campaign_id_index` (`campaign_id`),
  KEY `campaign_financial_goals_status_index` (`status`),
  KEY `campaign_financial_goals_order_index_index` (`order_index`),
  CONSTRAINT `campaign_financial_goals_campaign_index_fk` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=124 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_goals`
--

DROP TABLE IF EXISTS `campaign_goals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_goals` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `status` enum('active','completed') DEFAULT 'active',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_goals_id_uindex` (`id`),
  KEY `campaign_goals_campaign_index_index` (`campaign_index`),
  CONSTRAINT `campaign_goals_ibfk_1` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_media`
--

DROP TABLE IF EXISTS `campaign_media`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_media` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `embed_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `title` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `campaign_media_ibfk_1` (`created_by`),
  CONSTRAINT `campaign_media_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_tag_groups`
--

DROP TABLE IF EXISTS `campaign_tag_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_tag_groups` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `bg_color` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `border_color` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_tag_groups_id_uindex` (`id`),
  UNIQUE KEY `campaign_tag_groups_title_uindex` (`title`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaign_tags`
--

DROP TABLE IF EXISTS `campaign_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaign_tags` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `group_index` int unsigned NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaign_tags_id_uindex` (`id`),
  UNIQUE KEY `campaign_tags_group_index_title_uindex` (`group_index`,`title`),
  KEY `campaign_tags_group_index_index` (`group_index`),
  CONSTRAINT `campaign_tags_group_index_fk` FOREIGN KEY (`group_index`) REFERENCES `campaign_tag_groups` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=39 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaigns`
--

DROP TABLE IF EXISTS `campaigns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaigns` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `beneficiary_index` int unsigned DEFAULT NULL,
  `benefactor_index` int unsigned DEFAULT NULL,
  `benefactor_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `beneficiary_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `beneficiary_public_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `beneficiary_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `beneficiary_photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `external_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `rf_payment_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` enum('campaign','digital_piggy_bank') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `dpb_type` enum('general','campaign') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `related_campaign_id` char(36) DEFAULT NULL,
  `status` enum('in-check','send-to-doctor','send-for-translation','send-approvals','receive-approvals','receive-texts','active','video-to-be-shot','video-to-be-processed','video-to-be-published','video-published','completed','cancelled','expired','paused') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT 'in-check',
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `public_title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `friendly_wp_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `order` int unsigned DEFAULT NULL,
  `is_public` tinyint unsigned NOT NULL DEFAULT '0',
  `reels_order` int unsigned DEFAULT NULL,
  `reels_url` varchar(500) DEFAULT NULL,
  `reels_preview_video_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `checklist` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `support_plan` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `total_comments` int unsigned NOT NULL DEFAULT '0',
  `total_quick_donations` int unsigned NOT NULL DEFAULT '0',
  `total_shares` int unsigned NOT NULL DEFAULT '0',
  `financial_plan` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `short_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `long_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `main_video_embed_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `bank_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `bank_description_en` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `start_date` int unsigned DEFAULT NULL,
  `duration` int unsigned DEFAULT NULL,
  `end_date` int unsigned DEFAULT NULL,
  `commission_rate` decimal(18,4) DEFAULT NULL,
  `target_amount` decimal(18,4) DEFAULT NULL,
  `total_target_amount` decimal(18,4) DEFAULT NULL,
  `total_collected_campaign_funds` decimal(18,4) DEFAULT NULL,
  `total_collected_organization_funds` decimal(18,4) DEFAULT NULL,
  `total_collected_funds` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `total_expenses` decimal(18,4) DEFAULT NULL,
  `lowest_remainder_threshold` decimal(18,4) DEFAULT NULL,
  `has_outstanding` tinyint DEFAULT '0',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`),
  KEY `beneficiary_index` (`beneficiary_index`),
  KEY `created_by` (`created_by`),
  KEY `campaigns_ibfk_2` (`photo_index`),
  KEY `benefactor_index` (`benefactor_index`),
  KEY `campaigns_related_campaign_id_index` (`related_campaign_id`),
  CONSTRAINT `campaigns_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `campaigns_ibfk_2` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `campaigns_ibfk_3` FOREIGN KEY (`beneficiary_index`) REFERENCES `beneficiaries` (`index`),
  CONSTRAINT `campaigns_ibfk_4` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`),
  CONSTRAINT `campaigns_related_campaign_id_fk` FOREIGN KEY (`related_campaign_id`) REFERENCES `campaigns` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=487 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaigns_changes`
--

DROP TABLE IF EXISTS `campaigns_changes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaigns_changes` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `original_status` varchar(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `new_status` varchar(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `original_start_ts` int unsigned DEFAULT NULL,
  `new_start_ts` int unsigned DEFAULT NULL,
  `old_end_ts` int unsigned DEFAULT NULL,
  `new_end_ts` int unsigned DEFAULT NULL,
  `old_target_amount` double DEFAULT NULL,
  `new_target_amount` double DEFAULT NULL,
  `old_commission_rate` double DEFAULT NULL,
  `new_commission_rate` double DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=412261 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `campaigns_tags`
--

DROP TABLE IF EXISTS `campaigns_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaigns_tags` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned NOT NULL,
  `tag_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `campaigns_tags_id_uindex` (`id`),
  UNIQUE KEY `campaigns_tags_campaign_tag_uindex` (`campaign_index`,`tag_index`),
  KEY `campaigns_tags_tag_index_index` (`tag_index`),
  CONSTRAINT `campaigns_tags_campaign_index_fk` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `campaigns_tags_tag_index_fk` FOREIGN KEY (`tag_index`) REFERENCES `campaign_tags` (`index`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=491 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cart_items`
--

DROP TABLE IF EXISTS `cart_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cart_items` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `cart_index` int unsigned NOT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `type` varchar(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `message` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_quick_donation` tinyint unsigned DEFAULT '0',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `cart_items_id_uindex` (`id`),
  KEY `cart_items_cart_index_index` (`cart_index`),
  KEY `cart_items_campaign_index_index` (`campaign_index`),
  CONSTRAINT `cart_items_cart_index_fk` FOREIGN KEY (`cart_index`) REFERENCES `carts` (`index`),
  CONSTRAINT `cart_items_ibfk_2` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=5481 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `carts`
--

DROP TABLE IF EXISTS `carts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `carts` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `benefactor_index` int unsigned NOT NULL,
  `sum` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `carts_id_uindex` (`id`),
  KEY `carts_benefactor_index_index` (`benefactor_index`),
  CONSTRAINT `carts_ibfk_1` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=2105 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `countries`
--

DROP TABLE IF EXISTS `countries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `countries` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `code` char(2) DEFAULT NULL COMMENT 'ISO 3166-1 alpha-2',
  `iso3` char(3) DEFAULT NULL COMMENT 'ISO 3166-1 alpha-3',
  `top_level_domain` char(6) DEFAULT NULL,
  `fips` char(2) NOT NULL,
  `e164` char(15) NOT NULL,
  `prefix` char(15) NOT NULL,
  `continent` varchar(45) NOT NULL,
  `capital` varchar(45) NOT NULL,
  `time_zone` varchar(45) NOT NULL,
  `currency` varchar(45) NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `code` (`code`),
  KEY `iso3` (`iso3`),
  KEY `is_active` (`is_active`)
) ENGINE=InnoDB AUTO_INCREMENT=245 DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `currencies`
--

DROP TABLE IF EXISTS `currencies`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `currencies` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(3) DEFAULT NULL,
  `title` varchar(64) DEFAULT NULL,
  `decimals` int DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `symbol` varchar(5) NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `is_active` (`is_active`)
) ENGINE=InnoDB AUTO_INCREMENT=169 DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `data_activities`
--

DROP TABLE IF EXISTS `data_activities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `data_activities` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `type` enum('delete','undelete','activate','deactivate') COLLATE utf8mb4_general_ci DEFAULT NULL,
  `user_id` int unsigned DEFAULT NULL,
  `timestamp` int unsigned DEFAULT NULL,
  `table` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `record_id` int unsigned DEFAULT NULL,
  `object` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `model` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `note` text COLLATE utf8mb4_general_ci,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=90300 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `email_confirmations`
--

DROP TABLE IF EXISTS `email_confirmations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `email_confirmations` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int unsigned DEFAULT NULL,
  `email` char(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `code` char(32) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `client_identifier` char(32) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `confirmed` tinyint unsigned DEFAULT NULL,
  `expire_at` int DEFAULT NULL,
  `attempts` int unsigned NOT NULL DEFAULT '0',
  `type` enum('confirmation','reset') NOT NULL DEFAULT 'confirmation',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `is_active` (`is_active`),
  KEY `code` (`code`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `email_confirmations_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=43455 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `files`
--

DROP TABLE IF EXISTS `files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `files` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` varchar(255) DEFAULT NULL,
  `size` int DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`)
) ENGINE=InnoDB AUTO_INCREMENT=8319 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `history`
--

DROP TABLE IF EXISTS `history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `history` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `type_id` int unsigned DEFAULT NULL,
  `user_id` int unsigned DEFAULT NULL,
  `timestamp` int unsigned DEFAULT NULL,
  `table` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `record_id` int unsigned DEFAULT NULL,
  `attribute` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `object` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `old_value` text COLLATE utf8mb4_general_ci,
  `value` text COLLATE utf8mb4_general_ci,
  `ref_relationship` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ref_value` text COLLATE utf8mb4_general_ci,
  PRIMARY KEY (`id`),
  KEY `type_id` (`type_id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `history_ibfk_1` FOREIGN KEY (`type_id`) REFERENCES `history_types` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `history_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=15519373 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `history_types`
--

DROP TABLE IF EXISTS `history_types`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `history_types` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(128) COLLATE utf8mb4_general_ci DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoice_categories`
--

DROP TABLE IF EXISTS `invoice_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoice_categories` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_external` tinyint unsigned DEFAULT '0',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  CONSTRAINT `invoice_categories_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoices`
--

DROP TABLE IF EXISTS `invoices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoices` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `provider_index` int unsigned DEFAULT NULL,
  `provider_account_index` int unsigned DEFAULT NULL,
  `benefactor_index` int unsigned DEFAULT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `pnl_fund_index` int unsigned DEFAULT NULL,
  `attachment_index` int unsigned DEFAULT NULL,
  `provider_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `benefactor_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `campaign_title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `provider_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `provider_account_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `benefactor_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `campaign_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `pnl_fund_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `beneficiary_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `category_index` int unsigned DEFAULT NULL,
  `external_category_index` int unsigned DEFAULT NULL,
  `attachment_url` varchar(2048) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` enum('expenses','expenses-awaiting-document','incoming','open','no-document','proof-of-service') DEFAULT NULL,
  `category` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` enum('pending','awaiting-payment','paid','paid-with-cash','partial','cancelled','credit','paid-with-card','paid-with-spendeo') DEFAULT 'pending',
  `tax_authority` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `tax_id_number` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `subtotal` decimal(18,4) DEFAULT NULL,
  `tax` decimal(18,4) DEFAULT NULL,
  `paid` decimal(18,4) DEFAULT '0.0000',
  `discount` decimal(18,4) DEFAULT NULL,
  `total` decimal(18,4) DEFAULT NULL,
  `vat` decimal(18,4) DEFAULT NULL,
  `series` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mark` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `rf_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `intra_communal` tinyint(1) DEFAULT '0',
  `tax_withholding` tinyint(1) DEFAULT '0',
  `issued_at` int unsigned DEFAULT NULL,
  `used_at` int unsigned DEFAULT NULL,
  `due_at` int unsigned DEFAULT NULL,
  `paid_at` int unsigned DEFAULT NULL,
  `latest_payment_at` int unsigned DEFAULT NULL,
  `closed_at` int unsigned DEFAULT NULL,
  `period_from` int unsigned DEFAULT NULL,
  `period_to` int unsigned DEFAULT NULL,
  `closed` tinyint unsigned DEFAULT '0',
  `transactions_count` tinyint unsigned DEFAULT '0',
  `out_of_budget` tinyint unsigned DEFAULT '0',
  `paid_by` int unsigned DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  KEY `invoices_ibfk_2` (`benefactor_index`),
  KEY `invoices_ibfk_3` (`provider_index`),
  KEY `invoices_ibfk_4` (`campaign_index`),
  KEY `invoices_ibfk_5` (`attachment_index`),
  KEY `invoices_ibfk_6` (`category_index`),
  KEY `invoices_ibfk_7` (`external_category_index`),
  KEY `paid_by` (`paid_by`),
  KEY `pnl_fund_index` (`created_by`),
  KEY `invoices_ibfk_8` (`pnl_fund_index`),
  CONSTRAINT `invoices_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `invoices_ibfk_2` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`),
  CONSTRAINT `invoices_ibfk_3` FOREIGN KEY (`provider_index`) REFERENCES `providers` (`index`),
  CONSTRAINT `invoices_ibfk_4` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `invoices_ibfk_5` FOREIGN KEY (`attachment_index`) REFERENCES `files` (`index`),
  CONSTRAINT `invoices_ibfk_6` FOREIGN KEY (`category_index`) REFERENCES `invoice_categories` (`index`),
  CONSTRAINT `invoices_ibfk_7` FOREIGN KEY (`external_category_index`) REFERENCES `invoice_categories` (`index`),
  CONSTRAINT `invoices_ibfk_8` FOREIGN KEY (`pnl_fund_index`) REFERENCES `pnl_transactions` (`index`),
  CONSTRAINT `invoices_ibfk_9` FOREIGN KEY (`paid_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5928 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `languages`
--

DROP TABLE IF EXISTS `languages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `languages` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `code` char(15) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `iso3code` char(3) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `name` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `is_active` (`is_active`),
  KEY `code` (`code`)
) ENGINE=InnoDB AUTO_INCREMENT=657 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `news_article_tags`
--

DROP TABLE IF EXISTS `news_article_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `news_article_tags` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `bg_color` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `text_color` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `title` (`title`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `news_articles`
--

DROP TABLE IF EXISTS `news_articles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `news_articles` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `content` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `video_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` enum('draft','published') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'draft',
  `published_at` int unsigned DEFAULT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `status` (`status`),
  KEY `published_at` (`published_at`)
) ENGINE=InnoDB AUTO_INCREMENT=51 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `news_articles_gallery`
--

DROP TABLE IF EXISTS `news_articles_gallery`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `news_articles_gallery` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `news_article_index` int unsigned NOT NULL,
  `document_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `news_article_document_unique` (`news_article_index`,`document_index`),
  KEY `news_article_index` (`news_article_index`),
  KEY `document_index` (`document_index`),
  CONSTRAINT `news_articles_gallery_article_index_fk` FOREIGN KEY (`news_article_index`) REFERENCES `news_articles` (`index`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `news_articles_gallery_document_index_fk` FOREIGN KEY (`document_index`) REFERENCES `files` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=43 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `news_articles_tags`
--

DROP TABLE IF EXISTS `news_articles_tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `news_articles_tags` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `news_article_index` int unsigned NOT NULL,
  `tag_index` int unsigned NOT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `news_article_tag_unique` (`news_article_index`,`tag_index`),
  KEY `news_article_index` (`news_article_index`),
  KEY `tag_index` (`tag_index`),
  CONSTRAINT `news_articles_tags_article_index_fk` FOREIGN KEY (`news_article_index`) REFERENCES `news_articles` (`index`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `news_articles_tags_tag_index_fk` FOREIGN KEY (`tag_index`) REFERENCES `news_article_tags` (`index`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=85 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `occupations`
--

DROP TABLE IF EXISTS `occupations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `occupations` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=279 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_items`
--

DROP TABLE IF EXISTS `order_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_items` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `order_index` int unsigned NOT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `type` varchar(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `message` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_quick_donation` tinyint unsigned DEFAULT '0',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `order_items_id_uindex` (`id`),
  KEY `order_items_order_index_index` (`order_index`),
  KEY `order_items_campaign_index_index` (`campaign_index`),
  CONSTRAINT `order_items_campaign_index_fk` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `order_items_order_index_fk` FOREIGN KEY (`order_index`) REFERENCES `orders` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=73482 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `orders` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `external_order_id` varchar(20) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `sum` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `status` enum('pending','completed','cancelled','partially-paid') CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL DEFAULT 'pending',
  `payment_method` varchar(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL DEFAULT 'bank-deposit',
  `payment_fee_fixed_amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `payment_fee_percentage_amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `payment_fee_total_amount` decimal(18,4) NOT NULL DEFAULT '0.0000',
  `is_anonymous` tinyint(1) DEFAULT '0',
  `viva_order_code` varchar(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `viva_redirect_url` varchar(1024) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `viva_state` text CHARACTER SET latin1 COLLATE latin1_swedish_ci,
  `viva_success_url` varchar(1024) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `viva_failure_url` varchar(1024) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `viva_transaction_id` varchar(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `orders_id_uindex` (`id`),
  UNIQUE KEY `orders_external_order_id_uindex` (`external_order_id`),
  KEY `orders_status_index` (`status`)
) ENGINE=InnoDB AUTO_INCREMENT=35076 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `organization_members`
--

DROP TABLE IF EXISTS `organization_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `organization_members` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) NOT NULL,
  `user_index` int unsigned DEFAULT NULL,
  `photo_index` int unsigned DEFAULT NULL,
  `photo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
  `first_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone` varchar(100) DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `user_index` (`user_index`),
  KEY `photo_index` (`photo_index`),
  KEY `is_active` (`is_active`),
  KEY `organization_members_ibfk_3` (`created_by`),
  KEY `organization_members_ibfk_4` (`modified_by`),
  KEY `organization_members_ibfk_5` (`deleted_by`),
  CONSTRAINT `organization_members_ibfk_1` FOREIGN KEY (`user_index`) REFERENCES `users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `organization_members_ibfk_2` FOREIGN KEY (`photo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `organization_members_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `organization_members_ibfk_4` FOREIGN KEY (`modified_by`) REFERENCES `users` (`id`),
  CONSTRAINT `organization_members_ibfk_5` FOREIGN KEY (`deleted_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=24 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `organization_pnl_funds`
--

DROP TABLE IF EXISTS `organization_pnl_funds`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `organization_pnl_funds` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `organization_index` int unsigned DEFAULT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `type` enum('campaigns','campaigns_general','campaigns_remainder','organization_general','organization_marketing','cash') DEFAULT 'campaigns',
  `balance` decimal(18,4) DEFAULT '0.0000',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  CONSTRAINT `organization_pnl_funds_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pnl_transactions`
--

DROP TABLE IF EXISTS `pnl_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pnl_transactions` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `pnl_fund_index` int unsigned DEFAULT NULL,
  `source_transaction_index` int unsigned DEFAULT NULL,
  `source_invoice_index` int unsigned DEFAULT NULL,
  `type` enum('incoming','expense') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` enum('pending','completed','cancelled','campaign-missing') DEFAULT 'completed',
  `invoice_status` varchar(250) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `category_index` int unsigned DEFAULT NULL,
  `percentage` decimal(18,4) DEFAULT NULL,
  `original_amount` decimal(18,4) DEFAULT NULL,
  `amount` decimal(18,4) DEFAULT NULL,
  `completed_at` int unsigned DEFAULT NULL,
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `campaign_fund_tx` (`campaign_index`,`pnl_fund_index`,`source_transaction_index`),
  KEY `pnl_transactions_ibfk_2` (`pnl_fund_index`),
  KEY `pnl_transactions_ibfk_3` (`source_transaction_index`),
  KEY `pnl_transactions_ibfk_5` (`created_by`),
  KEY `pnl_transactions_ibfk_4` (`source_invoice_index`),
  KEY `category_index` (`category_index`),
  CONSTRAINT `pnl_transactions_ibfk_1` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `pnl_transactions_ibfk_2` FOREIGN KEY (`pnl_fund_index`) REFERENCES `organization_pnl_funds` (`index`),
  CONSTRAINT `pnl_transactions_ibfk_3` FOREIGN KEY (`source_transaction_index`) REFERENCES `transactions` (`index`),
  CONSTRAINT `pnl_transactions_ibfk_4` FOREIGN KEY (`source_invoice_index`) REFERENCES `invoices` (`index`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `pnl_transactions_ibfk_5` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `pnl_transactions_ibfk_6` FOREIGN KEY (`category_index`) REFERENCES `transaction_categories` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=542185 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `provider_accounts`
--

DROP TABLE IF EXISTS `provider_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_accounts` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `provider_index` int unsigned NOT NULL,
  `name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `owner_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `iban` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `swift_bic` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_default` tinyint unsigned DEFAULT '0',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `provider_index` (`provider_index`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  CONSTRAINT `provider_accounts_ibfk_1` FOREIGN KEY (`provider_index`) REFERENCES `providers` (`index`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `provider_accounts_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=601 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `providers`
--

DROP TABLE IF EXISTS `providers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `providers` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `user_index` int unsigned DEFAULT NULL,
  `type_index` int unsigned DEFAULT NULL,
  `logo_index` int unsigned DEFAULT NULL,
  `bank_index` int unsigned DEFAULT NULL,
  `country_index` int unsigned DEFAULT NULL,
  `occupation_index` int unsigned DEFAULT NULL,
  `logo_url` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `first_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `corporate_title` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `company_name` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `company_reg_number` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `tax_id_number` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `tax_authority` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `city` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address1` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `address2` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `postal_code` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `region` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `phone` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mobile` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `website` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `account_iban` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_beneficiary` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `verification_status` enum('unverified','pending','verified','rejected') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT 'unverified',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `user_index` (`user_index`),
  KEY `is_active` (`is_active`),
  KEY `country_index` (`country_index`),
  KEY `created_by` (`created_by`),
  KEY `logo_index` (`logo_index`),
  KEY `providers_ibfk_5` (`occupation_index`),
  CONSTRAINT `providers_ibfk_1` FOREIGN KEY (`user_index`) REFERENCES `users` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `providers_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `providers_ibfk_3` FOREIGN KEY (`logo_index`) REFERENCES `files` (`index`),
  CONSTRAINT `providers_ibfk_4` FOREIGN KEY (`country_index`) REFERENCES `countries` (`id`),
  CONSTRAINT `providers_ibfk_5` FOREIGN KEY (`occupation_index`) REFERENCES `occupations` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=1041 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `runtime_errors`
--

DROP TABLE IF EXISTS `runtime_errors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `runtime_errors` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` int unsigned DEFAULT NULL,
  `title` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `file` char(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `line` int DEFAULT NULL,
  `error_type` char(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `server_name` char(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `execution_script` text CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `pid` int DEFAULT NULL,
  `ip_address` char(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `created_at` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=85704 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `settings`
--

DROP TABLE IF EXISTS `settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `settings` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `keyword` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `is_active` tinyint unsigned NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `states`
--

DROP TABLE IF EXISTS `states`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `states` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `code` char(2) NOT NULL,
  `name` varchar(30) NOT NULL,
  `country_id` int unsigned NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `states_ifbk_1` (`country_id`),
  CONSTRAINT `states_ifbk_1` FOREIGN KEY (`country_id`) REFERENCES `countries` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=60 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `timezones`
--

DROP TABLE IF EXISTS `timezones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `timezones` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_ci NOT NULL,
  `value` varchar(255) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `is_active` (`is_active`),
  KEY `code` (`code`)
) ENGINE=InnoDB AUTO_INCREMENT=90 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `transaction_categories`
--

DROP TABLE IF EXISTS `transaction_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `transaction_categories` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` varchar(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_external` tinyint unsigned DEFAULT '0',
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  CONSTRAINT `transaction_categories_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `transaction_invoice`
--

DROP TABLE IF EXISTS `transaction_invoice`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `transaction_invoice` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `transaction_index` int unsigned NOT NULL,
  `invoice_index` int unsigned NOT NULL,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`index`),
  KEY `transaction_index` (`transaction_index`),
  KEY `invoice_index` (`invoice_index`),
  CONSTRAINT `transaction_invoice_ibfk_1` FOREIGN KEY (`transaction_index`) REFERENCES `transactions` (`index`) ON UPDATE CASCADE,
  CONSTRAINT `transaction_invoice_ibfk_2` FOREIGN KEY (`invoice_index`) REFERENCES `invoices` (`index`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=3427 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `transactions`
--

DROP TABLE IF EXISTS `transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `transactions` (
  `index` int unsigned NOT NULL AUTO_INCREMENT,
  `id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL,
  `campaign_index` int unsigned DEFAULT NULL,
  `csv_index` int unsigned DEFAULT NULL,
  `bank_index` int unsigned DEFAULT NULL,
  `provider_index` int unsigned DEFAULT NULL,
  `benefactor_index` int unsigned DEFAULT NULL,
  `category_index` int unsigned DEFAULT NULL,
  `external_category_index` int unsigned DEFAULT NULL,
  `provider_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `benefactor_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `beneficiary_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `order_id` char(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `external_order_id` varchar(20) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `order_item_index` int unsigned DEFAULT NULL,
  `campaign_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `reversal_transaction_id` char(36) CHARACTER SET latin1 COLLATE latin1_general_ci DEFAULT NULL,
  `transfer_from_account_index` int unsigned DEFAULT NULL,
  `transfer_to_account_index` int unsigned DEFAULT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `message` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `identifier` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `identifier_short` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `type` enum('incoming','expense','incoming-interbank-transfer','outgoing-interbank-transfer','return','withdrawal','platform-bank','incoming-campaign-transfer','outgoing-campaign-transfer','incoming-return','incoming-return-reversal','charge-return','charge-return-reversal') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `creation_type` enum('manual','imported','repeating','web') CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  `expense_type` enum('campaign-payment','financial-aid','campaign-general','invoice-payment','ads','fuel','electricity','bank-commission','legal-services','accounting-services','shipping','payroll','insurance','tax-authority','vehicle','office-supplies','office-equipment','business-general','marketing-services','software-development','personnel-travel','anykind','telephony-internet','government','cytec','vehicle-insurance','regulatory','security-technician-services') DEFAULT NULL,
  `incoming_type` enum('personal','business','sms','under-1000','above-1000','general','wholesale','retail','service','close-service') DEFAULT NULL,
  `status` enum('pending','completed','cancelled','campaign-missing') DEFAULT NULL,
  `sms_provider` enum('vodafone','cosmote','nova') DEFAULT NULL,
  `csv_line` int unsigned DEFAULT NULL,
  `is_public` tinyint unsigned DEFAULT '0',
  `is_recurring` tinyint unsigned DEFAULT '0',
  `is_quick_donation` tinyint unsigned DEFAULT '0',
  `is_emergency` tinyint unsigned DEFAULT '0',
  `card_charged` tinyint unsigned DEFAULT '0',
  `platform_related` tinyint unsigned DEFAULT '0',
  `invoices_count` tinyint unsigned DEFAULT '0',
  `out_of_budget` tinyint unsigned DEFAULT '0',
  `amount` decimal(18,4) DEFAULT NULL,
  `fee` decimal(18,4) DEFAULT '0.0000',
  `total_amount` decimal(18,4) DEFAULT NULL,
  `bank_commission` decimal(18,4) DEFAULT NULL,
  `organization_amount` decimal(18,4) DEFAULT NULL,
  `campaign_amount` decimal(18,4) DEFAULT NULL,
  `campaign_commission_rate` decimal(18,4) DEFAULT NULL,
  `completed_at` int unsigned DEFAULT NULL,
  `woocommerce_resp` text,
  `is_active` tinyint unsigned DEFAULT '1',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  `viva_transaction_id` varchar(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT NULL,
  PRIMARY KEY (`index`),
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `ux_identifier_campaign_amount` (`identifier`,`campaign_index`,`amount`),
  KEY `is_active` (`is_active`),
  KEY `created_by` (`created_by`),
  KEY `completed_at` (`completed_at`),
  KEY `is_public` (`is_public`),
  KEY `is_emergency` (`is_emergency`),
  KEY `card_charged` (`card_charged`),
  KEY `has_invoice` (`invoices_count`),
  KEY `type` (`type`),
  KEY `transactions_ibfk_2` (`campaign_index`),
  KEY `transactions_ibfk_3` (`bank_index`),
  KEY `transactions_ibfk_4` (`provider_index`),
  KEY `transactions_ibfk_5` (`benefactor_index`),
  KEY `transactions_ibfk_6` (`category_index`),
  KEY `transactions_ibfk_7` (`external_category_index`),
  KEY `transactions_ibfk_8` (`transfer_from_account_index`),
  KEY `transactions_ibfk_9` (`transfer_to_account_index`),
  KEY `identifier` (`identifier`),
  KEY `transactions_order_id_index` (`order_id`),
  KEY `transactions_external_order_id_index` (`external_order_id`),
  KEY `transactions_order_item_index_index` (`order_item_index`),
  CONSTRAINT `transactions_ibfk_0` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `transactions_ibfk_2` FOREIGN KEY (`campaign_index`) REFERENCES `campaigns` (`index`),
  CONSTRAINT `transactions_ibfk_3` FOREIGN KEY (`bank_index`) REFERENCES `bank_accounts` (`index`),
  CONSTRAINT `transactions_ibfk_4` FOREIGN KEY (`provider_index`) REFERENCES `providers` (`index`),
  CONSTRAINT `transactions_ibfk_5` FOREIGN KEY (`benefactor_index`) REFERENCES `benefactors` (`index`),
  CONSTRAINT `transactions_ibfk_6` FOREIGN KEY (`category_index`) REFERENCES `transaction_categories` (`index`),
  CONSTRAINT `transactions_ibfk_7` FOREIGN KEY (`external_category_index`) REFERENCES `transaction_categories` (`index`),
  CONSTRAINT `transactions_order_id_fk` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`),
  CONSTRAINT `transactions_order_item_index_fk` FOREIGN KEY (`order_item_index`) REFERENCES `order_items` (`index`)
) ENGINE=InnoDB AUTO_INCREMENT=985166 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
  `device_token` char(200) DEFAULT NULL,
  `password` char(60) NOT NULL,
  `first_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `gender` enum('FE','MA','OT','NA') DEFAULT NULL,
  `type` enum('1','2','3','4') DEFAULT NULL,
  `registered_from` enum('website','newsletter','adwords','facebook','instagram') DEFAULT NULL,
  `language_id` int unsigned DEFAULT NULL,
  `currency_id` int unsigned DEFAULT NULL,
  `timezone_id` int unsigned DEFAULT NULL,
  `must_change_password` tinyint unsigned DEFAULT '0',
  `is_active` tinyint unsigned DEFAULT '0',
  `created_at` int unsigned DEFAULT NULL,
  `modified_at` int unsigned DEFAULT NULL,
  `deleted_at` int unsigned DEFAULT NULL,
  `created_by` int unsigned DEFAULT NULL,
  `modified_by` int unsigned DEFAULT NULL,
  `deleted_by` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `is_active` (`is_active`),
  KEY `users_ibfk_1` (`language_id`),
  KEY `users_ibfk_2` (`currency_id`),
  KEY `users_ibfk_3` (`timezone_id`),
  CONSTRAINT `users_ibfk_1` FOREIGN KEY (`language_id`) REFERENCES `languages` (`id`),
  CONSTRAINT `users_ibfk_2` FOREIGN KEY (`currency_id`) REFERENCES `currencies` (`id`),
  CONSTRAINT `users_ibfk_3` FOREIGN KEY (`timezone_id`) REFERENCES `timezones` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=58193 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping routines for database 'deedspot'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-05-08 20:35:19
