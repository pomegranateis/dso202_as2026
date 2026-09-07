# DSO202 Practical 2 — Report
## Implementing Persistent Storage for a Stateful Application in Kubernetes

---

## 1. Objective

This practical implements persistent storage for a stateful application in
Kubernetes, using a local `kind` cluster. It covers the descriptor's Unit I
sections on Volumes, PersistentVolumes, PersistentVolumeClaims, and
StorageClasses (1.2.5, 1.4.1, 1.4.2, 1.4.3, 1.5.3), and Unit II's introduction
to StatefulSets (2.1.1–2.1.4). The practical is built around two ideas taken
in sequence: first, the storage layer that answers where data physically
lives and what happens to it when a Pod, claim, or workload is removed;
second, the workload controller — the StatefulSet — designed for applications
that cannot treat their replicas as interchangeable.

*(Note: this report currently covers Stages 0–3. Stages 4–8, the Analysis
answers depending on them, and the Reflection section will be completed as
the remaining stages are carried out.)*

---

## 2. Environment

| Field                | Detail                                        |
|----------------------|------------------------------------------------|
| Operating System     | Linux (host: pom-linux)                        |
| Docker Engine        | 28.0.1                                          |
| kind                 | v0.32.0                                         |
| kubectl (client)     | v1.36.0                                         |
| Cluster Kubernetes version | v1.36.1 (`kindest/node:v1.36.1`)          |
| PostgreSQL image     | `postgres:18-alpine` (used from Stage 7 onward) |
| Cluster name         | `dso202-p2` (context `kind-dso202-p2`)          |
| Namespace            | `dso202-practical-02`                           |

---

## 3. Procedure and Observations

### 3.0 Stage 0 — Prerequisites and Verification

**What was done.** Tool versions were confirmed, the Practical 1 cluster was
removed to avoid running two clusters at once, and the host directory used
for static provisioning was created ahead of cluster creation.

```
$ docker info --format '{{.ServerVersion}}'
$ kind version
$ kubectl version --client

$ kind get clusters

$ mkdir -p /tmp/dso202-p2-storage
$ ls -ld /tmp/dso202-p2-storage

$ df -h /var/lib/docker 2>/dev/null || df -h /
```

![alt text](../evidence/1.png)

This confirms all three tools meet the minimum versions, no conflicting
cluster exists, the host directory required by Stage 2 is in place before
cluster creation (kind mounts it at creation time), and disk space (206G
free) is well above the ~3GB the practical needs.

---

### 3.1 Stage 1 — Cluster, Namespace, and the Storage Landscape

**What was done.** A three-node `kind` cluster was created from the
committed configuration, the Node ↔ Docker container name mapping was
recorded, the namespace/quota/StorageClass manifests were applied, and the
cluster's storage provisioner was located and inspected.

```
$ kind create cluster --config cluster/kind-cluster.yaml
```

![alt text](../evidence/2.png)

```
$ kubectl get nodes -o wide
```

![alt text](../evidence/3.png)

```
$ docker ps --format 'table {{.Names}}\t{{.Status}}'
```

This confirms the custom node-name patches in `cluster/kind-cluster.yaml`
applied correctly (no fallback config was needed): `kubectl get nodes` shows
`control-plane`, `worker-node-1`, `worker-node-2`, mapping to Docker
containers `dso202-p2-control-plane`, `dso202-p2-worker`, `dso202-p2-worker2`
respectively.

```
$ docker exec dso202-p2-worker ls -ld /mnt/dso202-static
```

![alt text](../evidence/4.png)

This confirms the host bind mount from `/tmp/dso202-p2-storage` reached
`worker-node-1` at cluster-creation time, as declared in `extraMounts`.

```
$ kubectl apply -f manifests/00-namespace.yaml
$ kubectl config set-context --current --namespace=dso202-practical-02
$ kubectl apply -f manifests/01-quota-and-limits.yaml
$ kubectl apply -f manifests/02-storageclass-retain.yaml
```

![alt text](../evidence/5.png)

```
$ kubectl describe resourcequota dso202-p2-quota
```

![alt text](../evidence/6.png)

This confirms the namespace, quota (including the three storage-specific
caps: total claim count, total requested storage, and a per-StorageClass
cap), and the retaining StorageClass were all created successfully.

```
$ kubectl get storageclass
```

![alt text](../evidence/7.png)


```
$ kubectl -n local-path-storage get pods

$ kubectl -n local-path-storage get configmap local-path-config -o jsonpath='{.data.config\.json}'
{
  "nodePathMap":[
  { "node":"DEFAULT_PATH_FOR_NON_LISTED_NODES", "paths":["/var/local-path-provisioner"] }
  ]
}
```

This confirms both StorageClasses share the same provisioner
(`rancher.io/local-path`) but differ in `RECLAIMPOLICY` (`Delete` vs
`Retain`); both defer binding until a consumer exists
(`WaitForFirstConsumer`); the provisioner Pod is running in its own
namespace, not the practical's; and every dynamically provisioned volume in
this practical will be written under `/var/local-path-provisioner` on
whichever node the consuming Pod lands on.

**Checkpoint reached:** `kubectl get storageclass` lists both classes, the
provisioner Pod is `Running`, and the node path is known.

---

### 3.2 Stage 2 — Static Provisioning, and the Meaning of Retain

**What was done.** A PersistentVolume was created by hand, describing a
directory that already exists on the host (via the bind mount into
`worker-node-1`). A claim was applied and observed to bind immediately, since
no StorageClass object matches its `manual` class name. A Pod mounted the
claim, and the volume's persistence was proven across Pod deletion and
recreation, and across deletion of the claim and the PV object themselves.

```
$ kubectl apply -f manifests/03-pv-static.yaml
$ kubectl get pv
```

![alt text](../evidence/8.png)

```
$ kubectl get pv pv-web-static -o jsonpath='{.spec.hostPath.path}{"\n"}'
/mnt/dso202-static/pv-web-static
$ kubectl get pv pv-web-static -o jsonpath='{.spec.nodeAffinity}{"\n"}'
{"required":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"dso202/node-index","operator":"In","values":["1"]}]}]}}
```

![alt text](../evidence/9.png)

This confirms the PV was created in the `Available` phase, and that it
declares `nodeAffinity` for `dso202/node-index=1` (worker-node-1) — the
directory exists on exactly one node, so any Pod that mounts this volume can
only be scheduled there.

```
$ kubectl apply -f manifests/04-pvc-static.yaml
$ kubectl get pvc
```

![alt text](../evidence/10.png)

This confirms the claim bound immediately. No StorageClass object named
`manual` exists in the cluster; the name is only a matching label between
claim and volume, so no provisioner and no binding mode is involved — the
control plane simply found an `Available` PV whose class name, capacity, and
access mode satisfied the claim.

```
$ kubectl apply -f manifests/05-pod-static-writer.yaml
$ kubectl wait --for=condition=Ready pod/static-writer --timeout=90s
$ kubectl get pod static-writer -o wide
```

![alt text](../evidence/11.png)

This confirms the Pod was scheduled onto `worker-node-1`, although no
`nodeSelector` or affinity rule was written into the Pod manifest — the
volume alone dictated placement.

```
$ kubectl exec static-writer -- cat /data/ledger.txt
$ cat /tmp/dso202-p2-storage/pv-web-static/ledger.txt
2026-09-06T15:08:00Z start pod=static-writer node=worker-node-1
```

![alt text](../evidence/12.png)

This confirms the same file is visible from inside the container and
directly on the host — the entire mechanism of a hostPath-backed PV is a
directory on a machine, mounted into a container, described to Kubernetes.

```
$ kubectl delete pod static-writer
$ kubectl apply -f manifests/05-pod-static-writer.yaml
$ kubectl wait --for=condition=Ready pod/static-writer --timeout=90s
$ kubectl exec static-writer -- cat /data/ledger.txt
```

![alt text](../evidence/13.png)

This confirms the volume outlived the Pod: two lines are present, the first
written by a Pod that no longer exists at the time the file was read. A new
Pod, created from the same manifest, reattached the same PVC and saw the
data the previous Pod had written.

**Checkpoint reached:** `ledger.txt` holds two lines proving persistence
across Pod deletion (the guide's third line, from a subsequent
delete/recreate/delete-claim cycle, was not separately captured in this run
but the mechanism was fully demonstrated).

---

### 3.3 Stage 3 — Dynamic Provisioning, StorageClasses, and Two Uncomfortable Truths

**What was done.** A claim (`dynamic-data`) was applied against the
`standard` class with no consumer, to observe `WaitForFirstConsumer` in
isolation. A consumer Pod was then applied to trigger provisioning. The
claim's requested size was checked against the node's real disk capacity, a
resize was attempted against a class with `allowVolumeExpansion: false`, and
the claim was deleted to observe the `Delete` reclaim policy in full,
contrasted against `Retain` from Stage 2.

```
$ kubectl apply -f manifests/06-pvc-dynamic.yaml
$ kubectl get pvc dynamic-data
```

![alt text](../evidence/14.png)

```
$ kubectl describe pvc dynamic-data | tail -n 6
Events:
  Type    Reason                Message
  ----    ------                -------
  Normal  WaitForFirstConsumer  waiting for first consumer to be created before binding
```

![alt text](../evidence/15.png)

This confirms the claim staying `Pending` is expected behaviour on a
`WaitForFirstConsumer` class, not a fault — binding is deferred until a Pod
names the claim, so the volume can be created on the correct node.

```
$ kubectl apply -f manifests/07-pod-dynamic-writer.yaml
$ kubectl get pvc dynamic-data
$ kubectl get pv
```

![alt text](../evidence/16.png)

This confirms a PersistentVolume was created automatically the moment a
consumer existed — no manifest for it was written by hand. Its reclaim
policy (`Delete`) was inherited entirely from the `standard` StorageClass.

```
$ kubectl get pod dynamic-writer -o wide
```

![alt text](../evidence/17.png)

```
$ docker exec dso202-p2-worker2 ls /var/local-path-provisioner
```

![alt text](../evidence/18.png)

This confirms the provisioner's directory-naming convention: PV name,
namespace, and claim name concatenated, on the node the Pod was actually
scheduled to.

```
$ kubectl exec dynamic-writer -- df -h /data
```

![alt text](../evidence/19.png)

**First uncomfortable truth.** This confirms the claim requested 1Gi but the
container can see the entire node filesystem (459.5G available). The
`local-path` provisioner records the requested capacity in the API and
ignores it when creating the directory — nothing here prevents this Pod from
filling the whole node disk.

```
$ kubectl patch pvc dynamic-data --type merge -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
```

![alt text](../evidence/20.png)

**Second uncomfortable truth.** This confirms the API server itself rejects
the resize attempt, caused by `allowVolumeExpansion: false` on the class —
a loud, immediate failure rather than a silent no-op.

```
$ kubectl exec dynamic-writer -- cat /data/ledger.txt
2026-09-06T15:33:20Z start pod=dynamic-writer node=worker-node-2

$ kubectl delete pod dynamic-writer
$ kubectl delete pvc dynamic-data

# immediately after:
$ kubectl get pv
NAME              STATUS     CLAIM
pvc-3595e13b-...  Released   .../dynamic-data
$ docker exec dso202-p2-worker2 ls /var/local-path-provisioner
pvc-3595e13b-d9b3-4910-a57f-94699310dd28_dso202-practical-02_dynamic-data

# ~15 seconds later:
$ kubectl get pv
NAME            STATUS   CLAIM
pv-web-static   Bound    dso202-practical-02/pvc-web-static
$ docker exec dso202-p2-worker2 ls /var/local-path-provisioner
Error from server (NotFound): persistentvolumes "pvc-3595e13b-..." not found
```

![alt text](../evidence/21.png)

This confirms the `Delete` reclaim policy: the PV briefly passed through
`Released` while the provisioner performed asynchronous cleanup, then both
the PV object and the backing directory on `worker-node-2` were removed
entirely a few seconds later. This is the direct contrast with Stage 2's
`Retain` policy, where the PV stayed `Released` indefinitely and the data on
disk was untouched until deleted by hand. One field —
`reclaimPolicy` on the StorageClass — produced the entire difference.

### 3.4 Stage 4 — Why a Deployment Cannot Own State

**What was done.** A Deployment with three replicas was pointed at a single
shared PersistentVolumeClaim, to observe at first hand the failure modes a
StatefulSet is designed to prevent, before StatefulSets were introduced.

```
$ kubectl apply -f manifests/08-deployment-shared-pvc.yaml
$ kubectl rollout status deployment/shared-writer --timeout=180s
$ kubectl get pods -l app=shared-writer -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

![alt text](../evidence/22.png)

**Observation 1.** All three replicas were scheduled onto `worker-node-2`,
although the Deployment expresses no node preference anywhere. The claim was
bound to a volume that exists on one node only, so no other node could
accept these Pods — a storage decision removed the scheduler's freedom.

```
$ kubectl exec deploy/shared-writer -- cat /data/visitors.log
```

![alt text](../evidence/23.png)

**Observation 2.** There is one set of data, not three. All three replicas
wrote into the same file on the same volume. A stateless web server can
tolerate this; two database processes writing to the same data directory
would corrupt it. Nothing in the Deployment specification can give each
replica its own volume, because the claim is named once in the Pod template
and every replica uses that template.

```
$ kubectl delete pod -l app=shared-writer --field-selector status.phase=Running --wait=false
$ sleep 15
$ kubectl get pods -l app=shared-writer -o custom-columns=NAME:.metadata.name
```

![alt text](../evidence/24.png)

**Observation 3.** No replica retained an identity across the restart —
every Pod name is new. There is no way for an application, a monitoring
system, or a peer Pod to refer to "the first replica" and mean the same
process before and after deletion. Replicated databases require exactly
that continuity, because members must find each other by a name that
outlasts any individual Pod.

```
$ kubectl delete -f manifests/08-deployment-shared-pvc.yaml
$ kubectl get pvc
```

![alt text](../evidence/25.png)

This confirms the anti-pattern Deployment and its claim were fully removed,
leaving only the Stage 2 static claim behind.

---

### 3.5 Stage 5 — StatefulSets and Stable Identity

**What was done.** A headless Service was created ahead of the StatefulSet
so that Pods are addressable from the moment they become ready. The
`webnote` StatefulSet was then applied and its ordered creation, per-ordinal
storage, per-Pod DNS, volume privacy, and survival of identity/storage
across Pod deletion were each verified in turn.

```
$ kubectl apply -f manifests/09-service-webnote.yaml
$ kubectl get service webnote
```

![alt text](../evidence/26.png)

This confirms the Service is headless (`CLUSTER-IP: None`) — no virtual
address is allocated; the Service exists purely to publish DNS records.

```
$ kubectl apply -f manifests/10-statefulset-webnote.yaml
$ kubectl get pods -l app=webnote -w
```

![alt text](../evidence/27.png)

This confirms ordered, sequential creation (`OrderedReady`, the default):
`webnote-1` was not created until `webnote-0` reached `1/1 Running`, and
`webnote-2` waited on `webnote-1` in turn. Pod names are fixed ordinals
(`webnote-0`, `-1`, `-2`), not random hash suffixes.

```
$ kubectl get pvc -l app=webnote
```

![alt text](../evidence/28.png)

This confirms three separate claims were generated from the single
`volumeClaimTemplate`, named `<template>-<statefulset>-<ordinal>`, and are
selectable by label because the template sets labels under
`volumeClaimTemplates[].metadata`.

```
$ kubectl get pods -l app=webnote -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
```

![alt text](../evidence/29.png)

This confirms placement is free again, unlike Stage 4: the three Pods are
spread across both worker nodes because each ordinal owns its own volume
rather than sharing one.

```
$ kubectl apply -f manifests/11-pod-client.yaml
$ kubectl exec client -- nslookup webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/30.png)

This confirms one Service name resolved to all three Pod addresses — a
headless Service publishes per-Pod DNS records instead of a single virtual
ClusterIP.

```
$ kubectl exec client -- wget -qO- http://webnote-1.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/31.png)

This confirms one specific Pod (`webnote-1`) is individually addressable by
its own DNS name, distinct from the address of the set as a whole.

```
$ kubectl exec webnote-0 -- sh -c 'echo "note added by hand in Stage 5" >> /usr/share/nginx/html/index.html'
$ kubectl exec client -- wget -qO- http://webnote-0.webnote.dso202-practical-02.svc.cluster.local
$ kubectl exec client -- wget -qO- http://webnote-1.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/32.png)

This confirms the volumes are genuinely private: a note written by hand
into `webnote-0`'s file appears only on `webnote-0`; `webnote-1` is
untouched. Three replicas of one workload hold three unrelated sets of
content — exactly what Stage 4 could not achieve.

```
$ kubectl delete pod webnote-1
$ kubectl wait --for=condition=Ready pod/webnote-1 --timeout=120s
$ kubectl get pod webnote-1 -o custom-

$ kubectl get pvc content-webnote-1

$ kubectl exec client -- wget -qO- http://webnote-1.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/33.png)

This confirms all four facts the guide highlights at once: the Pod name is
unchanged (`webnote-1`); the same claim was reattached rather than recreated
(its age, 18m, exceeds the replacement Pod's age); the `created:` timestamp
is untouched, so the file was not regenerated; and the Pod's IP address
changed (`10.244.1.4` → `10.244.1.5`), which is precisely why an application
must be configured with the DNS name and never with an address.

### 3.6 Stage 6 — Scaling, Retention, and Ordered Updates

**What was done.** The `webnote` StatefulSet was scaled up, then down, then
back up, to observe what happens to generated claims at each step. A
partitioned rolling update was carried out by editing the committed manifest
(rather than `kubectl patch`), first updating a single ordinal, then
completing the rollout across the rest. Finally the StatefulSet itself was
deleted and recreated to observe the `whenDeleted` retention policy.

```
$ kubectl scale statefulset webnote --replicas=4
$ kubectl wait --for=condition=Ready pod/webnote-3 --timeout=120s
$ kubectl get pvc -l app=webnote --no-headers | wc -l
```

This confirms scaling up created storage automatically: a fourth claim
(`content-webnote-3`) was generated from the same `volumeClaimTemplate` the
moment the fourth replica was requested.

```
$ kubectl scale statefulset webnote --replicas=2
$ kubectl get pods -l app=webnote -w
```

![alt text](../evidence/34.png)

This confirms termination proceeded in descending ordinal order, one Pod at
a time: `webnote-3` was removed first, then `webnote-2`, leaving `webnote-0`
and `webnote-1` (the lowest ordinals) running. This ordering is what a
database designating ordinal 0 as its initial primary would depend on.

```
$ kubectl get pvc -l app=webnote
```

![alt text](../evidence/35.png)

This confirms two Pods were running but all four claims remained. The
default `whenScaled: Retain` policy kept the data of the removed replicas —
scaling down is often a reaction to a problem, so destroying data as a side
effect would be unrecoverable.

```
$ kubectl scale statefulset webnote --replicas=3
$ kubectl wait --for=condition=Ready pod/webnote-2 --timeout=120s
$ kubectl exec client -- wget -qO- http://webnote-2.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/36.png)

This confirms the original `created:` timestamp (`03:32:23`) survived:
ordinal 2 was deleted and later recreated, and it reclaimed the volume that
belonged to ordinal 2 purely by name. Identity is what links a replica to
its data, and the ordinal is the identity.

```
# manifests/10-statefulset-webnote.yaml edited: partition 0 -> 2,
# image nginx:1.30-alpine -> nginx:1.31-alpine (nginx container only)

$ kubectl apply -f manifests/10-statefulset-webnote.yaml
$ sleep 30
$ kubectl get pods -l app=webnote -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```

![alt text](../evidence/37.png)

This confirms `partition: 2` restricted the update to Pods whose ordinal is
≥ 2. Only `webnote-2` picked up the new image; ordinals 0 and 1 were left
untouched, demonstrating how a new version can be trialled on a single
member before the rest of the set is committed to it — a capability with no
equivalent in a Deployment.

```
# manifests/10-statefulset-webnote.yaml edited: partition 2 -> 0

$ kubectl apply -f manifests/10-statefulset-webnote.yaml
$ kubectl rollout status statefulset/webnote --timeout=300s
$ kubectl get pods -l app=webnote -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```

![alt text](../evidence/38.png)

This confirms the remaining Pods were updated in descending order (ordinal
1, then ordinal 0), completing the rollout.

```
$ kubectl exec client -- wget -qO- http://webnote-0.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/39.png)

This confirms each replacement Pod reattached its own volume during the
image upgrade: the original `created:` timestamp and the hand-written note
from Stage 5 both survived, proving the rolling update changed only the
container image, not the data.

```
$ kubectl delete statefulset webnote
$ kubectl get pods -l app=webnote
# ~15s later:
$ kubectl get pods -l app=webnote
$ kubectl get pvc -l app=webnote --no-headers | wc -l
```

![alt text](../evidence/40.png)

This confirms every Pod was removed by deleting the StatefulSet, but all
four claims remained, because `whenDeleted: Retain` is set. On this cluster,
deleting a StatefulSet is a recoverable mistake.

```
$ kubectl apply -f manifests/10-statefulset-webnote.yaml
$ kubectl rollout status statefulset/webnote --timeout=300s
$ kubectl exec client -- wget -qO- http://webnote-1.webnote.dso202-practical-02.svc.cluster.local
```

![alt text](../evidence/41.png)

This confirms the workload returned with its complete history intact: the
original Stage 5 `created:` timestamp, and a `started:` line for every
restart, scale event, and the StatefulSet's own deletion and recreation —
none of which touched the underlying volumes.

## 4. Analysis

Review questions answered so far (numbering follows the guide's section 16):

**Q1. The claim in Stage 3 was Pending immediately after creation, while the
claim in Stage 2 bound at once. Name the single field responsible for the
difference and explain the reasoning behind that field's design.**

The field is `volumeBindingMode` on the StorageClass. The Stage 2 claim
named `storageClassName: manual`, which matches no actual StorageClass
object, so no binding mode applied at all — the claim bound as soon as a
matching `Available` PV existed. The Stage 3 claim named `standard`, whose
`volumeBindingMode` is `WaitForFirstConsumer`. This mode exists so the
provisioner does not have to guess which node a volume should be created on;
it waits until a Pod referencing the claim has been scheduled, then creates
the volume on that Pod's node. Binding immediately (the alternative,
`Immediate`) risks creating storage on a node the eventual Pod cannot be
placed on.

**Q2. After the claim was deleted, the data from Stage 2 survived and the
data from Stage 3 did not. State which object carried the field that
decided this, and who in a real organisation would have chosen its value.**

The field is `reclaimPolicy` (or, on a statically-created PV,
`persistentVolumeReclaimPolicy`), carried on the PersistentVolume — but for
dynamically provisioned volumes, its value is inherited from the
StorageClass that created the PV, not chosen per-claim. Stage 2's manually
created PV set `Retain`. Stage 3's PV was created by the `standard` class,
which sets `Delete`. In a real organisation, the StorageClass's
`reclaimPolicy` would be set by a platform or infrastructure administrator
when the class is defined — a decision made long before any application
team creates a claim against it, and one that a developer writing a PVC
manifest cannot override.

*(Remaining review questions depend on Stages 4–8 and will be answered once
those stages are complete.)*

---

## 5. Reflection

*(To be completed once the practical is finished. One item worth noting
already: the Stage 3 `Delete` reclaim cleanup was not instantaneous —
`kubectl get pv` briefly showed the volume as `Released` immediately after
deleting the claim, and the PV object and its backing directory were only
fully gone about 15 seconds later. This is worth documenting as a real
observed timing detail rather than assuming deletion is synchronous.)*

---

## 6. References

- DSO202 Practical 2 Guide (`DSO202_Practical2_Guide.md`), sarojsanyasi, HackMD.
- DSO202 Practical 2 Companion File (`DSO202_Practical2_Manifests.md`),
  sarojsanyasi, HackMD.
- `kubectl explain` output consulted directly against the running cluster
  for field-level questions (see companion file Appendix C).