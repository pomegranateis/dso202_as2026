# DSO202 — Practical 2: Persistent Storage and StatefulSets in Kubernetes

## Purpose

This repository implements DSO202 Practical 2 (list of practicals, item 2:
"Implement persistent storage for a stateful application in Kubernetes"). It
covers, using a local `kind` cluster:

- static and dynamic PersistentVolume provisioning
- StorageClasses and reclaim policies (`Retain` vs `Delete`)
- why a Deployment cannot safely own per-replica state
- StatefulSets: stable identity, stable storage, stable network identity, and
  ordered operations
- headless Services and per-Pod DNS
- a real stateful application (PostgreSQL) deployed on retained storage

## Environment

| Component  | Version                                                     |
|------------|--------------------------------------------------------------|
| OS         | Linux (pom-linux)                                            |
| Docker     | 28.0.1                                                        |
| kind       | v0.32.0                                                       |
| kubectl    | v1.36.0 (client)                                              |
| Kubernetes | v1.36.1 (kind node image `kindest/node:v1.36.1`)              |
| PostgreSQL | 18-alpine (used in later stages)                              |

## Repository structure

```
dso202-practical-02/
├── README.md
├── cluster/
│   └── kind-cluster.yaml
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-quota-and-limits.yaml
│   ├── 02-storageclass-retain.yaml
│   ├── 03-pv-static.yaml
│   ├── 04-pvc-static.yaml
│   ├── 05-pod-static-writer.yaml
│   ├── 06-pvc-dynamic.yaml
│   ├── 07-pod-dynamic-writer.yaml
│   ├── 08-deployment-shared-pvc.yaml
│   ├── 09-service-webnote.yaml
│   ├── 10-statefulset-webnote.yaml
│   ├── 11-pod-client.yaml
│   ├── 12-secret-postgres.yaml
│   ├── 13-service-postgres.yaml
│   └── 14-statefulset-postgres.yaml
├── evidence/
└── report/
    └── practical-02-report.md
```

## Rebuild sequence (from an empty machine)

```bash
# 1. Prerequisites
mkdir -p /tmp/dso202-p2-storage

# 2. Cluster
kind create cluster --config cluster/kind-cluster.yaml
# fallback if node-name patches fail:
# kind create cluster --config cluster/kind-cluster-fallback.yaml

# 3. Namespace, quota, storage class
kubectl apply -f manifests/00-namespace.yaml
kubectl config set-context --current --namespace=dso202-practical-02
kubectl apply -f manifests/01-quota-and-limits.yaml
kubectl apply -f manifests/02-storageclass-retain.yaml

# 4. Static provisioning
kubectl apply -f manifests/03-pv-static.yaml
kubectl apply -f manifests/04-pvc-static.yaml
kubectl apply -f manifests/05-pod-static-writer.yaml
kubectl wait --for=condition=Ready pod/static-writer --timeout=90s

# 5. Dynamic provisioning (Stage 3)
kubectl apply -f manifests/06-pvc-dynamic.yaml
kubectl apply -f manifests/07-pod-dynamic-writer.yaml

# 6. Deployment anti-pattern demo (Stage 4)
kubectl apply -f manifests/08-deployment-shared-pvc.yaml
# ... observe, then:
kubectl delete -f manifests/08-deployment-shared-pvc.yaml

# 7. StatefulSet — webnote (Stage 5-6)
kubectl apply -f manifests/09-service-webnote.yaml
kubectl apply -f manifests/10-statefulset-webnote.yaml
kubectl apply -f manifests/11-pod-client.yaml

# 8. PostgreSQL StatefulSet (Stage 7)
kubectl apply -f manifests/12-secret-postgres.yaml
kubectl apply -f manifests/13-service-postgres.yaml
kubectl apply -f manifests/14-statefulset-postgres.yaml
```

## Cleanup sequence

```bash
kubectl delete -f manifests/
kubectl delete pvc --all
kubectl get pv
kubectl delete pv <released-pv-name>   # for each PV left in Released phase

kubectl config set-context --current --namespace=default
kind delete cluster --name dso202-p2

# Only after evidence has been captured:
rm -rf /tmp/dso202-p2-storage
```

## Status

- [x] Stage 0 — Prerequisites and verification
- [x] Stage 1 — Cluster, namespace, storage landscape
- [x] Stage 2 — Static provisioning and Retain
- [ ] Stage 3 — Dynamic provisioning
- [ ] Stage 4 — Deployment anti-pattern
- [ ] Stage 5 — StatefulSets and stable identity
- [ ] Stage 6 — Scaling, retention, ordered updates
- [ ] Stage 7 — PostgreSQL StatefulSet
- [ ] Stage 8 — Cleanup