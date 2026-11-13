# Load tests (Grafana k6)

k6 scripts for the Deliverable 5 non-functional requirements, run against the Kubernetes deployment in [`../k8s/`](../k8s/README.md). Every request goes through the API gateway with a real access token from team Identity, exactly as the browser does.

## Targets and the requirements conflict

The two requirement documents disagree. The scripts use the **original Deliverable 1 submission** as the provisional baseline, and can evaluate the other set with `TARGETS=requirements`. Neither document has been changed; the team should decide which one is authoritative.

| Requirement | Deliverable 1 (`TARGETS=d1`, default) | `running-buddy/docs/requirements.md` (`TARGETS=requirements`) | k6 metric |
|---|---|---|---|
| NFR-1.1 runner search, 10,000 profiles | p95 < 2 s | p95 < 3 s | `http_req_duration{op:runner_search}` |
| NFR-1.2 nearby-runs query | p95 < 1 s | p95 < 2 s | `http_req_duration{op:nearby_runs}` |
| NFR-1.3 cached weather | p95 < 300 ms | p95 < 500 ms | `http_req_duration{op:weather_cached}` |
| NFR-1.3 weather cache miss | ≤ 3 s | ≤ 3 s | `weather_cache_miss_duration` max (`weather-cold.js`) |
| NFR-2.1 concurrency | 500 concurrent users, 5,000 registered | same | `SCENARIO=ramp TARGET_VUS=500`; 5,000 seeded accounts |
| NFR-3.1 availability | 99 % **monthly** uptime | 99 % **daily** uptime | not measurable here — see Limitations |

**Proposed, not existing requirements** (no document defines them; adopt or change them as a team): per operation, HTTP failure rate < 1 % and response-correctness checks > 99 % (`MAX_ERROR_RATE`, default 0.01); during a single pod replacement, no failed HTTP requests and replacement Ready within 30 s (measured in [`../k8s/README.md`](../k8s/README.md)).

Every threshold is per operation (`{op:...}` tags). There is no aggregate latency threshold, because a fast weather response would hide a slow search.

## What the API actually offers

- **Runner search** — `GET /api/v1/runners?radiusKm=&experience=` → gateway → Discovery (gRPC) → Profile (REST). Profile loads every profile and computes distances in Python; there is no PostGIS index yet (ADR-0016 is not implemented), so this is the operation the 10,000-profile dataset stresses.
- **Nearby runs** — there is **no proximity endpoint**. The browse/map screen calls `GET /api/v1/runs`, which returns every upcoming run (plus the caller's past runs), with one participant query per run and no pagination. The test measures that endpoint as the current implementation of NFR-1.2; it is not a radius query.
- **Weather** — `GET /api/v1/conditions?latitude=&longitude=&at=` → Run Conditions → Redis (key: 0.01° cell + hour, TTL 15 min) or the live Open-Meteo/CAMS provider on a miss. Slots beyond about 4.5 days return 503 because the CAMS air-quality forecast is shorter.

Correctness checks per response: search returns compatible runners, honours the experience filter and never exposes coordinates; runs list has at least the seeded count and unjoined runs show only approximate (1-decimal) pins; weather is a cache hit with live provider data.

## Dataset (seed once, safe to repeat)

```sh
k8s/scripts/run-tool.sh python seed_loadtest.py              # 10,000 profiles, 5,000 accounts, 200 upcoming runs
k8s/scripts/run-tool.sh python seed_loadtest.py --report     # counts only
k8s/scripts/run-tool.sh python seed_loadtest.py --reschedule # move load-test runs forward if they have started
k8s/scripts/run-tool.sh python seed_loadtest.py --remove     # delete only load-test rows
```

Rows use deterministic UUIDv5 IDs in a dedicated namespace and a visible marker (`k6 load-test fixture` bio/title, `@loadtest.example.com` e-mail); inserts are `ON CONFLICT DO NOTHING`, so a re-run changes nothing and Ray, Mali and every other row are never overwritten. `--remove` deletes only rows that have both the namespace ID and the marker. The same fixed random seed produces the same profiles every time: uniformly spread over a 15 km radius of central Bangkok, pace 4.5–9.5 min/km, 40/40/20 % beginner/intermediate/advanced. The seed runs in the cluster's own database; the Compose databases are untouched. Sizes are adjustable (`TOOL_ENV=LOADTEST_PROFILES=…,LOADTEST_ACCOUNTS=…,LOADTEST_RUNS=…`).

Each k6 VU logs in as its own account (VU *n* → `k6-runner-<n-1>`), so 500 VUs are 500 different runners, and renews its token after 12 minutes (tokens expire at 15). Login is measured separately (`login_duration`); bcrypt cost 12 makes each login about 240 ms, by design.

## Scenarios

| Command | Model | What it shows |
|---|---|---|
| `load-tests/run-k6.sh running-buddy.js SCENARIO=smoke` | 1 VU, 3 iterations of each operation | Correctness and wiring; run first |
| `load-tests/run-k6.sh running-buddy.js SCENARIO=baseline BASELINE_RATE=10 BASELINE_DURATION=5m` | Open model: 10 iterations/s, no think time | Latency at a fixed, moderate request rate; reports dropped iterations if the system cannot keep up |
| `load-tests/run-k6.sh running-buddy.js SCENARIO=ramp TARGET_VUS=500` | Closed model: 0 → 50 → 250 → 500 VUs (1 m, 2 m, 2 m), hold 3 m, ramp down 1 m; 1–5 s think time | NFR-2.1: 500 concurrent users |
| `load-tests/run-k6.sh weather-cold.js COLD_CHECKS=5` | 1 VU, 5 uncached slots | NFR-1.3 cache miss ≤ 3 s, kept apart from sustained load |
| `load-tests/compare-replicas.sh` | Same ramp at 1 and then 2 replicas | Horizontal scaling (see below) |

Mix per iteration: 30 % runner search, 40 % nearby runs, 30 % cached weather (`MIX=30,40,30`). Ramp shape: `RAMP_STAGES=duration:fraction,...` (fractions of `TARGET_VUS`).

**VUs are not requests per second.** A VU is one simulated user running the loop: request, wait for the response, think 1–5 s, repeat. With an average think time of 3 s, 500 VUs produce roughly 500 / (3 s + response time) ≈ 150 req/s while responses are fast — and *fewer* when the system slows down, because each user waits for its answer (closed model). The baseline instead fixes the arrival rate (open model): if responses slow down, k6 needs more VUs to keep the rate and, when `maxVUs` is exhausted, records `dropped_iterations`. Both numbers are reported.

### Keeping the live weather provider bounded

`setup()` warms six fixed slots (three parks × 06:00/18:00 Bangkok, two days ahead): at most 12 provider requests per run, none when Redis is already warm. During load every weather request must be a cache hit; each miss increments `weather_cache_miss`, and more than `MAX_WEATHER_MISSES` (10) aborts the run, which caps provider traffic even if the cache were flushed mid-test. Keep warm-cache runs under 15 minutes from setup (the TTL). The cold check makes at most 2 × 10 provider requests per run.

## Replica comparison

`compare-replicas.sh` runs the identical workload twice — `DEPLOYMENTS` (gateway, profile, scheduling, conditions, discovery) at 1 and then 2 replicas — with the same per-pod requests/limits (100m / 1 CPU), the same k6 budget (1–2 CPUs) and the same VM. The gateway is restarted before each run so its gRPC channel resolves every Discovery pod. Output: `results/<time>-replica-comparison/{replicas-1,replicas-2,comparison.md}`. The second run benefits from the first run's warm PostgreSQL buffers; for a stricter comparison use `REPLICA_COUNTS="2 1"` as well and compare both orders.

## Result artifacts

Each run writes `results/<UTC time>-<label>/`. The 31 Oct 2026 runs are committed as evidence; folders whose name ends in `-INVALID` or `-INTERRUPTED` carry a `NOTE.txt` and must not be quoted as results.

Each folder contains:

- `summary.txt` — per-operation count, req/s, avg/p50/p90/p95/p99/max, failed %, checks %, each threshold's PASS/FAIL, k6 exit code (99 = a threshold failed);
- `summary.json` — full k6 end-of-test summary (all metrics and thresholds);
- `k6.log` — complete k6 output;
- `environment.txt` — host CPU/RAM, every running Colima VM, node capacity, replicas and limits, gateway gRPC mode, image digests and git revisions, dataset counts;
- `pod-usage.txt` — `kubectl top pods` every 15 s.

k6 runs as a Job inside the cluster (`grafana/k6:2.3.0`, requests 1 CPU, limit 2 CPUs) and calls `http://gateway:8000`, so no host port-forward sits in the measurement path. It shares the VM's CPUs with the system under test, which is constant across runs but means absolute numbers understate a dedicated deployment.

## Measured results

### 13 Nov 2026 — current stack (team Profile and Notification)

Apple M4 (10 CPUs, 16 GiB), `cra-k8s` VM **8 vCPU / 10 GiB** (`CPUS=8 MEMORY_GIB=10 k8s/scripts/cluster-up.sh`), the other Colima VM stopped, k3s v1.33.3, D1 targets. Dataset 10,006 profiles (10,000 load-test), 5,012 accounts, 204 upcoming runs. Identity runs 3 replicas (see the login note below). Folders are under `results/`.

| Run | Load | Search p95 | Nearby runs p95 | Cached weather p95 | Failures | Verdict |
|---|---|---|---|---|---|---|
| `20261113T192821Z-smoke` | 1 VU × 3 | 177 ms | 67 ms | 10 ms | 0 | All thresholds **PASS** |
| `20261113T192859Z-baseline-10rps` | 10 iterations/s, 5 min (3,071 requests, 0 dropped) | 1,704 ms | 524 ms | 187 ms | search 0.12 % | All thresholds **PASS** (login note below) |
| `20261113T193656Z-weather-cold-10` | 10 uncached slots, 1 VU | — | — | — | 1 of 10 | Cache miss median 2,122 ms, max 4,061 ms: **FAIL** (≤ 3 s) |
| `20261113T202551Z-replica-comparison-200/replicas-1` | ramp to 200 VUs, 1 replica | 2,559 ms | 2,959 ms | 192 ms | search 6.8 % | **FAIL** (search, nearby runs) |
| `20261113T202551Z-replica-comparison-200/replicas-2` | ramp to 200 VUs, 2 replicas | 1,947 ms | 273 ms | 122 ms | search 0.03 % | All thresholds **PASS** |
| `20261113T205057Z-ramp-500-replicas-2` | ramp to 500 VUs, 2 replicas | 10,003 ms | 2,619 ms | 554 ms | search 55.9 % | **FAIL** — NFR-2.1 not met |

**Horizontal scaling (valid comparison, 200 VUs).** Same workload, same per-pod limits, same VM; only the replica count of gateway, profile, scheduling, conditions and discovery changed. 2 replicas ran first, so the 1-replica run had the warmer PostgreSQL buffers and still lost. At 1 replica, Profile (999 m) and Scheduling (1,000 m) sat at their 1-CPU limit while the node had headroom (peak 43 %); a second replica moved the bottleneck off them: nearby-runs p95 2,959 → 273 ms, search p95 2,559 → 1,947 ms, throughput 32.7 → 38.2 req/s, node CPU 43 → 64 %. Details: `results/20261113T202551Z-replica-comparison-200/comparison.md`.

**500 VUs (NFR-2.1): FAIL** under both target sets (`requirements.md` allows 3 s / 2 s / 500 ms; measured 10 s / 2.6 s / 554 ms). 80 req/s, 501 of 501 logins succeeded, no pod restarts, node CPU up to 7.3 of 8 cores. Search hits the gateway's 10 s gRPC deadline. Causes, from the measurements:

- **Unpaginated search.** One search returns 75 KB – 1.2 MB of JSON (up to ~3,800 runners). Profile → Discovery → gateway each serialise and parse it again (the gateway receives it as a JSON string inside gRPC). A result limit or pagination in Discovery/Profile is the fix; it is service code, so it is not changed here.
- **N+1 runs list** in Scheduling (one participant query per run, 204 runs), already noted on 31 Oct.
- **One laptop VM.** Services, data stores and k6 share 8 vCPUs; at 500 VUs adding replicas only splits the same CPUs (the 1-replica 500-VU run, `…-INVALID-broker-restarts`, peaked at the same 86 %).

**Weather cache miss: FAIL tonight.** The provider answered in a steady ~0.9 s from the Mac, the VM and a pod (DNS 2–30 ms), and a cache miss makes two provider calls one after the other (forecast, then air quality), so ~2 s is the floor and any provider slowdown crosses 3 s. On 31 Oct the same test measured 1.6 s. Fetching both in parallel would halve the floor (service code).

**Login under bursts.** Team Identity checks bcrypt (cost 12, pure JS) while holding a pooled PostgreSQL connection in a `FOR UPDATE` transaction, and the pool gives up after 2 s. With 1 replica, 38.6 % of the baseline's logins (50 VUs at once) failed. Identity now runs 3 replicas; every later run had 0 login failures.

**Fixed during these runs (configuration and gateway only):**

- RabbitMQ's liveness probe ran `rabbitmq-diagnostics` (an Erlang VM per check); on the saturated node it timed out, the kubelet restarted a healthy broker 8 times, and Identity (which needs the broker to start) crash-looped with it. Liveness and readiness are now TCP checks on 5672. The three runs affected are kept with `-INVALID-broker-restarts`.
- The gateway retries read-only Discovery calls on `UNAVAILABLE`, which a call started while Discovery recycles a connection (`GRPC_MAX_CONNECTION_AGE_MS`) used to return as 503 "max connection age". 330 of 330 searches across the recycle succeeded afterwards.
- Profile and Notification pods set `enableServiceLinks: false`; Kubernetes' injected `POSTGRES_PORT=tcp://…` / `RABBITMQ_PORT=tcp://…` crashed both team services.
- The smoke check for search expected a `match` score that the team Profile service does not return (the frontend does not use it); it now checks `distanceKm`. The run before the change is `…-INVALID-stale-search-check`.

### 31 Oct 2026 — previous stack (Python Profile and Notification)

`cra-k8s` VM 6 vCPU / 6 GiB, a second Colima VM sharing the host, dataset 10,004 profiles, 5,004 accounts, 201 upcoming runs.

| Run | Load | Runner search p95 | Nearby runs p95 | Cached weather p95 | Failures | Verdict |
|---|---|---|---|---|---|---|
| `20261031T041938Z-smoke` | 1 VU × 3 | 68 ms | 37 ms | 11 ms | 0 | All thresholds PASS |
| `20261031T042116Z-baseline-10rps` | 10 iterations/s, 5 min (3,069 requests, max 50 VUs, 0 dropped) | 56 ms | 53 ms | 16 ms | 0.22 % / 0.17 % / 0 % | All thresholds PASS |
| `20261031T042729Z-weather-cold` | 5 uncached slots, 1 VU | — | — | — | 0 | Cache miss 1,556–1,631 ms, max < 3 s **PASS** |

The 500-VU and replica-comparison attempts of 31 Oct (`…-INVALID`, `…-INTERRUPTED`) are superseded by the 13 Nov runs above.

## Demo sequence (~100 s of k6 results)

1. (15 s) `20261113T192821Z-smoke/summary.txt`: three operations, every check and threshold PASS; explain the per-operation thresholds and the D1 targets (table above).
2. (25 s) Baseline: 10 iterations/s for 5 minutes, all thresholds PASS, 0 dropped. Explain VUs versus requests per second and the open versus closed model.
3. (30 s) `20261113T202551Z-replica-comparison-200/comparison.md`: 1 replica fails, 2 replicas pass; Profile and Scheduling were at their CPU limit. This is the demonstrated quality attribute (scalability).
4. (30 s) The 500-VU run: say plainly that NFR-2.1 is not met on one laptop VM, show search hitting the 10 s deadline, and name the cause (unpaginated 1 MB search responses) and the fix.

For a live run during the presentation: `load-tests/scripts/demo-live.sh` (2 minutes, 100 VUs, k6 dashboard, deletes the Profile pod at 60 s).

## Limitations

- One local VM (8 vCPU / 10 GiB on 13 Nov, 6 vCPU / 6 GiB on 31 Oct, Apple M4 laptop) shared by every service, the data stores and k6; on 31 Oct another Colima VM shared the host (recorded in each `environment.txt`). `pod-usage.txt` from later runs also records node-level CPU. Results show relative behaviour and bottlenecks, not production capacity.
- "Nearby runs" is the unfiltered runs list, because no proximity query exists; runner search is a full scan returning every match unpaginated, not the PostGIS design of ADR-0016.
- A few minutes of load cannot establish monthly or daily uptime (NFR-3.1); no availability percentage is claimed.
- The ramp holds 500 VUs for 3 minutes; it is not a soak test, and peak-hour traffic (NFR-2.2, 5× average) has no defined average to scale from.
