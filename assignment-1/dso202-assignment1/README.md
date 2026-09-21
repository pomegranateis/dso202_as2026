# DSO202 — Assignment 1: Three-Tier Application Deployment on Kubernetes

**Namespace:** `dso202-assignment-01`
**Cluster:** `kind` (`dso202` — 1 control-plane node, 2 worker nodes)

This repository contains the Kubernetes manifests and supporting documentation for deploying a three-tier Task Tracker application (frontend, backend, database) to a local `kind` cluster, as specified in the DSO202 Assignment 1 brief.

---

## Repository Structure

```
dso202-assignment1/
├── README.md
├── kind-cluster.yaml
├── namespace.yaml
├── common-manifests/
│   ├── configmap.yaml
│   ├── secret.yaml
│   └── quota.yaml
├── database/
│   ├── pvc.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── backend/
│   ├── deployment.yaml
│   └── service.yaml
├── frontend/
│   ├── deployment.yaml
│   └── service.yaml
├── rbac/
│   └── rbac.yaml          # Task 8 bonus
└── evidence/               # screenshots supporting Task 7 verification
```

---

## 1. Architecture Note (Task 1)

### Cluster Topology

The `kind` cluster consists of three Docker containers, each acting as a Kubernetes node:

| Container              | Node role       | Components running                                                                              |
| ----------------------- | --------------- | ------------------------------------------------------------------------------------------------ |
| `dso202-control-plane`  | `control-plane` | `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`, `kubelet`, `kube-proxy`   |
| `dso202-worker`         | `worker-node-1` | `kubelet`, `kube-proxy`, application Pods                                                        |
| `dso202-worker2`        | `worker-node-2` | `kubelet`, `kube-proxy`, application Pods                                                        |

The host maps port `30080` to the same port on the control-plane container via `extraPortMappings` in `kind-cluster.yaml`, which is what allows the frontend's NodePort Service to be reached directly from a browser at `http://localhost:30080`.

**Note on image architecture:** the three provided images (`sarojsanyasi/dso202-frontend`, `-backend`, `-db`, tag `1.0`) are published as `linux/arm64` only — no `amd64` manifest exists (confirmed via `docker manifest inspect`). Since this machine is `x86_64`, the images run under QEMU user-mode emulation (`qemu-user-static` + `binfmt-support`, registered once at the host level via `update-binfmts`), which all three kind node containers inherit automatically since they share the host kernel. Images were pre-pulled on the host with `docker pull --platform=linux/arm64 ...` and injected directly into every node with `kind load docker-image`, rather than left for the nodes to pull themselves — this avoids any platform-negotiation failure at the containerd level inside kind.

### What Happens on the Control Plane for Every Pod

1. **`kube-apiserver`** receives the `kubectl apply`, validates the manifest, and writes it to `etcd`. Every read and write in the cluster passes through this component.
2. **`etcd`** persists the desired state as the cluster's single source of truth.
3. **`kube-scheduler`** watches for unscheduled Pods, evaluates the two worker nodes against resource requests/limits, and binds the Pod to one of them.

The control plane's role is entirely about deciding and recording — it never runs application containers itself.

### What Happens on the Selected Worker Node

1. **`kubelet`** watches the API server for Pods assigned to it, retrieves the required image via the container runtime (`containerd`), and starts the container(s).
2. **`kube-proxy`** programs iptables/IPVS rules so traffic sent to a Service's ClusterIP is forwarded to the correct Pod IP regardless of which node it runs on.
3. **The CNI plugin** (`kindnet`) assigns the Pod an IP from the cluster's pod subnet and wires up cross-node Pod networking.

### Why a Dedicated Namespace

`dso202-assignment-01` is a logical partition within the single physical cluster — it is not tied to any node and does not get its own control plane or scheduler. All three tiers live in one namespace so that:

- Their Services resolve each other by short DNS name (`db-svc`, `backend-svc`) without a fully qualified path.
- Resource governance (ResourceQuota, LimitRange) and RBAC can be scoped to the assignment as a single unit, isolated from `default` and other namespaces on the cluster.

### Object Choice per Tier

| Tier                                | Object Used                            | Why                                                                                                                                                                                                          |
| ------------------------------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Frontend** (nginx, static assets)  | `Deployment`                            | Stateless and interchangeable — any replacement Pod is identical to the one it replaces. Exposed via a `NodePort` Service so it can be reached directly from the host browser.                             |
| **Backend** (REST API)               | `Deployment`                            | Stateless as long as it holds no local session state; all persistence is delegated to Postgres. Exposed internally via a `ClusterIP` Service so only cluster-internal traffic can reach it.                |
| **Database** (PostgreSQL)            | `Deployment` + `PersistentVolumeClaim`  | A single-replica Deployment per the assignment's scope, with its data path backed by a PVC so Pod lifecycle and data lifecycle are decoupled. Exposed via a **headless** Service (`clusterIP: None`) so the backend addresses it by a stable DNS name rather than a load-balanced virtual IP — appropriate for a single-instance database. |

### Supporting Objects (Not Tied to a Single Pod)

| Object                       | Purpose                                                                                                                        |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **ConfigMap** (`app-config`)  | Non-sensitive configuration: `DB_HOST`, `DB_PORT`, `DB_NAME`, `APP_PORT`, `CORS_ORIGIN`, `POSTGRES_DB`, `BACKEND_URL`.         |
| **Secret** (`app-secret`)     | Credential values: `DB_USER`, `DB_PASSWORD`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.                                             |
| **PersistentVolumeClaim**     | Requests storage from kind's default `standard` StorageClass, used exclusively by the database tier.                          |

---

## 2. Configuration and Secrets (Task 2)

All non-sensitive configuration lives in `app-config`; all credentials live in `app-secret`. The two objects are kept strictly separate — no credential value appears in the ConfigMap.

A deliberate naming mismatch exists between the backend's expected variables and the official Postgres image's variables, and is preserved intentionally per the assignment contract:

| Backend expects | Official Postgres image expects | Value        |
| ---------------- | -------------------------------- | ------------- |
| `DB_NAME`         | `POSTGRES_DB`                     | Same value    |
| `DB_USER`         | `POSTGRES_USER`                   | Same value    |
| `DB_PASSWORD`     | `POSTGRES_PASSWORD`               | Same value    |

### ⚠️ Secret Encoding Caveat

**Kubernetes Secrets are base64-encoded, not encrypted, by default.** Base64 is a reversible encoding, not cryptographic protection — anyone with API access to the namespace, or direct access to `etcd`, can trivially decode a Secret's contents (`kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d`). This is documented as a known limitation of the assignment's scope (Unit I), not something remediated within these manifests. A production deployment would additionally require:

- Encryption at rest for Secrets in `etcd`.
- RBAC rules restricting Secret access to only the workloads/users that need it (see Task 8 — the bonus read-only Role deliberately excludes the `secrets` resource entirely, verified with `kubectl auth can-i get secrets ... → no`).
- Consideration of an external secret store (e.g. HashiCorp Vault, a cloud provider's secret manager) rather than native Kubernetes Secrets.

---

## 3. ResourceQuota and LimitRange Justification (Task 6)

### Context

The namespace runs three single-replica Deployments (frontend, backend, database) — three Pods under normal, steady-state operation. Values below were chosen with that baseline plus headroom for temporary duplication during rollouts or Pod recreation (e.g. the Task 7c backend-deletion test).

### ResourceQuota

```yaml
hard:
  requests.cpu: "1500m"
  requests.memory: "1.5Gi"
  limits.cpu: "3000m"
  limits.memory: "3Gi"
  pods: "10"
```

| Value                    | Reasoning                                                                                                                       |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `requests.cpu: 1500m`     | ~500m per tier at request level — sufficient for steady-state nginx, a lightweight REST backend, and a single Postgres instance. |
| `requests.memory: 1.5Gi`  | ~512Mi per tier, sized for Postgres (the heaviest of the three).                                                                |
| `limits.cpu: 3000m`       | Double the total request, allowing each tier to burst without any single tier consuming an entire node's CPU.                   |
| `limits.memory: 3Gi`      | Same doubling logic — burst headroom without unbounded consumption.                                                              |
| `pods: "10"`              | Covers the 3 steady-state Pods plus temporary duplicates during rollouts/recreation, while preventing runaway Pod creation.       |

### LimitRange

```yaml
limits:
  - type: Container
    default:
      cpu: "250m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "500m"
      memory: "512Mi"
    min:
      cpu: "50m"
      memory: "64Mi"
```

**Why the LimitRange is necessary alongside the ResourceQuota:** a ResourceQuota only enforces a ceiling on the sum of requests/limits across the namespace — it does not require individual Pods to declare any resources at all. Since none of the three Deployments specify a `resources:` block, applying the ResourceQuota alone (with `requests.cpu`/`requests.memory` set) would actually **block Pod creation entirely**, because Kubernetes refuses to schedule a Pod with no defined resource requests into a namespace governed by such a quota. The LimitRange resolves this by transparently injecting default requests/limits onto every container, keeping Pods schedulable while remaining properly bounded and accounted for.

Note: since the three application Pods were created *before* the LimitRange existed, `kubectl describe resourcequota` initially showed `0` used despite 3 Pods running — the LimitRange only injects defaults at admission time, so pre-existing Pods are unaffected until they are recreated (e.g. during the Task 7c backend-deletion test, at which point the new Pod picks up the defaults and begins counting toward the quota).

---

## 4. Verification Evidence (Task 7)

Full command transcripts and screenshots are in `evidence/`.

### 7a — Full CRUD Cycle

Verified via Postman against a port-forwarded backend Service (`kubectl port-forward svc/backend-svc <local-port>:8080`), since the frontend's browser-side JavaScript cannot resolve the cluster-internal DNS name `backend-svc` from outside the cluster network (see Section 5). All five operations succeeded: create (`POST /api/tasks` → `201 Created`), list (`GET /api/tasks` → `200`), retrieve single task (`GET /api/tasks/{id}` → `200`), update (`PUT /api/tasks/{id}` → `200`, status changed to `done`), and delete (`DELETE /api/tasks/{id}` → `204 No Content`).

### 7b — Service DNS Resolution

From inside the running frontend Pod (`kubectl exec ... -- curl http://backend-svc:8080/api/status`), the backend Service was reached by name and returned `{"status":"ok","db":"connected"}`, confirming cluster DNS correctly resolves the backend Service from another Pod.

### 7c — Self-Healing and Data Persistence

1. A task was created via the port-forwarded backend and its ID recorded.
2. `kubectl get pods -l tier=backend --watch` was left running in a separate terminal.
3. The backend Pod was deleted manually (`kubectl delete pod -l tier=backend`).
4. The watch output showed the old Pod `Terminating`, then a new Pod (different ReplicaSet hash) reach `Running` within seconds.
5. The port-forward was re-established (a `port-forward` tunnel targets a specific Pod IP at the moment it starts, so it breaks when that Pod is deleted — restarting it against the same Service picks up the new Pod automatically).
6. The previously created task was retrieved successfully through the new backend Pod, confirming that the database's PersistentVolumeClaim — not the backend container's ephemeral filesystem — is what preserves data across Pod recreation.

### 7d — Declarative vs. Imperative Comparison

A ConfigMap was created/compared two ways:

- **Declaratively:** `kubectl apply -f common-manifests/configmap.yaml` — re-applying the already-existing `app-config` produced `configmap/app-config unchanged`, direct evidence of idempotency.
- **Imperatively:** `kubectl create configmap demo-config --from-literal=DEMO_KEY=demo-value` — created and torn down as a throwaway, never touching the real `app-config`.

**Comparison:** the declarative approach is repeatable and idempotent — reapplying the same file with no changes produces no side effects (`unchanged`, as observed), and the YAML itself is a reviewable, version-controlled source of truth, which is why every real resource in this project is managed this way. The imperative approach is faster for one-off or exploratory changes but leaves no record in version control and is harder to reproduce exactly later. In practice, declarative management suits anything intended to persist or be audited, while imperative commands are best reserved for quick, disposable debugging — exactly how `demo-config` was used here.

---

## 5. Known Constraints and Troubleshooting Notes

- **Images are `linux/arm64`-only:** `docker manifest inspect sarojsanyasi/dso202-backend:1.0` shows a single real platform manifest (`arm64`/`linux`), no `amd64`. On this `x86_64` host, images run under QEMU emulation via `qemu-user-static`/`binfmt-support`, installed at the OS level (`apt install qemu-user-static binfmt-support`) rather than via the `tonistiigi/binfmt` Docker-image installer, which itself failed to pull due to intermittent registry connectivity. Images were force-pulled with `--platform=linux/arm64` and injected into all three kind nodes with `kind load docker-image` rather than relying on the nodes to pull them natively.
- **Docker Hub registry connectivity:** pulls intermittently failed with `net/http: TLS handshake timeout` (transient network issue, not a Docker or image problem) — resolved by retrying with a short backoff loop; persistent failures were additionally mitigated by pointing the Docker daemon at public DNS resolvers (`8.8.8.8`, `1.1.1.1`) in `/etc/docker/daemon.json`.
- **Browser-side `BACKEND_URL` limitation:** `BACKEND_URL` resolves correctly *inside* the cluster (Pod-to-Pod), but a browser running on the host machine cannot resolve cluster-internal DNS names like `backend-svc` — the frontend loads correctly at `localhost:30080` (proving the NodePort routing itself works), but its in-page "Backend unreachable" banner is expected client-side behavior, not a misconfiguration. This is a structural characteristic of the assignment's networking design; the brief explicitly permits `curl`/Postman through a port-forwarded backend as the verification path for Task 7a, which is what this submission uses. Making the browser UI fully functional would require exposing the backend via NodePort, which Section 6 of the brief explicitly forbids.
- **Local port 8080 conflict:** a pre-existing local GitLab instance (Puma/Ruby, running under the `git` user) was already bound to `127.0.0.1:8080`, intercepting requests intended for `kubectl port-forward svc/backend-svc 8080:8080` and returning GitLab 404 pages instead of backend responses. Resolved by port-forwarding to an alternate local port (`8090`) instead.
- **`kubectl port-forward` targets a Pod, not the Service's load-balancing:** during the Task 7c self-healing test, the port-forward tunnel broke (`curl: (52) Empty reply from server`) the moment the original backend Pod was deleted, since the tunnel had resolved to that Pod's specific IP at start time. Restarting the port-forward against the same Service picked up the newly created Pod automatically.
- **Minimal runtime images:** the provided images intentionally omit some debugging tools, consistent with the assignment's build standard of minimal, hardened runtime images; `curl` was available inside the frontend image and used directly for Task 7b.

---

## 6. Task 8 (Bonus) — Namespace RBAC

A minimal read-only `ServiceAccount` (`readonly-viewer`) is scoped to `dso202-assignment-01` via a `Role`/`RoleBinding` granting `get`/`list`/`watch` on Pods, Services, ConfigMaps, PVCs, Events, Deployments, and ReplicaSets — **Secrets are deliberately excluded** from the Role's rules, consistent with the Secret encoding caveat in Section 2.

Verified with `kubectl auth can-i`:

| Check                                      | Result |
| -------------------------------------------- | -------- |
| `get pods` (as `readonly-viewer`)            | `yes`  |
| `get secrets` (as `readonly-viewer`)         | `no`   |
| `delete pods` (as `readonly-viewer`)         | `no`   |

---

## About the Images

The three tier images used in the manifests above (`sarojsanyasi/dso202-frontend:1.0`, `sarojsanyasi/dso202-backend:1.0`, `sarojsanyasi/dso202-db:1.0`) are the ones isssued and are used unmodified, per Section 6 of the assignment brief ("No image tag other than the one issued... may be used"). Identical copies were additionally retagged and pushed to a personal Docker Hub account (`pomegranatei/dso202-*:1.0`) as a personal mirror only — the manifests in this repository continue to reference the original `sarojsanyasi/...` images for submission.