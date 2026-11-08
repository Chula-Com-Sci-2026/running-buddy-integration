# Database evidence for the video

Use **pgweb for PostgreSQL**, **redis-cli for Redis**, and the existing **RabbitMQ management dashboard**. This is inspection/evidence tooling, not a metrics-monitoring system; adding Grafana or a second database GUI is unnecessary for a five-minute recording.

## Start for recording

From `running-buddy-integration/`, first start the normal demo (team Identity branch), then add pgweb:

```sh
./scripts/start-team-identity.sh
./scripts/start-monitoring.sh
```

Start the frontend separately as usual. The monitoring script creates a random local viewer password in the ignored `.env`, prepares live views, and starts only PostgreSQL/pgweb if the app is otherwise stopped. It does not start the other app services. Initial application migrations must already exist.

| Tool | Location | Show |
|---|---|---|
| pgweb | http://localhost:8081 | Real service databases and rows after a UI action |
| RabbitMQ | http://localhost:15678 | `notifications.events` consumers/delivery activity; `identity.email.v1` is separate |
| Redis CLI | Terminal inside `running-buddy-integration/` | Actual forecast JSON and its remaining TTL |

pgweb has bookmarks for team Identity, Profile, Discovery, Scheduling, Reputation, Notification and the Python Identity fallback. Pick a bookmark and **Connect**, expand **demo_monitor → Views**, then select the appropriate view. pgweb may initially expand `public`; those raw tables are intentionally inaccessible to the viewer. For the active demo choose **01-Identity-team**, not the fallback bookmark.

The `demo_monitor` views execute SELECTs against the actual service tables. They are not copied data or fixtures. The separate `demo_viewer` role has SELECT only on these views; it cannot modify rows or read raw credential tables. The views exclude password hashes, refresh-token records, OTPs and private profile coordinates. The pgweb read-only flag is an additional convenience, not the only protection. No app role gains monitoring privileges. The viewer binds only to localhost; bookmarks reference a password environment variable, so no credentials are committed in bookmark files.

## Short recording sequence

1. Send/accept a buddy request in the app. In pgweb choose Discovery → `demo_monitor` → Views → `buddy_requests`; refresh and match the request ID/status.
2. Show Discovery's `outbox_events` with a non-null `published_at`, then Notification's `notifications` with the matching event ID. RabbitMQ's dashboard shows the active queue consumer and delivery activity. A successfully consumed queue may correctly have zero ready messages.
3. Create/join a run. Scheduling's `runs` and `participants` prove storage and membership.
4. Show Redis immediately after checking live run conditions. Cache entries expire after 15 minutes, so generate a fresh one during rehearsal/recording rather than expecting yesterday's key to remain.
5. After attendance/rating/record actions, show Reputation's corresponding views. Distance and duration should match the app.

Keep pgweb tabs and queries prepared before recording. Useful SQL is saved in `queries/`; use each only with its matching service bookmark. Read-only queries can also be pasted into pgweb's Query editor. Do not spend video time explaining setup or scrolling through connection settings.

## Redis evidence

```sh
docker compose exec redis redis-cli --scan --pattern 'forecast:*'
```

Copy the key for the run's location/time, then:

```sh
docker compose exec redis redis-cli GET '<forecast-key>'
docker compose exec redis redis-cli TTL '<forecast-key>'
```

Explain that the JSON was written/read by Run Conditions in a real local Redis server, and the positive TTL proves expiry is configured. A second matching forecast request should hit the cache. Redis CLI is a more direct and compact proof here than adding a separate Redis GUI.

## Verify and stop

```sh
python3 scripts/check-monitoring.py
./scripts/stop-monitoring.sh
docker compose -f compose.yaml -f compose.team-identity.yaml stop
```

The check verifies actual database permissions: approved views are readable; raw-table access and writes are denied even if a client tries to disable read-only transaction mode. `stop-monitoring.sh` stops pgweb only; the final command stops the app stack and databases without removing volumes. Do not use `down -v`.

Implementation reference: [official pgweb project](https://github.com/sosedoff/pgweb), including its supported bookmarks, multiple sessions and read-only connection options. The image is pinned to the inspected digest (pgweb v0.17.0).
