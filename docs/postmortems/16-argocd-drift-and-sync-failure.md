# Drift and a failed sync: the three axes of ArgoCD state

## Failure A — a manual change in the cluster (drift)

- **Symptom:** `kubectl -n dev scale deployment talk-booking --replicas=5` while git says
  `replicaCount: 1`. With selfHeal on, the extra pods live for seconds and disappear.
  With it off, they stay, and the application sits OutOfSync.
- **Signal:** `kubectl get applications -n argocd` → `OutOfSync / Progressing`; the DIFF
  tab shows `replicas: 5` (live) against `replicas: 1` (desired).
- **Cause:** the desired state lives in git, not in the cluster. The controller
  continuously compares the rendered chart with the live objects. A manual change is a
  divergence, not a new intent.
- **Fix:** a durable change goes in as a commit to the gitops repository. `kubectl` only
  fixes things for a temporary window.
- **Prevention:** selfHeal is on in dev. It matters to understand the cost of turning it
  off: a manual change is not reverted right away, but the next unrelated sync (a tag
  bump from CI, someone else's commit) will silently wipe it. The failure then arrives at
  an unpredictable moment.

## Failure B — a schema-invalid manifest in git

- **Symptom:** `replicaCount: "too much, observe break"` committed to `values-dev.yaml`.
  The application keeps serving traffic.
- **Signal:** the three axes diverged at the same time — SYNC `OutOfSync`, HEALTH
  `Healthy`, OPERATION `SyncError`:
  `error when patching ...: Invalid value: "": unrecognized type: int32`,
  `Retrying attempt #4`, then `retried 5 times`.
  The RESULT table shows the sync was partial: `v1/Service` → Synced,
  `apps/v1/Deployment` → SyncFailed.
- **Cause:** Helm does not check types and rendered a string. The patch was rejected by
  **kube-apiserver** during schema validation (`replicas` is declared int32). ArgoCD is a
  client here, not a gatekeeper. The live Deployment did not change, so the old
  ReplicaSet and its pods kept running.
- **Fix:** `git revert` of the breaking commit; the next loop turn brought back Synced.
- **Prevention:** tell two classes of bad manifests apart. A schema-invalid one is
  rejected at the API door: the change never lands, and the failure is safe. A **valid
  but semantically wrong** one (a nonexistent image tag, `replicaCount: 0`) is accepted
  by the apiserver, ArgoCD reports Synced, and health falls apart afterwards. `Synced`
  means "the cluster matches git", not "the configuration is right". Review of the merge
  request protects from a bad decision, GitOps does not.
