# Can't Run Alone — local Deliverable 4 integration

Runs seven independently owned domain services, a gateway, real PostgreSQL, real Redis and RabbitMQ. All repositories must be sibling folders. No application shares another application's tables. This is a local course demo with scoped functionality, not a production deployment.

## Start

From this repository:

```sh
python3 scripts/init-env.py
docker compose up -d --build
docker compose run --rm tools python seed.py
```

Wait for `docker compose ps` to show the API/database health checks ready before seeding. On a fresh startup the Rails migrations and Python SQL migrations run automatically. `scripts/init-databases.sh` creates service-owned demo and test databases on the first PostgreSQL initialization. If using an older volume from before test databases were added, create the missing `*_test` databases as the PostgreSQL operator; do not broaden application-role permissions.

Start the frontend separately:

```sh
cd ../cant-run-alone-frontend
npm run dev -- --host 127.0.0.1
```

Open http://localhost:5173/login. Frontend mock mode is off by default; `.env.example` documents the gateway URL. Seed credentials: `ray@example.com` / `runner123` and `mali@example.com` / `runner123`. Seeded phone verification is a development fixture, not evidence of SMS delivery. The UI registration flow uses a random expiring OTP printed by `docker compose logs identity` through the explicitly labeled local console adapter.

Gateway: http://localhost:8088. RabbitMQ management: http://localhost:15678 (user `cra`, password from ignored local `.env`). The database and internal service ports are not exposed to the host. No secrets are committed. PostgreSQL and Redis use named volumes; Redis uses AOF.

## Business flows

1. Log in, create/update a profile, discover a compatible runner, send a buddy request. Log in as the recipient, open Activity, receive the broker notification and accept the request.
2. Create a public run, pin a meeting point and check live weather/air quality. Publish the run; another runner joins. Exact pin coordinates appear only after joining; unjoined map coordinates are approximate.
3. Open Activity for the prepared past run. Ray confirms, then Mali confirms; the second confirmation completes the run. Confirmed participants can rate each other and log their own records. Rating aggregates stay hidden until three ratings exist. Running history shows persisted records and totals.

Use separate browser contexts for the two accounts. Run Conditions uses Open-Meteo/CAMS with a 15-minute Redis cache and up to six hours of stale fallback. A missing forecast fails visibly rather than fabricating weather. The future run must be within the provider's available forecast horizon. The prepared past run carries a clearly identified historical weather fixture.

## Tests and database evidence

```sh
./scripts/test-services.sh
docker compose run --rm tools python check_flows.py
docker compose run --rm tools python check_broker.py
docker compose run --rm tools python persistence.py before
docker compose restart postgres redis
docker compose run --rm tools python persistence.py after
```

The service runner uses separate `*_test` PostgreSQL databases and Redis database 15. Tests must not run against demo databases; Profile tests truncate their dedicated test table. Rails tests explicitly migrate pre-created test databases and do not require CREATEDB privileges. Python tests use real local databases; provider failures are simulated only in focused unit tests. `check_flows.py` uses live services, real gRPC, broker delivery and the live weather provider. It adds uniquely identified integration records without deleting existing data.

Frontend checks run in its repository: `npm test`, `npm run lint`, `npm run build`. Unit tests explicitly enable mock mode for the old prototype fixtures; live browser mode remains disabled for mocks. UI evidence is under `cant-run-alone-frontend/screenshots/delivery4/`.

Show these database queries in the recording after their corresponding UI actions:

```sh
docker compose exec postgres psql -U discovery -d discovery -c 'SELECT id,sender_id,recipient_id,status FROM buddy_requests ORDER BY created_at DESC LIMIT 5;'
docker compose exec postgres psql -U discovery -d discovery -c 'SELECT id,event_type,published_at FROM outbox_events ORDER BY created_at DESC LIMIT 5;'
docker compose exec postgres psql -U notification -d notification -c 'SELECT event_id,recipient_id,type,is_read FROM notifications ORDER BY created_at DESC LIMIT 5;'
docker compose exec postgres psql -U scheduling -d scheduling -c 'SELECT id,title,status,starts_at FROM runs ORDER BY created_at DESC LIMIT 5;'
docker compose exec postgres psql -U reputation -d reputation -c 'SELECT run_id,runner_id,distance_meters,duration_seconds FROM running_records ORDER BY created_at DESC LIMIT 5;'
docker compose exec redis redis-cli --scan --pattern 'forecast:*'
```

Copy a forecast key from the last command, then run `docker compose exec redis redis-cli GET '<key>'` and `docker compose exec redis redis-cli TTL '<key>'`. Match IDs and values to the browser action; merely showing a running database container is not sufficient evidence. `contracts/persistence-proof.json` records only non-secret probe identifiers.

## Replace a service with a teammate implementation

`contracts/` contains exported live OpenAPI and event documentation. Discovery's source contract is in `../buddy-discovery-service/proto/`; the gateway's contract copy must match it. Set `IDENTITY_URL`, `PROFILE_URL`, `CONDITIONS_URL`, `SCHEDULING_URL`, `NOTIFICATION_URL`, `REPUTATION_URL` or `DISCOVERY_TARGET` in `.env`, then recreate the gateway and affected callers. For services running on the host, containers generally reach them through `host.docker.internal`. Ensure JWT issuer/audience/key compatibility first. Never expose the signing secret in frontend environment variables.

Run contract and flow checks before switching. Adapt payload differences explicitly. Changing a URL does not migrate local accounts or run data. RabbitMQ/Kafka differences require a transport adapter; event JSON compatibility alone is insufficient.

## Scope and boundaries

Search is delegated by Discovery to Profile through its API; there is no replicated candidate read model yet. Profile public reads omit private coordinates. Phone verification is distinct from a Trust & Safety badge. Admin, moderation, reports, suspension, written reviews, reminders, public-history privacy settings and invite-only runs are deferred. Ended-run attendance opens on confirmation access; no scheduled end-run event consumer is claimed. Scheduling owns completion; Reputation persists confirmation after Scheduling accepts it. A retry reconciles a partially completed cross-service confirmation.

Health checks, structured API errors and tests are included. Coverage percentage has not been measured; do not claim compliance with the historical 70% target. HS256 trust is limited to the local demo; see ADR-0010. Each repository has local feature-branch commits; nothing is pushed by these instructions.

Stop without deleting stored data:

```sh
docker compose down
```

Do not use `down -v` unless deliberately discarding all local databases.


## Demo against the team Identity PR branch

The teammate implementation is checked out in `../team-identity-service/` on `fix/deliverable-4-auth-integration`. The optional override uses that checkout, a separate `identity_team` database, matching JWT claims and stable demo UUIDs. The existing Python Identity repository and `identity` database remain untouched.

```sh
./scripts/start-team-identity.sh
./scripts/test-team-identity.sh
```

Use the same browser/gateway URLs and Ray/Mali credentials. The script provisions only the additional local databases with the PostgreSQL operator, builds the checked-out branch, starts its console-only email worker on `identity.email.v1`, and seeds matching user IDs. It never merges or pulls the team branch automatically. Do not use the base Python Identity test command against the Node image; the team script runs Node's PostgreSQL-backed regression suite and complete business-flow/broker checks.

To return to the preserved Python implementation and database:

```sh
./scripts/restore-local-identity.sh
```

Use the override on subsequent operations while testing the PR branch: `docker compose -f compose.yaml -f compose.team-identity.yaml ...`. Using only the base Compose file selects the Python configuration. Team registration now supports the existing frontend contract, so no frontend rewrite or token-validation weakening is needed. Fresh sessions are required after switching implementations; old refresh cookies belong to the other database.
