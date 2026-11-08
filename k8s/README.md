# Kubernetes deployment (Deliverable 5)

Runs the same stack as `compose.yaml` — gateway, seven domain services, two workers, PostgreSQL, Redis and RabbitMQ — on a local single-node k3s cluster. This is a course demo of service discovery and non-functional requirement management, not a production or high-availability deployment. Compose remains the default workflow and is unaffected.

## Decisions

| Topic | Choice | Reason |
|---|---|---|
| Cluster | Dedicated Colima profile `cra-k8s` with k3s (`colima start --kubernetes`); other local clusters work, see [Not using Colima?](#not-using-colima) | Already part of the macOS/Colima setup. A separate VM never touches the Compose VM (`default` profile) or its volumes. k3s uses the VM's Docker daemon, so locally built images need no registry. |
| Profile, Notification | **Team services** (`../team-profile-service`, TypeScript; `../team-notification-service`, FastAPI) | Adopted on 8 Nov 2026 as the default in Compose and Kubernetes; they implement the contracts in `running-buddy-contracts`. Same Service names and port 8000 as before, so callers are unchanged. Profile adds its photo storage (`profile-storage`, MinIO) and publishes `ProfileUpdated`. The Python versions are not deployed. |
| Identity | **Team Identity** (`../team-identity-service`, Express, ADR-0023 bcrypt) | Adopted for the demo on 17 Oct 2026 (Deliverable 4 plan). Same settings as `compose.team-identity.yaml`, `identity_team` database, port 5000. The Python fallback is not deployed. |
| Discovery | Kubernetes Services + cluster DNS (CoreDNS) | No service mesh or external registry. Destinations stay configuration: `service-endpoints` ConfigMap holds the same variables as Compose. |
| Migrations | One Job per service, run by `deploy.sh` before any Deployment | Kubernetes has no `depends_on`. Scaling a Deployment never runs a migration. All three migrators also take a PostgreSQL advisory lock and record versions, so an overlap would still be safe. |
| Database setup | Idempotent `db-bootstrap` Job | Creates a role and an owned database per service; never drops anything. No CREATEDB/superuser for application roles. |
| Browser access | NodePort `gateway-public` → http://localhost:30090 | Colima forwards node ports to macOS. Unlike `kubectl port-forward`, it balances over every ready gateway pod. |
| Gateway → Discovery gRPC | Headless Service + `round_robin`, Discovery closes connections after 30 s | Measured below: the Compose-style ClusterIP target pins every call to one pod. |

## Prerequisites

`brew install kubectl k6 kubeconform` (k6 and kubeconform only for load tests/validation). Colima 0.9 with the `vz` VM type. The sibling repositories must be checked out next to this one, as for Compose.

The VM uses 6 CPUs and 6 GiB by default (`CPUS=… MEMORY_GIB=… k8s/scripts/cluster-up.sh`). It can run while the Compose VM is up, but both share the host; stop other VMs before load tests.

### Not using Colima?

> [!IMPORTANT]
> The scripts were written and tested on macOS with Colima. Only `cluster-up.sh` calls Colima. Every other script uses whatever cluster and Docker daemon `KUBE_CONTEXT` and `DOCKER_CONTEXT` name, so any local Kubernetes works if it meets these three requirements:
>
> 1. **Images built by `build-images.sh` are visible to the cluster.** Every manifest uses `imagePullPolicy: Never` with `cra/*:local` images, so a pod stays in `ErrImageNeverPull` if the image is not already in the node's container runtime. There is no registry.
> 2. **A default StorageClass exists**, for the PostgreSQL, Redis and RabbitMQ PersistentVolumeClaims.
> 3. **NodePort 30090 is reachable on `localhost`**, or you forward the gateway yourself.
>
> Give the cluster at least 6 CPUs and 6 GiB, as for the Colima VM.

**Docker Desktop (macOS, Windows, Linux), recommended alternative.** Enable Kubernetes in Docker Desktop settings with the **kubeadm** cluster type and raise Resources to 6 CPUs / 6 GiB. With kubeadm, images you build with Docker Desktop are used by the cluster directly, a default StorageClass (`hostpath`) exists, and NodePorts are published on `localhost`. Skip `cluster-up.sh`, find the context names with `kubectl config get-contexts` and `docker context ls`, then run the other scripts with them:

```sh
export KUBE_CONTEXT=docker-desktop
export DOCKER_CONTEXT=desktop-linux   # the Docker Desktop entry in `docker context ls`
k8s/scripts/build-images.sh
k8s/scripts/deploy.sh
k8s/scripts/seed-demo.sh
k8s/scripts/check.sh
```

Docker Desktop's **kind** cluster type does not share Docker's images; use kubeadm.

**minikube, kind, k3d or another cluster.** Skip `cluster-up.sh`, set `KUBE_CONTEXT` to your cluster's context and leave `DOCKER_CONTEXT` at your normal Docker context (`DOCKER_CONTEXT=default`). After `build-images.sh`, copy each `cra/*:local` image into the cluster (`minikube image load`, `kind load docker-image` or `k3d image import`) before `deploy.sh`. These clusters do not publish NodePorts on `localhost`, so reach the gateway with `kubectl --context "$KUBE_CONTEXT" -n cra port-forward svc/gateway 30090:8000`. A port-forward sends all traffic to one gateway pod, so use it for the demo, not for the replica comparison.

**Windows.** The scripts are POSIX `sh`; run them from WSL 2 or Git Bash, not PowerShell.

These alternatives follow each tool's documented behavior but have not been run by the team; the measured results in this README come from the Colima setup.

## Start

From `running-buddy-integration/`:

```sh
k8s/scripts/cluster-up.sh      # create/resume the cra-k8s VM; restores your Docker context afterwards
k8s/scripts/build-images.sh    # build cra/*:local into the VM (re-run after code changes, e.g. build-images.sh gateway)
k8s/scripts/deploy.sh          # secrets -> data stores -> db-bootstrap -> migrations -> applications
k8s/scripts/seed-demo.sh       # Ray/Mali, profiles (through Profile's API), prepared past run (insert-only)
k8s/scripts/check.sh           # existing check_flows.py + check_broker.py, run inside the cluster
```

**A cluster deployed before 8 Nov 2026** still holds the Python Profile and Notification tables. Run `k8s/scripts/switch-to-team-profile-notification.sh` once before `deploy.sh`: it renames them to `profile_legacy` / `notification_legacy` (nothing is deleted), creates empty databases for the team migrations and removes the Python worker's broker queue and fanout `cra.dead` exchange.

Every script passes `--context colima-cra-k8s` (`KUBE_CONTEXT`) and `--context colima-cra-k8s` for Docker, so your current kubectl and Docker contexts are not used or changed.

Frontend against the cluster (from `../cant-run-alone-frontend`, open http://localhost:5173 — use `localhost`, not `127.0.0.1`, so refresh cookies stay same-site):

```sh
VITE_API_BASE_URL=http://localhost:30090/api/v1 npm run dev
```

RabbitMQ management, when needed: `kubectl --context colima-cra-k8s -n cra port-forward svc/rabbitmq 15679:15672` (user `cra`, password from the Secret).

## What is deployed

| Workload | Kind | Service (DNS name: port) | Probes | Storage |
|---|---|---|---|---|
| postgres | StatefulSet | `postgres:5432` | `pg_isready` | PVC 5 Gi |
| redis (AOF) | StatefulSet | `redis:6379` | `redis-cli ping` | PVC 1 Gi |
| rabbitmq | StatefulSet | `rabbitmq:5672`, `:15672` | diagnostics ping / port check | PVC 1 Gi |
| identity (team) + identity-worker | Deployment | `identity:5000` | HTTP `/up` (DB) | — |
| profile-storage (MinIO) | StatefulSet | `profile-storage:9000`, NodePort `30091` | HTTP `/minio/health/ready` | PVC 1 Gi |
| profile (team) | Deployment | `profile:8000` | HTTP `/ready` (DB) | — |
| conditions | Deployment | `conditions:8000` | HTTP `/ready` (Redis) | — |
| scheduling | Deployment | `scheduling:8000` | HTTP `/up` (DB) | — |
| notification (team) + notification-worker | Deployment | `notification:8000` | HTTP `/up`; worker: ready file | — |
| discovery + discovery-outbox | Deployment | `discovery:50051`, `discovery-headless:50051` | TCP (no gRPC health service exists) | — |
| reputation | Deployment | `reputation:3000` | HTTP `/up` | — |
| gateway | Deployment | `gateway:8000`, NodePort `30090` | HTTP `/up` | — |

All names and ports match Compose, which is why `check_flows.py` runs unmodified. Readiness probes remove a pod from its Service until its dependency works; liveness probes are TCP-only so a database outage does not cause restart loops. HTTP pods sleep 5 s in `preStop` so kube-proxy drops the endpoint before the server stops. Every container has CPU/memory requests and limits (application pods: 100m request, 1 CPU limit — uvicorn and Puma run one process per pod). Workers have no port and therefore no probe; the kubelet restarts them if they exit. Init containers wait for PostgreSQL/RabbitMQ in place of Compose `depends_on: service_healthy`.

Secrets: `create-secrets.sh` generates `cra-secrets` (PostgreSQL superuser, shared application DB password as in Compose, JWT key, broker password, team Identity refresh key) once, inside the cluster. Nothing is written to the repository. Each Deployment receives only the keys it uses, and each service's `DATABASE_URL` names only its own database and role.

Unchanged guarantees: each service owns its database (verified: every table in each database is owned by that service's role); every service validates the JWT itself and applies its own authorization; the browser reaches only the gateway.

## Service discovery

Callers use the Service name, never a pod address. `profile` resolves (via the namespace search path) to `profile.cra.svc.cluster.local`, a stable ClusterIP; kube-proxy forwards each new TCP connection to a ready pod listed in the Service's EndpointSlice. When a pod is replaced, the EndpointSlice changes and the name does not.

To use a different implementation, edit `service-endpoints.yaml` (or `kubectl -n cra edit configmap service-endpoints`) and restart the callers (`kubectl -n cra rollout restart deployment/gateway`). Discovery and Scheduling read their single dependency URL from the same ConfigMap.

### Measured: pod replacement (HTTP)

`k8s/scripts/replacement-demo.sh` (Profile at 2 replicas, 20 req/s through the gateway, both original pods deleted one after the other) — `../load-tests/results/20261031T035915Z-replacement-profile/`:

- 2,000 requests, **2,000 succeeded, 0 failed**; p50 11 ms, p95 22 ms, max 676 ms (single slow second right after the first deletion).
- Pod IPs changed from 10.42.0.26/.35 to 10.42.0.37/.38; `profile` and `profile.cra.svc.cluster.local` resolved to 10.43.28.236 before and after.
- Each replacement was Ready about 3 s after deletion.

This holds because the gateway opens a new HTTP connection per request, so each request goes to an endpoint that is currently ready.

### Measured: gRPC and replicas

`k8s/scripts/grpc-check.sh` (1 gateway pod, 2 Discovery pods, 10 req/s on `GET /api/v1/buddy-requests`; calls counted from each Discovery pod's own log) — `../load-tests/results/20261031T040636Z-grpc-check/` and, with the connection-age setting, `20261031T041352Z-grpc-check/`:

| Situation | ClusterIP target (`discovery:50051`, gRPC default pick_first — the Compose setting) | Headless + `round_robin` | Headless + `round_robin` + 30 s max connection age (deployed) |
|---|---|---|---|
| 2 ready pods, 30 s | 300 / 0 calls (100 % one pod) | 150 / 150 | 150 / 150 |
| Busiest pod deleted mid-probe | 749/750 ok; 1 × 503, ~2 s stall; afterwards all calls on one pod, the other 0 | 749/750 ok; 1 × 503; replacement pod got 40 % | 749/750 ok; 1 × 503; replacement got 36 % |
| Scale 1 → 2 mid-probe (no failure) | added pod 0 calls | **added pod 0 calls** | added pod 27 % of the 60 s probe (joins within ~30 s), 0 failures |

Conclusions: a long-lived HTTP/2 channel is balanced per connection, not per call, so a ClusterIP Service alone does not spread gRPC load. `round_robin` over the headless Service spreads calls over the pods DNS returned when the channel last resolved, but it only re-resolves after a connection breaks. The server-side maximum connection age makes the gateway reconnect and re-resolve every 30 s, so scaled-out pods are used. Deleting a busy pod still fails the one call in flight on its connection (HTTP did not, because each request opens a new connection); a gateway retry for idempotent reads would remove it and is proposed, not implemented.

Application changes made for this (both opt-in, Compose behaviour unchanged when unset):

- `api-gateway/app.py`: `DISCOVERY_LB_POLICY` env sets the channel's `grpc.lb_policy_name`.
- `buddy-discovery-service/bin/grpc-server`: `GRPC_MAX_CONNECTION_AGE_MS` (and `GRPC_MAX_CONNECTION_AGE_GRACE_MS`, default 10 s) set the server's max connection age.

## Load tests

See [`../load-tests/README.md`](../load-tests/README.md) for the 10,000-profile dataset, k6 scenarios, targets and measured results.

## Demo sequence (~90 s of discovery evidence)

1. (10 s) `kubectl --context colima-cra-k8s -n cra get pods,svc` — every service has a stable Service name.
2. (15 s) `kubectl -n cra get configmap service-endpoints -o yaml` — the gateway's destinations are Service names, configurable as in Compose.
3. (45 s) `k8s/scripts/replacement-demo.sh` — show the per-second probe lines staying at `failed=0` while the timeline logs each deletion and `2/2 ready again`. (Start it before recording; it runs about 2 minutes.)
4. (20 s) Show `summary.md` of that run: endpoints changed, DNS answer identical, 0 failures. Then the gRPC table above: ClusterIP 100/0 versus round_robin 50/50, and the scale-out row.

## Cleanup

```sh
colima stop --profile cra-k8s                 # stop the VM; all cluster data and images are kept
kubectl --context colima-cra-k8s delete namespace cra   # DELETES the cluster's databases (PVCs) — only if intended
colima delete --profile cra-k8s               # remove the whole VM — only if intended
```

None of these touch the Compose VM, its volumes, or the demo data stored there.

## Troubleshooting

- `ErrImageNeverPull`: the image is not in the VM's daemon; run `k8s/scripts/build-images.sh <name>`.
- A Job stuck in `deploy.sh`: `kubectl -n cra logs job/<name>`; jobs are deleted and recreated on every deploy.
- `Valid access token required` from a service but not the gateway: the pod started before `cra-secrets` existed; `kubectl -n cra rollout restart deployment/<name>`.
- `docker compose` now talks to the wrong VM: `docker context use colima` (Colima switches contexts on `colima start`; `cluster-up.sh` restores it).
- `localhost:30090` not answering: `kubectl -n cra get endpoints gateway-public`; Colima's port forwarder may need `colima stop/start --profile cra-k8s`.
- Discovery calls all hit one pod after scaling: wait 30 s (connection age) or restart the gateway.

## Limitations

Single node, single PostgreSQL/Redis/RabbitMQ instance: pod rescheduling is demonstrated, node failure and data-store failover are not, and no uptime figure (NFR-3.1) can be derived from these short local runs. Rails services run the same development images and `RAILS_ENV=development` as Compose. Containers run as their images' default users. Discovery readiness is TCP-only until it exposes `grpc.health.v1`. The shared HS256 key keeps the ADR-0022 trust limitation.
