# Pod replacement result

- Probe: 20 req/s for 100 s to `http://gateway:8000/api/v1/me/profile`
- Sent 2000, succeeded 2000, failed 0 (success rate 1.0)
- Latency p50 11 ms, p95 23 ms, max 1263 ms
- DNS before: `profile -> 10.43.28.236 | profile.cra.svc.cluster.local -> 10.43.28.236`
- DNS after:  `profile -> 10.43.28.236 | profile.cra.svc.cluster.local -> 10.43.28.236`
- Endpoints before: 10.42.0.33, 10.42.0.34
- Endpoints after:  10.42.0.36, 10.42.0.37
- Failures: none

See timeline.log, pod-events.log and probe.log for the per-second record.
