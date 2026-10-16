SELECT id, event_id, recipient_id, type, is_read, created_at
FROM demo_monitor.notifications
ORDER BY created_at DESC LIMIT 10;
