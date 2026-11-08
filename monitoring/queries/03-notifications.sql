SELECT id, event_id, recipient_id, event_type, category, read_at, occurred_at
FROM demo_monitor.notifications
ORDER BY occurred_at DESC LIMIT 10;
