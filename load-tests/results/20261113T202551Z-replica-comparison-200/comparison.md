| Metric | replicas-1 | replicas-2 |
|---|---|---|
| Replicas (gateway/profile/scheduling/conditions/discovery) | 1/1/1/1/1 | 2/2/2/2/2 |
| Duration (s) | 555 | 556 |
| Peak VUs | 200 | 200 |
| HTTP requests (total) | 18,155 | 21,265 |
| Throughput (req/s, whole run) | 32.7 | 38.2 |
| Iterations | 17,936 | 21,050 |
| Dropped iterations | 0 | 0 |
| runner_search requests | 5,382 | 6,313 |
| runner_search med (ms) | 1,478 | 332 |
| runner_search p(95) (ms) | 2,559 | 1,947 |
| runner_search p(99) (ms) | 2,904 | 2,553 |
| runner_search max (ms) | 3,617 | 3,677 |
| runner_search failed (%) | 6.80 | 0.03 |
| runner_search checks passed (%) | 93.20 | 99.97 |
| nearby_runs requests | 7,238 | 8,503 |
| nearby_runs med (ms) | 667 | 78 |
| nearby_runs p(95) (ms) | 2,959 | 273 |
| nearby_runs p(99) (ms) | 3,387 | 439 |
| nearby_runs max (ms) | 4,102 | 788 |
| nearby_runs failed (%) | 0.00 | 0.00 |
| nearby_runs checks passed (%) | 100.00 | 100.00 |
| weather_cached requests | 5,316 | 6,234 |
| weather_cached med (ms) | 9 | 11 |
| weather_cached p(95) (ms) | 192 | 122 |
| weather_cached p(99) (ms) | 347 | 244 |
| weather_cached max (ms) | 582 | 519 |
| weather_cached failed (%) | 0.00 | 0.00 |
| weather_cached checks passed (%) | 100.00 | 100.00 |
| Peak node CPU (millicores, 8 vCPU VM) | 3,510 | 5,171 |
| Peak node CPU (%) | 43 | 64 |
| Peak CPU gateway (millicores, all pods) | 546 | 933 |
| Peak CPU profile (millicores, all pods) | 999 | 1,990 |
| Peak CPU scheduling (millicores, all pods) | 1,000 | 869 |
| Peak CPU conditions (millicores, all pods) | 20 | 33 |
| Peak CPU discovery (millicores, all pods) | 33 | 61 |
| Peak CPU identity (millicores, all pods) | 227 | 256 |
| Peak CPU postgres (millicores, all pods) | 441 | 658 |
| Peak CPU k6 (millicores, all pods) | 177 | 300 |
| Threshold checks{op:nearby_runs} rate>0.99 | PASS | PASS |
| Threshold checks{op:runner_search} rate>0.99 | FAIL | PASS |
| Threshold checks{op:weather_cached} rate>0.99 | PASS | PASS |
| Threshold http_req_duration{op:nearby_runs} p(95)<1000 | FAIL | PASS |
| Threshold http_req_duration{op:runner_search} p(95)<2000 | FAIL | PASS |
| Threshold http_req_duration{op:weather_cached} p(95)<300 | PASS | PASS |
| Threshold http_req_failed{op:nearby_runs} rate<0.01 | PASS | PASS |
| Threshold http_req_failed{op:runner_search} rate<0.01 | FAIL | PASS |
| Threshold http_req_failed{op:weather_cached} rate<0.01 | PASS | PASS |
| Threshold weather_cache_miss count<=10 | PASS | PASS |
