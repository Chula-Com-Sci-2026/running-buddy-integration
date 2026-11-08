| Metric | replicas-1 | replicas-2 |
|---|---|---|
| Replicas (gateway/profile/scheduling/conditions/discovery) | 1/1/1/1/1 | 2/2/2/2/2 |
| Duration (s) | 308 | 547 |
| Peak VUs | 500 | 500 |
| HTTP requests (total) | 14,808 | 25,540 |
| Throughput (req/s, whole run) | 48.1 | 46.7 |
| Iterations | 14,116 | 25,026 |
| Dropped iterations | 0 | 0 |
| runner_search requests | 4,327 | 7,387 |
| runner_search med (ms) | 118 | 282 |
| runner_search p(95) (ms) | 1,227 | 10,241 |
| runner_search p(99) (ms) | 2,236 | 11,087 |
| runner_search max (ms) | 3,714 | 13,805 |
| runner_search failed (%) | 0.14 | 34.67 |
| runner_search checks passed (%) | 99.86 | 65.33 |
| nearby_runs requests | 5,626 | 10,020 |
| nearby_runs med (ms) | 1,489 | 2,410 |
| nearby_runs p(95) (ms) | 11,498 | 25,678 |
| nearby_runs p(99) (ms) | 18,452 | 32,111 |
| nearby_runs max (ms) | 26,003 | 45,140 |
| nearby_runs failed (%) | 0.30 | 8.64 |
| nearby_runs checks passed (%) | 99.70 | 91.36 |
| weather_cached requests | 4,341 | 7,545 |
| weather_cached med (ms) | 18 | 51 |
| weather_cached p(95) (ms) | 289 | 1,594 |
| weather_cached p(99) (ms) | 1,855 | 3,386 |
| weather_cached max (ms) | 2,878 | 5,806 |
| weather_cached failed (%) | 0.00 | 0.00 |
| weather_cached checks passed (%) | 99.90 | 100.00 |
| Peak CPU gateway (millicores, all pods) | 579 | 1,012 |
| Peak CPU profile (millicores, all pods) | 773 | 1,247 |
| Peak CPU scheduling (millicores, all pods) | 961 | 1,369 |
| Peak CPU conditions (millicores, all pods) | 38 | 71 |
| Peak CPU discovery (millicores, all pods) | 59 | 163 |
| Peak CPU identity (millicores, all pods) | 709 | 679 |
| Peak CPU postgres (millicores, all pods) | 799 | 1,118 |
| Peak CPU k6 (millicores, all pods) | 256 | 461 |
| Threshold checks{op:nearby_runs} rate>0.99 | PASS | FAIL |
| Threshold checks{op:runner_search} rate>0.99 | PASS | FAIL |
| Threshold checks{op:weather_cached} rate>0.99 | PASS | PASS |
| Threshold http_req_duration{op:nearby_runs} p(95)<1000 | FAIL | FAIL |
| Threshold http_req_duration{op:runner_search} p(95)<2000 | PASS | FAIL |
| Threshold http_req_duration{op:weather_cached} p(95)<300 | PASS | FAIL |
| Threshold http_req_failed{op:nearby_runs} rate<0.01 | PASS | FAIL |
| Threshold http_req_failed{op:runner_search} rate<0.01 | PASS | FAIL |
| Threshold http_req_failed{op:weather_cached} rate<0.01 | PASS | PASS |
| Threshold weather_cache_miss count<=10 | FAIL | PASS |
