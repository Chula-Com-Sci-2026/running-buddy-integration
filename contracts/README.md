# Contract catalog

The JSON OpenAPI files are snapshots exported from the running services. Each service's actual `/openapi.json` is authoritative for its implemented HTTP routes. Gateway catch-all proxy routes are generic in OpenAPI; downstream contracts define the forwarded resource schemas. The older frontend YAML is a draft and does not describe every added Activity route.

| Surface | Contract |
|---|---|
| Identity | `identity.openapi.json` |
| Profile | `profile.openapi.json` |
| Run Conditions | `conditions.openapi.json` |
| Run Scheduling | `scheduling.openapi.json` |
| Notification | `notification.openapi.json` |
| Gateway | `gateway.openapi.json`; route matrix below |
| Discovery | `../../buddy-discovery-service/proto/buddy_discovery/v1/buddy_discovery.proto` |
| Reputation | `reputation.openapi.yaml` |
| Broker | `events.md` |

All protected HTTP requests carry `Authorization: Bearer <JWT>`. gRPC carries the same value in lowercase `authorization` metadata. Tokens use issuer `cant-run-alone-local`, audience `cant-run-alone-services`, HS256 and a 15-minute expiry. Refresh tokens are HttpOnly, SameSite=Lax cookies scoped to `/api/v1/auth`; rotating/revoked state is stored in Identity. The signing key is local configuration and is never part of this catalog.

## Gateway routing

- `POST /api/v1/auth/{register,verify-otp,login,refresh,logout}` -> Identity; request/response schemas in Identity contract.
- `GET /api/v1/runners` -> Discovery `SearchRunners`, whose JSON payload contains public Profile runner views. Filters: `radiusKm`, `experience`, `pace`, `availability`, `verifiedOnly`. In the local implementation a nonempty pace filter other than `Any` requests overlap with the caller's saved pace range. Trust badges are deferred, so `verifiedOnly=true` returns no approved badges.
- `GET /api/v1/runners/{uuid}`, `GET/PUT /api/v1/me/profile` -> Profile.
- `GET/POST /api/v1/buddy-requests` -> Discovery list/send; send body `{ "runnerId": "UUID" }`. Gateway derives sender from token. Optional old frontend `note` is not persisted by the current protobuf contract.
- `PATCH /api/v1/buddy-requests/{uuid}` -> Discovery response; body `{ "decision": "accepted" }` or `rejected`. `DELETE` cancels a sender-owned pending request.
- `GET /api/v1/buddies` -> Discovery; returns array of buddy UUIDs.
- `/api/v1/runs` and run membership operations -> Scheduling.
- `GET /api/v1/conditions` -> Run Conditions.
- `/api/v1/notifications` and `PATCH /api/v1/notifications/{uuid}/read` -> Notification.
- `/api/v1/running_records`, `/api/v1/me/history`, `POST /api/v1/runs/{uuid}/attendance`, `POST /api/v1/runs/{uuid}/ratings`, and `GET /api/v1/runners/{uuid}/rating-summary` -> Reputation.
- `GET /api/v1/dashboard` aggregates current profile, cumulative record distance and the next scheduled run, which may be null. The total is cumulative history, not a weekly metric.

Use UUID IDs, ISO-8601 timestamps with timezones, metres/seconds for stored running records and kilometres for run plans. Run form date/time is interpreted as Asia/Bangkok. Ratings are integers 1–5. HTTP statuses: 401 unauthenticated, 403 forbidden, 404 missing, 409 conflicting lifecycle/capacity/duplicate (some Rails validation duplicates return 422), 422 invalid input, 503 unavailable collaborator/provider. Rails record errors preserve the original D3 nested error envelope; newer errors use `code`/`message`. FastAPI body validation uses its native `detail` list. Consumers should tolerate these documented shapes; a unified error envelope remains future cleanup.

Search locations are area/distance only. Unjoined run pins are rounded; participant IDs/confirmed IDs and exact coordinates are visible only to joined runners. Phone verification is distinct from a moderation-approved badge.
