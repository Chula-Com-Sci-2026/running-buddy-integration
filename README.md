# Running Buddy Integration

Runs seven independently owned domain services, a gateway, real PostgreSQL, real Redis and RabbitMQ. All repositories must be sibling folders. No application shares another application's tables. This is a local course demo with scoped functionality, not a production deployment.

## Start

For Colima, allocate at least 4 GB RAM to the full demo stack (`colima start --cpu 4 --memory 4`). The 2 GB default was observed with only 25 MB available and API requests timing out. Stop Colima before changing the allocation; existing database volumes are retained.

From this repository:

```sh
python3 scripts/init-env.py
docker compose up -d --build
docker compose run --rm tools python seed.py
```

Wait for `docker compose ps` to show the API/database health checks ready before seeding. On a fresh startup the Rails migrations, the Python SQL migrations and the team Profile (Drizzle) and Notification (Alembic) migrations run automatically. `scripts/init-databases.sh` creates service-owned demo and test databases on the first PostgreSQL initialization. If using an older volume from before test databases were added, create the missing `*_test` databases as the PostgreSQL operator; do not broaden application-role permissions.

Start the frontend separately:

```sh
cd ../cant-run-alone-frontend
npm run dev -- --host 127.0.0.1
```

Open http://localhost:5173/login. Frontend mock mode is off by default; `.env.example` documents the gateway URL. Seed credentials: `ray@example.com` / `runner123` and `mali@example.com` / `runner123`. Seeded phone verification is a development fixture, not evidence of SMS delivery. The UI registration flow uses a random expiring OTP printed by `docker compose logs identity` through the explicitly labeled local console adapter.

Gateway: http://localhost:8088. RabbitMQ management: http://localhost:15678 (user `cra`, password from ignored local `.env`). The database and internal service ports are not exposed to the host. No secrets are committed. PostgreSQL and Redis use named volumes; Redis uses AOF.

## Team Profile and Notification services

Profile and Notification run the team's own implementations, checked out as sibling folders:

```sh
git clone https://github.com/Chula-Com-Sci-2026/profile-service.git ../team-profile-service
git clone https://github.com/Chula-Com-Sci-2026/notification-service.git ../team-notification-service
```

They keep the Compose names `profile` and `notification` on port 8000, so the gateway, Discovery and the checks reach them unchanged. Their HTTP and event contracts are the ones in [running-buddy-contracts](https://github.com/Chula-Com-Sci-2026/running-buddy-contracts) (`profile.openapi.json`, `profile-events.schema.json`, `notification.openapi.json`). Profile also starts `profile-storage` (MinIO, published on `127.0.0.1:9000` for photo links; set `PROFILE_PHOTO_PORT` if 9000 is taken), creates its bucket and its own broker user `profile`, and publishes `ProfileUpdated` through its outbox. Nothing consumes `ProfileUpdated` yet, so those events wait in Profile's outbox until a queue is bound. MinIO's own images are no longer publicly pullable, so the stack uses Chainguard's MinIO pinned by digest.

**Volumes created before 8 Nov 2026** still hold the Python Profile and Notification tables. Run once, then start as usual:

```sh
python3 scripts/init-env.py                          # adds PROFILE_STORAGE_SECRET to .env
./scripts/switch-to-team-profile-notification.sh     # renames the old databases to *_legacy; deletes nothing
docker compose up -d --build
docker compose run --rm tools python seed.py         # Ray, Mali, Narin and Pim's profiles, through Profile's API
```

The Python `profile-service` and `notification-service` folders are no longer used by the stack.

## Share the stack for UAT (Cloudflare tunnel)

With the stack running, `scripts/uat-tunnel.sh start` builds the frontend, serves it with `vite preview`, opens a Cloudflare quick tunnel and prints a public `https://….trycloudflare.com` link. Everything goes through that one link: the page, `/api` (gateway) and `/profile-service` (photo storage), and Profile is restarted so its photo upload links use it. Needs `cloudflared` (`brew install cloudflared`); no Cloudflare account.

```bash
scripts/uat-tunnel.sh start    # prints the link to share
scripts/uat-tunnel.sh otp      # sign-up OTP codes from Identity's log (SMS is not wired up)
scripts/uat-tunnel.sh status
scripts/uat-tunnel.sh stop     # close the link; Profile's photo links go back to localhost
```

- The link changes on every `start` and is public while open; share it only with testers and stop it afterwards.
- Testers' sign-ups and data land in the demo database. Reset afterwards if needed.
- Running `docker compose up` while the tunnel is open recreates Profile with localhost photo links; run `stop` and `start` again.

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
docker compose exec postgres psql -U notification -d notification -c 'SELECT event_id,recipient_id,event_type,read_at FROM notifications ORDER BY occurred_at DESC LIMIT 5;'
docker compose exec postgres psql -U scheduling -d scheduling -c 'SELECT id,title,status,starts_at FROM runs ORDER BY created_at DESC LIMIT 5;'
docker compose exec postgres psql -U reputation -d reputation -c 'SELECT run_id,runner_id,distance_meters,duration_seconds FROM running_records ORDER BY created_at DESC LIMIT 5;'
docker compose exec redis redis-cli --scan --pattern 'forecast:*'
```

Copy a forecast key from the last command, then run `docker compose exec redis redis-cli GET '<key>'` and `docker compose exec redis redis-cli TTL '<key>'`. Match IDs and values to the browser action; merely showing a running database container is not sufficient evidence. `contracts/persistence-proof.json` records only non-secret probe identifiers.

## Replace a service with a teammate implementation

`contracts/` contains exported live OpenAPI and event documentation. Discovery's source contract is in `../buddy-discovery-service/proto/`; the gateway's contract copy must match it. Set `IDENTITY_URL`, `PROFILE_URL`, `CONDITIONS_URL`, `SCHEDULING_URL`, `NOTIFICATION_URL`, `REPUTATION_URL` or `DISCOVERY_TARGET` in `.env`, then recreate the gateway and affected callers. For services running on the host, containers generally reach them through `host.docker.internal`. Ensure JWT issuer/audience/key compatibility first. Never expose the signing secret in frontend environment variables.

Run contract and flow checks before switching. Adapt payload differences explicitly. Changing a URL does not migrate local accounts or run data. RabbitMQ/Kafka differences require a transport adapter; event JSON compatibility alone is insufficient.

## Trust & Safety

The stack runs `trust-safety`, `trust-safety-worker` and `trust-safety-publisher` behind the gateway. On a Postgres volume created before this service existed, add its database once after the stack is up; a new volume needs nothing:

```sh
./scripts/add-trust-safety-database.sh
docker compose up -d
```

Set `MODERATOR_IDS` in `.env` to the account UUIDs allowed to moderate. Without it, nobody can. Until Identity exposes its lock route, suspensions are recorded and published, but the runner can still sign in. Identity does not publish `PhoneVerified` yet, so badges are not granted automatically. The k8s manifests do not include this service.

## Scope and boundaries

Search is delegated by Discovery to Profile's temporary search endpoint; Discovery does not yet consume `ProfileUpdated` into its own read model. Profile public reads omit private coordinates. Phone verification is distinct from a Trust & Safety badge. Admin, moderation, reports, suspension, written reviews, reminders, public-history privacy settings and invite-only runs are deferred. Ended-run attendance opens on confirmation access; no scheduled end-run event consumer is claimed. Scheduling owns completion; Reputation persists confirmation after Scheduling accepts it. A retry reconciles a partially completed cross-service confirmation.

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


## Video database viewer

The optional [monitoring setup](monitoring/README.md) adds localhost pgweb at port 8081 with per-service bookmarks and a dedicated viewer limited to selected live views. Start with `./scripts/start-monitoring.sh` after initializing the demo; stop with `./scripts/stop-monitoring.sh`. Redis proof uses the existing CLI, and RabbitMQ uses its existing dashboard. No application service or endpoint changes are needed.
