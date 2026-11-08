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

All runs on 31 Oct 2026: Apple M4 (10 CPUs, 16 GiB), `cra-k8s` VM 6 vCPU / 6 GiB, k3s v1.33.3, dataset 10,004 profiles (10,000 load-test), 5,004 accounts, 201 upcoming runs, D1 targets. A second Colima VM running an unrelated stack shared the host throughout (see each `environment.txt`). Folders are under `results/`.

| Run | Load | Runner search p95 | Nearby runs p95 | Cached weather p95 | Failures | Verdict |
|---|---|---|---|---|---|---|
| `20261031T041938Z-smoke` | 1 VU × 3 | 68 ms | 37 ms | 11 ms | 0 | All thresholds PASS |
| `20261031T042116Z-baseline-10rps` | 10 iterations/s, 5 min (3,069 requests, max 50 VUs, 0 dropped) | 56 ms | 53 ms | 16 ms | 0.22 % / 0.17 % / 0 % (see note) | All thresholds PASS |
| `20261031T042729Z-weather-cold` | 5 uncached slots, 1 VU | — | — | — | 0 | Cache miss 1,556–1,631 ms, max < 3 s **PASS** |

Baseline note: 4 of 55 logins returned 500 when 50 VUs logged in at the same instant at the start of the test, and each of those VUs then sent one request without a token (the 2 + 2 failed search/runs requests). Cause, from team Identity's code: login holds a pooled PostgreSQL connection inside a `FOR UPDATE` transaction during the ~240 ms bcrypt comparison, and the `pg` pool (10 connections by default with `DATABASE_URL`, 2 s acquire timeout) times out under a burst. The script now skips the business request after a failed login and reports `login_failed` separately.

### 500 concurrent users and the replica comparison — not yet validly measured

No valid NFR-2.1 / replica-comparison result exists yet. Re-run with `load-tests/compare-replicas.sh`.

- `20261031T042800Z-replica-comparison-INVALID`: the 1-replica run was aborted after 308 s by the provider guard (13 weather cache misses > 10), because the warm-up then accepted slots cached about 15 minutes earlier, which expired mid-test. The warm-up now uses only freshly fetched slots. The two runs had different durations and load, so they must not be compared.
- `20261031T044505Z-replica-comparison-INTERRUPTED`: the VM was stopped from outside (clean shutdown) about 4 minutes in; no summary.

Indicative observations from the invalid pair only, to be confirmed by a valid run:

- 1 replica, ramp up to 500 VUs (aborted at peak): nearby runs p95 11.5 s (far above the 1 s target; Scheduling at its 1-CPU limit — `GET /runs` serialises 201 runs with one participant query each), runner search p95 1.2 s, cached weather p95 289 ms, about 48 req/s.
- 2 replicas, full 9-minute ramp: every latency threshold failed (search p95 10.2 s with 35 % failures at the gateway's 10 s gRPC deadline). Summed pod CPU peaked at about 6 cores, the VM's whole capacity, so extra replicas added contention instead of capacity.
- Throughput stayed near 47 req/s at 500 VUs, not ~150: with a closed model each user waits for its slow response before thinking again.

Expected bottlenecks to address before NFR-2.1 can pass: the unfiltered N+1 runs list (a proximity query with pagination, ADR-0016), the full-table Python search, per-request PostgreSQL connections in the Python services, and Identity's login connection hold. A valid scaling comparison also needs a node that is not saturated: run it with the other VM stopped, at a load the 1-replica deployment can just sustain (e.g. `TARGET_VUS=200`), or with a larger VM.

## Demo sequence (~100 s of k6 results)

1. (15 s) `summary.txt` of the smoke run: three operations, every check and threshold PASS; explain the per-operation thresholds and that the D1 targets are used (table above).
2. (30 s) Baseline `summary.txt`: 10 iterations/s for 5 minutes, p95 56 / 53 / 16 ms, 0 dropped iterations. Explain VUs versus requests per second and the open versus closed model.
3. (20 s) Cold-cache run: five real provider fetches at 1.6 s each, under the 3 s limit; the warm-cache guard caps live provider traffic.
4. (35 s) The 500-VU ramp and the `comparison.md` from a valid `compare-replicas.sh` run (re-run first). Until then, state honestly that the 500-user target is not yet met: nearby-runs p95 was 11.5 s and the 6-vCPU node saturated, and name the bottlenecks above.

## Limitations

- One local VM (6 vCPU / 6 GiB on an Apple M4 laptop) shared by every service, the data stores and k6; another Colima VM was running on the same host during the measured runs (recorded in each `environment.txt`). `pod-usage.txt` from later runs also records node-level CPU. Results show relative behaviour and bottlenecks, not production capacity.
- "Nearby runs" is the unfiltered runs list, because no proximity query exists; runner search is a full scan in Python, not the PostGIS design of ADR-0016.
- A few minutes of load cannot establish monthly or daily uptime (NFR-3.1); no availability percentage is claimed.
- The ramp holds 500 VUs for 3 minutes; it is not a soak test, and peak-hour traffic (NFR-2.2, 5× average) has no defined average to scale from.
