-- Read only. Run against the intended deployment database with a read-only account.
SELECT destination_id, status, COUNT(*) AS events,
       MIN(created_at) AS oldest_created_at, MAX(attempts) AS maximum_attempts
FROM fuda_push_outbox GROUP BY destination_id, status;

SELECT event_id, destination_id, device_type, device_id, event_type,
       status, attempts, next_attempt_at, lease_until, last_outcome, last_http_status
FROM fuda_push_outbox WHERE status IN ('PENDING', 'IN_FLIGHT')
ORDER BY created_at LIMIT 100;
