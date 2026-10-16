SELECT id, title, status, starts_at, distance_km, participant_limit
FROM demo_monitor.runs
ORDER BY created_at DESC LIMIT 10;
