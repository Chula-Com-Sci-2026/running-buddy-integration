| Metric | 20261113T194014Z-running-buddy-SCENARIO_ramp-TARGET_VUS_500 | replicas-2 |
|---|---|---|
| Replicas (gateway/profile/scheduling/conditions/discovery) | 1/1/1/1/1 | 2/2/2/2/2 |
| Duration (s) | 588 | 578 |
| Peak VUs | 500 | 500 |
| HTTP requests (total) | 7,818 | 5,931 |
| Throughput (req/s, whole run) | 13.3 | 10.3 |
| Iterations | 7,318 | 5,515 |
| Dropped iterations | 0 | 0 |
| runner_search requests | 2,018 | 1,340 |
| runner_search med (ms) | 11,088 | 13,141 |
| runner_search p(95) (ms) | 43,316 | 60,002 |
| runner_search p(99) (ms) | 51,973 | 60,010 |
| runner_search max (ms) | 56,572 | 60,119 |
| runner_search failed (%) | 85.68 | 84.93 |
| runner_search checks passed (%) | 14.32 | 15.07 |
| nearby_runs requests | 2,716 | 1,765 |
| nearby_runs med (ms) | 32,319 | 35,271 |
| nearby_runs p(95) (ms) | 54,973 | 60,008 |
| nearby_runs p(99) (ms) | 60,003 | 60,018 |
| nearby_runs max (ms) | 60,045 | 60,074 |
| nearby_runs failed (%) | 61.49 | 73.99 |
| nearby_runs checks passed (%) | 38.51 | 26.01 |
| weather_cached requests | 2,035 | 1,307 |
| weather_cached med (ms) | 8,789 | 11,194 |
| weather_cached p(95) (ms) | 33,692 | 60,001 |
| weather_cached p(99) (ms) | 39,793 | 60,011 |
| weather_cached max (ms) | 44,054 | 60,046 |
| weather_cached failed (%) | 7.42 | 30.99 |
| weather_cached checks passed (%) | 92.58 | 69.01 |
| Peak node CPU (millicores, 8 vCPU VM) | 6,951 | 6,949 |
| Peak node CPU (%) | 86 | 86 |
| Peak CPU gateway (millicores, all pods) | 890 | 814 |
| Peak CPU profile (millicores, all pods) | 951 | 1,255 |
| Peak CPU scheduling (millicores, all pods) | 894 | 756 |
| Peak CPU conditions (millicores, all pods) | 91 | 88 |
| Peak CPU discovery (millicores, all pods) | 164 | 201 |
| Peak CPU identity (millicores, all pods) | 1,808 | 1,392 |
| Peak CPU postgres (millicores, all pods) | 728 | 649 |
| Peak CPU k6 (millicores, all pods) | 669 | 558 |
| Threshold checks{op:nearby_runs} rate>0.99 | FAIL | FAIL |
| Threshold checks{op:runner_search} rate>0.99 | FAIL | FAIL |
| Threshold checks{op:weather_cached} rate>0.99 | FAIL | FAIL |
| Threshold http_req_duration{op:nearby_runs} p(95)<1000 | FAIL | FAIL |
| Threshold http_req_duration{op:runner_search} p(95)<2000 | FAIL | FAIL |
| Threshold http_req_duration{op:weather_cached} p(95)<300 | FAIL | FAIL |
| Threshold http_req_failed{op:nearby_runs} rate<0.01 | FAIL | FAIL |
| Threshold http_req_failed{op:runner_search} rate<0.01 | FAIL | FAIL |
| Threshold http_req_failed{op:weather_cached} rate<0.01 | FAIL | FAIL |
| Threshold weather_cache_miss count<=10 | PASS | PASS |
