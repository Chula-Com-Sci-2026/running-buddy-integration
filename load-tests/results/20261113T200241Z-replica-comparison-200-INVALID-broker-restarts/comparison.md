| Metric | replicas-1 | replicas-2 |
|---|---|---|
| Replicas (gateway/profile/scheduling/conditions/discovery) | 1/1/1/1/1 | 2/2/2/2/2 |
| Duration (s) | 571 | 572 |
| Peak VUs | 200 | 200 |
| HTTP requests (total) | 5,299 | 5,774 |
| Throughput (req/s, whole run) | 9.3 | 10.1 |
| Iterations | 5,081 | 5,646 |
| Dropped iterations | 0 | 0 |
| runner_search requests | 1,551 | 1,212 |
| runner_search med (ms) | 4,840 | 10,114 |
| runner_search p(95) (ms) | 14,235 | 14,812 |
| runner_search p(99) (ms) | 17,275 | 18,571 |
| runner_search max (ms) | 20,796 | 21,537 |
| runner_search failed (%) | 75.63 | 78.55 |
| runner_search checks passed (%) | 24.37 | 21.45 |
| nearby_runs requests | 2,022 | 1,645 |
| nearby_runs med (ms) | 22,143 | 7,431 |
| nearby_runs p(95) (ms) | 44,191 | 33,590 |
| nearby_runs p(99) (ms) | 53,904 | 37,855 |
| nearby_runs max (ms) | 58,195 | 42,132 |
| nearby_runs failed (%) | 43.42 | 15.44 |
| nearby_runs checks passed (%) | 56.58 | 84.56 |
| weather_cached requests | 1,511 | 1,176 |
| weather_cached med (ms) | 932 | 775 |
| weather_cached p(95) (ms) | 15,297 | 10,529 |
| weather_cached p(99) (ms) | 20,942 | 21,269 |
| weather_cached max (ms) | 22,314 | 26,433 |
| weather_cached failed (%) | 0.20 | 0.00 |
| weather_cached checks passed (%) | 99.80 | 100.00 |
| Peak node CPU (millicores, 8 vCPU VM) | 6,880 | 5,516 |
| Peak node CPU (%) | 86 | 68 |
| Peak CPU gateway (millicores, all pods) | 881 | 486 |
| Peak CPU profile (millicores, all pods) | 942 | 733 |
| Peak CPU scheduling (millicores, all pods) | 889 | 364 |
| Peak CPU conditions (millicores, all pods) | 78 | 71 |
| Peak CPU discovery (millicores, all pods) | 163 | 138 |
| Peak CPU identity (millicores, all pods) | 946 | 316 |
| Peak CPU postgres (millicores, all pods) | 723 | 304 |
| Peak CPU k6 (millicores, all pods) | 451 | 233 |
| Threshold checks{op:nearby_runs} rate>0.99 | FAIL | FAIL |
| Threshold checks{op:runner_search} rate>0.99 | FAIL | FAIL |
| Threshold checks{op:weather_cached} rate>0.99 | PASS | PASS |
| Threshold http_req_duration{op:nearby_runs} p(95)<1000 | FAIL | FAIL |
| Threshold http_req_duration{op:runner_search} p(95)<2000 | FAIL | FAIL |
| Threshold http_req_duration{op:weather_cached} p(95)<300 | FAIL | FAIL |
| Threshold http_req_failed{op:nearby_runs} rate<0.01 | FAIL | FAIL |
| Threshold http_req_failed{op:runner_search} rate<0.01 | FAIL | FAIL |
| Threshold http_req_failed{op:weather_cached} rate<0.01 | PASS | PASS |
| Threshold weather_cache_miss count<=10 | PASS | PASS |
