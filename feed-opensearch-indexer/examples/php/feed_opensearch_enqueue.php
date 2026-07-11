<?php

declare(strict_types=1);

/**
 * Minimal app-side enqueue helper for the PA Feed OpenSearch indexer.
 *
 * Contract:
 * - entity_id is campaign_actions.`index`, not campaigns.`index`.
 * - action is producer intent:
 *   I = source row was created and should be indexed
 *   U = source row changed and should be refreshed from MySQL
 *   D = source row was deleted and should be removed from OpenSearch
 *
 * The worker decides the final index_status:
 * - indexed = document exists in OpenSearch
 * - deleted = document was removed or the refreshed source row is no longer feed_visible
 * - failed = processing failed after retries
 */
final class FeedOpenSearchIndexerQueue
{
    private const ENTITY_CAMPAIGN_ACTION = 'campaign_action';
    private const ACTION_INSERT = 'I';
    private const ACTION_UPDATE = 'U';
    private const ACTION_DELETE = 'D';

    private string $jobsTable;

    public function __construct(private PDO $pdo, string $indexerDatabase = 'pa_opensearch_indexer')
    {
        $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        if (!preg_match('/^[A-Za-z0-9_]+$/', $indexerDatabase)) {
            throw new InvalidArgumentException('indexerDatabase must contain only letters, numbers, and underscores');
        }

        $this->jobsTable = sprintf('`%s`.`search_index_jobs`', $indexerDatabase);
    }

    public function enqueueCampaignActionInsert(int|string $campaignActionIndex, int $priority = 0, string $source = 'app'): int
    {
        return $this->enqueueCampaignAction($campaignActionIndex, self::ACTION_INSERT, $priority, $source);
    }

    public function enqueueCampaignActionUpdate(int|string $campaignActionIndex, int $priority = 0, string $source = 'app'): int
    {
        return $this->enqueueCampaignAction($campaignActionIndex, self::ACTION_UPDATE, $priority, $source);
    }

    public function enqueueCampaignActionDelete(int|string $campaignActionIndex, int $priority = 0, string $source = 'app'): int
    {
        return $this->enqueueCampaignAction($campaignActionIndex, self::ACTION_DELETE, $priority, $source);
    }

    public function enqueueCampaignAction(
        int|string $campaignActionIndex,
        string $action,
        int $priority = 0,
        string $source = 'app'
    ): int {
        $campaignActionIndex = trim((string) $campaignActionIndex);
        $source = trim($source);

        if ($campaignActionIndex === '') {
            throw new InvalidArgumentException('campaignActionIndex cannot be empty');
        }

        if (!in_array($action, [self::ACTION_INSERT, self::ACTION_UPDATE, self::ACTION_DELETE], true)) {
            throw new InvalidArgumentException('action must be I, U, or D');
        }

        if ($source === '') {
            throw new InvalidArgumentException('source cannot be empty');
        }

        if (strlen($source) > 32) {
            throw new InvalidArgumentException('source must fit search_index_jobs.source VARCHAR(32)');
        }

        $stmt = $this->pdo->prepare(
            'INSERT INTO ' . $this->jobsTable . '
                (entity_type, entity_id, action, priority, source)
             VALUES
                (:entity_type, :entity_id, :action, :priority, :source)'
        );

        $stmt->execute([
            ':entity_type' => self::ENTITY_CAMPAIGN_ACTION,
            ':entity_id' => $campaignActionIndex,
            ':action' => $action,
            ':priority' => $priority,
            ':source' => $source,
        ]);

        return (int) $this->pdo->lastInsertId();
    }
}

/*
Example usage with the indexer database directly:

$pdo = new PDO(
    'mysql:host=127.0.0.1;port=3306;dbname=pa_opensearch_indexer;charset=utf8mb4',
    'app_user_with_insert_grant',
    'secret'
);

$queue = new FeedOpenSearchIndexerQueue($pdo);
$queue->enqueueCampaignActionUpdate(528);
$queue->enqueueCampaignActionDelete(167);

Recommended app transaction shape when the app and indexer DB are on the same
MySQL server and can safely share one transaction:

$pdo->beginTransaction();
try {
    // Update deedspot.campaign_actions here.
    $queue->enqueueCampaignActionUpdate($campaignActionIndex);
    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    throw $e;
}
*/
