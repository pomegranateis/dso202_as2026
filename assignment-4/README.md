# DSO202 — Assignment 4 (DRAFT, work in progress)

> **Status:** started, not finished. The official brief, including the required **Image 1.1**, could not be found (it is not in this repository, and a search of the shared DSO202 Drive files and email found nothing). This draft assumes Assignment 4 continues from Practical 4 (GitOps with Argo CD) and Assignment 3. **Once the brief and Image 1.1 are found, check this assumption first** and update Section 1.

**Assumed brief:** deliver the Task Tracker from Assignments 1 and 3 by GitOps, with Argo CD keeping the cluster in line with this Git repository.
**Tools:** Argo CD, Helm chart from Assignment 3 (`assignment-3/helm/tasktracker`, unchanged)
**Cluster:** `kind` (`dso202`: 1 control-plane node, 2 worker nodes), the same cluster used in Assignments 2 and 3 and Practical 4

---

## 1. Brief and Image 1.1

| Item | Status |
| --- | --- |
| Assignment 4 brief | **Missing**: to be copied here word for word |
| Image 1.1 (required by the brief) | **Missing**: ask the tutor or classmates; save it as `evidence/image-1.1.png` |
| Assumed topic (GitOps / Argo CD) | To confirm against the brief |

---

## 2. What Changes from Assignment 3

| Area | Assignment 3 | Assignment 4 (planned) |
| --- | --- | --- |
| Who applies changes | Me, with `kubectl apply -k` / `helm install` | Argo CD, from the `main` branch of this repository |
| Source of truth | My terminal and local files | Git: a commit is the only way to change the cluster |
| Drift (manual `kubectl edit`) | Stays until noticed | dev: reverted automatically (`selfHeal`); prod: shown as `OutOfSync` |
| Deleted resources | Left behind unless removed by hand | dev: removed (`prune`) |
| Promotion dev → prod | Second `helm install` | Automatic sync for dev, manual `argocd app sync` for prod |
| Access control | `default` project | Dedicated `AppProject` limited to this repo and two namespaces |

---

## 3. Repository Structure

```
assignment-4/
├── README.md
├── argocd/
│   ├── project.yaml     # AppProject "tasktracker": allowed repo + destinations
│   ├── app-dev.yaml     # Application: chart + environments/dev.yaml, automated sync
│   └── app-prod.yaml    # Application: chart + environments/prod.yaml, manual sync
└── evidence/            # screenshots a4-1 … (to be added), and image-1.1.png
```

The Applications point at `assignment-3/helm/tasktracker` with `../environments/<env>.yaml`, so the chart is reused, not copied.

---

## 4. Environments

| Setting | dev | prod |
| --- | --- | --- |
| Argo CD Application | `tasktracker-dev` | `tasktracker-prod` |
| Namespace | `tasktracker-gitops-dev` | `tasktracker-gitops-prod` |
| Values file | `assignment-3/helm/environments/dev.yaml` | `assignment-3/helm/environments/prod.yaml` |
| Sync | Automated (`prune`, `selfHeal`) | Manual |
| Ingress host | `dev.tasktracker.local` | `prod.tasktracker.local` |

**Note:** the values files reuse the Assignment 3 NodePorts (30180 / 30280) and Ingress hosts, so the Assignment 3 Helm and Kustomize installs must be removed first (`helm uninstall …`, `kubectl delete -k …`), or the Services will clash.

---

## 5. Planned Steps

1. Check the cluster and that Argo CD from Practical 4 is still running: `kubectl get pods -n argocd`.
2. Remove the Assignment 3 releases (see note in Section 4).
3. Apply the project and Applications:
   ```bash
   kubectl apply -f argocd/project.yaml
   kubectl apply -f argocd/app-dev.yaml -f argocd/app-prod.yaml
   ```
4. Give the database password without committing it (the chart's `required` check stops the render until this is done):
   ```bash
   argocd app set tasktracker-dev  -p credentials.password='<password>'
   argocd app set tasktracker-prod -p credentials.password='<password>'
   ```
   A better option to look at later: Sealed Secrets or External Secrets, so the Secret itself can live in Git encrypted.
5. Wait for dev to show `Synced` / `Healthy`, then open `http://dev.tasktracker.local:8081`.
6. **GitOps demo:** change `frontend.replicaCount` in `environments/dev.yaml`, commit, push, and watch Argo CD roll it out.
7. **Self-heal demo:** `kubectl scale deploy/frontend-deployment -n tasktracker-gitops-dev --replicas=3` and watch Argo CD put it back.
8. **Rollback demo:** `argocd app history` / `git revert` of the change from step 6.
9. Sync prod by hand: `argocd app sync tasktracker-prod`.
10. Take screenshots for every step into `evidence/` and fill in Section 6.

---

## 6. Evidence

_To be added after the steps in Section 5 are run._

| # | Shows | File |
| --- | --- | --- |
| 1.1 | Image required by the brief | `evidence/image-1.1.png` (missing) |
| a4-1 | Argo CD UI: both Applications | — |
| a4-2 | dev `Synced` / `Healthy` | — |
| a4-3 | Commit → automatic rollout | — |
| a4-4 | Self-heal reverting a manual change | — |
| a4-5 | Rollback | — |
| a4-6 | prod manual sync | — |

---

## 7. To Do

- [ ] Find the Assignment 4 brief and Image 1.1; confirm or correct the assumed topic
- [ ] Run the steps in Section 5 on the kind cluster
- [ ] Add screenshots and write up results
- [ ] Decide on secret handling (manual parameter vs Sealed Secrets)
