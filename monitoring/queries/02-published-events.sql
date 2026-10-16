SELECT id AS event_id, event_type, published_at, created_at
FROM demo_monitor.outbox_events
ORDER BY created_at DESC LIMIT 10;
