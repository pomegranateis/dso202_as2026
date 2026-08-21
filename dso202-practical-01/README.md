# DSO202 — Practical 1

Setting Up a Local Kubernetes Cluster with kind, and Deploying First Workloads

## Purpose

This repository contains the manifests, cluster configuration, and evidence
for DSO202 Practical 1. It sets up a three-node Kubernetes cluster locally
using `kind`, then walks through Namespaces, ResourceQuotas, LimitRanges,
Pods, Deployments (rolling updates, rollback, self-healing), and Services
(ClusterIP and NodePort), finishing with a full cleanup and a reproducibility
check.

Descriptor sections covered: Unit I — 1.1, 1.2.1, 1.2.2, 1.2.3, 1.2.4, 1.3.1,
1.3.2, 1.3.3, 1.4.1, 1.5.1, 1.5.3.

## Environment

| Tool | Version used |
|---|---|
| OS | Pop!_OS 22.04 LTS |
| Docker | 28.0.1 |
| kind | v0.32.0 |
| kubectl | v1.36.0 |
| Cluster Kubernetes version | v1.36.1 |

## Repository structure

```
dso202-practical-01/
├── README.md
├── cluster/
│   └── kind-cluster.yaml
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-quota-and-limits.yaml
│   ├── 02-pod-web.yaml
│   ├── 03-deployment-web.yaml
│   ├── 04-service-clusterip.yaml
│   ├── 05-service-nodeport.yaml
│   └── 06-pod-client.yaml
├── evidence/
│   ├── screenshots/            # numbered screenshots, see index below
│   ├── web-imperative-as-stored.yaml
│   ├── final-state-all.txt
│   ├── final-state-nodes.txt
│   └── final-state-events.txt
└── report/
    └── practical-01-report.md
```

## Note on the namespace name

The companion manifest file supplied for this practical was inconsistent —
some listings used `dso202-practical` and others `dso202-practical-01`. This
repository standardises on **`dso202-practical`** everywhere, matching the
guide's own prose and Stage 3/4 command examples.

## Note on the readiness probe

Listings 4 and 5 as supplied did not include a `readinessProbe`, even though
Stage 6 Step 7 of the guide assumes one exists. A `readinessProbe` was added
to `manifests/03-deployment-web.yaml` so that readiness-gated traffic routing
could be demonstrated as intended. See the report's Reflection section for
details.

## Rebuilding from an empty machine

```bash
# 1.Install tools (see official docs for each)
# Docker Engine >= 24.0
# kind >= v0.32.0
# kubectl v1.35 / v1.36 / v1.37

# 2.Create the cluster
kind create cluster --config cluster/kind-cluster.yaml

# 3.Apply every manifest (lexical order via numbered filenames)
kubectl apply -f manifests/

# 4.Set the default namespace for convenience
kubectl config set-context --current --namespace=dso202-practical

# 5.Verify
kubectl get all
kubectl diff -f manifests/ && echo "cluster matches repository"
```

Reach the app once running:

```bash
curl -s http://localhost:30080          # NodePort, from the host
kubectl exec client-pod -- wget -qO- http://web-clusterip   # ClusterIP, from inside the cluster
```

## Cleanup

```bash
kubectl delete -f manifests/
kind delete cluster --name dso202
```

## Evidence / screenshot index

Screenshots are numbered in chronological order and stored under
`evidence/screenshots/`. Numbering below reflects the order they were
captured during the practical.

| # range | Stage | Covers |
|---|---|---|
| 1 | Stage 1 | `kind create cluster`, `kind get clusters`, `kind get nodes` |
| 2–8 | Stage 2 | `current-context`, `cluster-info`, `get nodes` / `-o wide`, `describe node worker-node-1`, node labels via jsonpath, `get namespaces`, `kube-system` Pods, `api-resources` |
| 9–12 | Stage 3 | Imperative namespace demo (create/get/delete `dso202-scratch`), `--dry-run` namespace YAML, `describe resourcequota`, `describe limitrange` |
| 13–23 | Stage 4 | Declarative `web-pod` apply (`created` → `unchanged`), resource confirmation + quota check, `describe pod` events, label selectors, label add/remove, annotation, `exec -it … sh`, `nginx -v`, `port-forward` + curl, `kubectl explain` |
| 24–36 | Stage 5 | Dry-run Deployment comparison, self-healing demo, `SuccessfulCreate` event, scale to 5 then revert via re-apply, rolling update to `1.31-alpine` (watch + status), rollout history, revision 1 image check, rollback (`undo`), deliberate failed rollout (`9.99-does-not-exist`), diagnose + recover, final `apply` + `diff` confirming match |
| 37–40 | Stage 6 (start) | ClusterIP Service applied, EndpointSlice check, `client-pod` applied and ready, `nslookup` from `client-pod` |
| 41+ | Stage 6 (rest) | `wget` HTTP test through the Service, load-balancing distribution test, readiness-probe gap identified, probe added and Deployment re-rolled, readiness-gating demo redone (Pod removed from / restored to EndpointSlice), broken-service selector-mismatch demo, NodePort Service applied, `curl localhost:30080`, `docker exec dso202-worker curl …`, LoadBalancer `<pending>` demo |
| (final) | Stage 7 | `final-state-*` evidence capture, declarative delete of all objects, `kubectl get all` confirming empty namespace, full rebuild via `kubectl apply -f manifests/`, settled `kubectl get all`, `kind delete cluster`, confirmation via `kind get clusters` / `docker ps` |

**Still to capture and add to `evidence/screenshots/`:** the Stage 6 items
from "wget HTTP test" onward, and all of Stage 7, per the table above. These
were completed during the practical session but not yet numbered/saved as
screenshot files.

## References

- kind documentation: https://kind.sigs.k8s.io/docs/user/quick-start/
- Kubernetes documentation: https://kubernetes.io/docs/