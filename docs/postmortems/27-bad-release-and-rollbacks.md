# A broken release reaches prod with every indicator green, and GitOps undoes the emergency rollback (theme 27)

A deliberately broken release went through the whole delivery path: CI, dev, a merge
request into `values-prod.yaml`, and prod. Then it was rolled back in two ways. The
canonical rollback (a `git revert`) worked. The emergency rollback
(`argocd app rollback`) was first refused. Once forced through, it was silently undone
within minutes by the parent Application.

| phase | what happened | prod state |
|---|---|---|
| 1 | release `8b8187e` merged into prod via MR (`494837f`) | broken |
| 2 | load measured | broken, ArgoCD `Synced / Healthy` |
| 3 | canonical rollback: `git revert` of the merge (`68822f9`) | healthy; recovery **not measured** |
| 4 | broken version reapplied (`c8c7080`), then `argocd app rollback` | healthy for minutes, then broken again |
| end | `git revert` of the reapply (`fae97b4`) in gitops, the app commit reverted (`c095048`) | healthy |

---

- **Symptom:** in prod, `/talks` returns 500 on a large share of requests. Pods are
  `Running`, both probes pass, and ArgoCD shows `app-prod  Synced  Healthy` the whole
  time.

- **Signal:** load through the ALB, 20 concurrent clients:

  ```
  /talks, 60 s                       /health, 30 s
  [200]    5612 responses            [200]    5719 responses
  [500]    5521 responses            [502]      44 responses
  [502]      87 responses
  ```

  `/health` is almost clean while `/talks` fails on half the requests. The failure lives
  in one handler, below everything that watches the service.

- **Cause:** the release sorted talks with `select(Talk).order_by(Talk.tittle)`, while the
  model field is `title`.
  - *Seen in the code:* the typo. *Not captured:* the exception text. By the code it has
    to be an attribute error on the model class, raised inside the handler and turned into
    a 500 by the framework.
  - **Every gate passed:**
    - the linter does not check attribute names on SQLAlchemy models;
    - the application starts, because the query only runs inside the handler;
    - the probes stay green, because `/health` and `/ready` never touch `/talks`;
    - ArgoCD reports sync and health of Kubernetes objects, not of requests.

    The CI `test` stage was, and still is, a placeholder (`echo "pytest"`). Nothing in
    the pipeline ever executed the handler.
  - *Inferred (by the tutor):* the near-exact 50/50 split. The error is deterministic and
    prod ran two replicas, so half the traffic means the 60-second measurement overlapped
    an unfinished rollout: one old pod and one new. The rollout was about a minute long
    because of the graceful shutdown budget from theme 26.
  - *Not analysed:* the 502s on both endpoints during the rollout. Theme 26 measured zero
    502s after the graceful shutdown fix, so these are an open question.

- **Rollback 1, canonical: `git revert` of the merge commit.** ArgoCD synced prod back to
  the previous tag. The truth stayed in git: the cluster matched the repository before and
  after.
  - **Not measured.** The load test meant for this phase was started only after the broken
    version had been reapplied for phase 4. So the numbers from it (`1350 × 200`,
    `9076 × 500`, `214 × 502`) describe the broken state, not the recovery. The mismatch
    surfaced only when the gitops history (`Merge → Revert → Reapply`) was checked against
    the numbers.

- **Rollback 2, emergency: `argocd app rollback`.**
  1. Refused on entry:
     ```
     rpc error: code = FailedPrecondition desc = rollback cannot be initiated when auto-sync is enabled
     ```
     This is a guard, not a failure. A rollback creates a cluster state that git does not
     contain, and automated sync exists to remove exactly such states.
  2. After `argocd app set app-prod --sync-policy none` the rollback ran. The cluster went
     to the healthy revision, and ArgoCD reported the drift honestly:
     ```
     Sync Policy:        Manual
     Sync Status:        OutOfSync from main (c8c7080)
     ```
  3. Minutes later, the repeated check of the policy showed the field coming back:
     ```
     {"syncOptions":["CreateNamespace=true"]}
     {"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}
     ```
     `app-prod` is itself a resource of the `root` Application, and `apps/app-prod.yaml`
     in git says `automated`. `root` has `selfHeal`, so the manual edit was ordinary drift.
     `root` restored it, `app-prod` resynced to `c8c7080`, and prod was broken again while
     showing `Synced / Healthy`.

  The emergency path is unavailable in this configuration by design. ADR 27 chose
  "prod changes only through a merge request" and accepted this cost before the drill.
  The drill showed the cost is total, not partial: whether automated sync is on is also
  written in git.

- **Fix:** revert of the reapply in gitops (`fae97b4`), and revert of the broken commit
  in the application repository (`c095048`). Recovery after the final revert was not
  measured under load; the git history is the record.

- **How we verified:** the protection and the parent's self-heal were observed directly
  (`FailedPrecondition`, the drift status, the `syncPolicy` field returning). The recovery
  of the canonical rollback was **not** verified by measurement.

- **Prevention:**
  - **A real test stage.** A test that calls `/talks` against a database (a TestClient
    with a Postgres service in CI) would have failed this build before any image was
    pushed. It is the cheapest gate, and it is missing.
  - **A promotion gate based on dev evidence.** Dev broke first, as a canary should, and
    nothing stopped the manual promotion. A post-deploy smoke test of the real endpoints
    in dev, required by the `promote` job, turns "dev is broken" into "promotion is
    blocked".
  - **Symptom alerts.** `HighErrorRate` (more than 5 % of 5xx for 5 minutes) was added in
    theme 29, after this incident. At about 50 % errors it would have fired.
  - **An emergency runbook that matches the GitOps shape.** In an app-of-apps setup the
    fastest safe rollback is still a revert merged into git. A bypass has to stop the
    parent too, and then it has to be closed with a commit, or it will be undone.
  - **Keep the rollback target alive.** The healthy image prod returned to in this
    incident, `348ffe4`, is gone from ECR today (checked 2026-09-28): the lifecycle policy
    keeps the last four images of any tag, and dev builds evicted it. The same rollback
    now would end in `ImagePullBackOff`. Promoted images need a retention rule of their
    own.

- **Where else this lives:** any release whose failure is in request handling rather
  than in startup: a wrong query, a missing column after a contract migration (theme 22),
  an expired credential to a third-party API. Pods, probes and the GitOps controller all
  report healthy, because none of them sends a real request. Only a test that executes
  the handler, or an alert on request outcomes, sees it.
