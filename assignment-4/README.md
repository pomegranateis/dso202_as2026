# DSO202 — Assignment 4: GitOps Delivery of the Task Tracker with Argo CD

The assignment brief requires the work to live in its own public repository, `dso202-gitops`. This folder only
points to it, so that all four assignments can be found from this repository.

| | |
| --- | --- |
| **Repository** | <https://github.com/pomegranateis/dso202-gitops> |
| **Write-up** | [README](https://github.com/pomegranateis/dso202-gitops#readme): purpose, pinned versions, build sequence, credentials, deviations, screenshots, answers Q1–Q6 |
| **Evidence** | [docs/evidence.md](https://github.com/pomegranateis/dso202-gitops/blob/main/docs/evidence.md): command output for Tasks 1–10 |
| **Release tags** | `v1.0.0`, `v1.1.0`, `v1.2.0` |
| **Pull requests** | [#1–#6](https://github.com/pomegranateis/dso202-gitops/pulls?q=is%3Apr) (Task 7) |
| **`main` when this page was written** | `7ac5212` |

## What was built

Argo CD v3.5.6 runs in a kind cluster (`dso202-gitops`) and delivers the Task Tracker from Git to two
environments: `dev` follows `main` with automated sync, prune and self-heal; `staging` follows a release tag and is
synchronised by hand. An app-of-apps root Application creates every other Application, two AppProjects separate the
administrator-level platform layer from the least-privilege workload project, database credentials are committed
only as SealedSecrets, and the whole environment was rebuilt from the repository and one backed-up key in about
three minutes.

| Task | Result |
| --- | --- |
| 1 | Repository in the required layout; Assignment 3 chart adjusted to the chart contract C1–C11 |
| 2 | Argo CD installed from a pinned Kustomize overlay; seven Pods running |
| 3 | `platform` and `dso202` AppProjects; root Application created `dso202` |
| 4 | Sealed Secrets through Git; credentials sealed per environment; no plaintext in history |
| 5 | Waves database → backend → frontend, PostSync smoke test, CRUD in dev, staging synced by hand |
| 6 | Read-only `reviewer` account; log access granted by one commit |
| 7 | Release promoted through the tag gate; faulty release diagnosed, rollback refused, `git revert`, fix-forward |
| 8 | Four drills (self-heal, reported drift, pruning, project guardrail), each predicted before running |
| 9 | Cluster deleted and rebuilt from Git and the sealing key: 3 min 18 s to a working dev frontend |
| 10 | Bonus: `tasktracker-dev` as a two-source Application |

## Deviations (details in the repository README)

- The `1.1` release images were never issued, so Task 7 used the issued `1.0` images (from my own Docker Hub
  account, `pomegranatei/dso202-*`) and made each release a values change, with a deliberately injected and declared
  fault for the failing release.
- `ReplicaSet` and `Pod` were added to the workload project's whitelist so that Argo CD shows Pods and their logs.
- The smoke test uses the Assignment 2 LimitRange minimum (`50m`/`64Mi`) instead of Listing 13's lower values.

## Screenshots

Shown from the `dso202-gitops` repository ([`docs/screenshots/`](https://github.com/pomegranateis/dso202-gitops/tree/main/docs/screenshots)); each one is
also placed next to its command output in [docs/evidence.md](https://github.com/pomegranateis/dso202-gitops/blob/main/docs/evidence.md).

**Task 2 — Argo CD v3.5.6 after admin sign-in:** all six Applications `Healthy` and `Synced`.

![Argo CD after admin sign-in](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-1-argocd-signed-in.jpg)

**Task 3 — the root Application's resource tree:** five child Applications and the `dso202` AppProject, created
by the root from Git.

![Root Application resource tree](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-2-root-tree.jpg)

**Task 5 — the `tasktracker-dev` resource tree:** ConfigMaps, Services, Deployments with their ReplicaSets and Pods,
the database StatefulSet and its Pod, and the PostSync smoke-test Job.

![tasktracker-dev resource tree](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-3-tasktracker-dev-tree.jpg)

**Task 6 — the read-only `reviewer` account reading Pod logs**, its User Info, and its Applications page (only the
two `dso202` Applications are visible):

![reviewer reading the backend Pod's logs](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-4-reviewer-logs.jpg)

![User Info: reviewer](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-4b-reviewer-user-info.jpg)

![reviewer's Applications page](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-4c-reviewer-applications.jpg)

**Task 5 — the application in both environments:** dev at `http://localhost:30080` and staging at
`http://localhost:8081`, each reporting `BACKEND + DB ONLINE`.

![Dev UI](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-5-dev-ui.jpg)

![Staging UI](https://raw.githubusercontent.com/pomegranateis/dso202-gitops/main/docs/screenshots/a4-6-staging-ui.jpg)