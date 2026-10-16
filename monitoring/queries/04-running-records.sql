SELECT id, run_id, runner_id, distance_meters, duration_seconds, occurred_at
FROM demo_monitor.running_records
ORDER BY created_at DESC LIMIT 10;
