| Metric | replicas-2 |
|---|---|
| Replicas (gateway/profile/scheduling/conditions/discovery) | 2/2/2/2/2 |
| Duration (s) | 556 |
| Peak VUs | 500 |
| HTTP requests (total) | 44,479 |
| Throughput (req/s, whole run) | 80.1 |
| Iterations | 43,964 |
| Dropped iterations | 0 |
| runner_search requests | 13,093 |
| runner_search med (ms) | 153 |
| runner_search p(95) (ms) | 10,003 |
| runner_search p(99) (ms) | 10,178 |
| runner_search max (ms) | 10,786 |
| runner_search failed (%) | 55.89 |
| runner_search checks passed (%) | 44.11 |
| nearby_runs requests | 17,579 |
| nearby_runs med (ms) | 510 |
| nearby_runs p(95) (ms) | 2,619 |
| nearby_runs p(99) (ms) | 3,263 |
| nearby_runs max (ms) | 4,496 |
| nearby_runs failed (%) | 0.00 |
| nearby_runs checks passed (%) | 100.00 |
| weather_cached requests | 13,292 |
| weather_cached med (ms) | 36 |
| weather_cached p(95) (ms) | 554 |
| weather_cached p(99) (ms) | 1,083 |
| weather_cached max (ms) | 1,790 |
| weather_cached failed (%) | 0.00 |
| weather_cached checks passed (%) | 100.00 |
| Peak node CPU (millicores, 8 vCPU VM) | 7,280 |
| Peak node CPU (%) | 91 |
| Peak CPU gateway (millicores, all pods) | 1,379 |
| Peak CPU profile (millicores, all pods) | 1,978 |
| Peak CPU scheduling (millicores, all pods) | 1,742 |
| Peak CPU conditions (millicores, all pods) | 69 |
| Peak CPU discovery (millicores, all pods) | 70 |
| Peak CPU identity (millicores, all pods) | 666 |
| Peak CPU postgres (millicores, all pods) | 1,194 |
| Peak CPU k6 (millicores, all pods) | 466 |
| Threshold checks{op:nearby_runs} rate>0.99 | PASS |
| Threshold checks{op:runner_search} rate>0.99 | FAIL |
| Threshold checks{op:weather_cached} rate>0.99 | PASS |
| Threshold http_req_duration{op:nearby_runs} p(95)<1000 | FAIL |
| Threshold http_req_duration{op:runner_search} p(95)<2000 | FAIL |
| Threshold http_req_duration{op:weather_cached} p(95)<300 | FAIL |
| Threshold http_req_failed{op:nearby_runs} rate<0.01 | PASS |
| Threshold http_req_failed{op:runner_search} rate<0.01 | FAIL |
| Threshold http_req_failed{op:weather_cached} rate<0.01 | PASS |
| Threshold weather_cache_miss count<=10 | PASS |
