SELECT id, sender_id, recipient_id, status, created_at
FROM demo_monitor.buddy_requests
ORDER BY created_at DESC LIMIT 10;
