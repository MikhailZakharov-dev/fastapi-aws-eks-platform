# A contract migration under live old code: green indicators, dead service

- **Symptom:** the endpoint returns 500 on every request. Meanwhile the pod is
  `1/1 Running`, the restart counter does not grow, and the ArgoCD Application is
  `Synced/Healthy`.

- **Signal:** before and after the migration, with no change to the pod at all:

  ```
  BEFORE  GET /talks → 200
  AFTER   GET /talks → 500
  log     sqlalchemy.exc.ProgrammingError:
          (psycopg.errors.UndefinedColumn) column talks.speaker does not exist
  ```

- **Cause:** the migration dropped a column that the running code still queries. The
  schema moved forward, the code stayed in yesterday's world. In a real deployment this
  happens in the rolling-update window, when both versions of the code are alive at once
  and there is one schema for all of them: it has to fit both the new version and the
  previous one.

- **Why monitoring does not catch it:** the application started long ago, the startup
  connection check passed, the process is alive. Neither liveness nor readiness can tell
  this state apart — only requests to the changed table fail. ArgoCD is satisfied too:
  every object matches git, and the database schema is not part of the desired state at
  all. The service is down with every indicator green.

- **Fix — expand/contract, three steps:**
  1. **expand**: add the new thing without touching the old (a nullable column or one
     with a default). The schema is compatible with both versions of the code.
  2. **deploy the code**: the new version writes to both fields and reads the new one.
     Wait until the rollout has fully finished and no old pods remain.
  3. **contract**: drop the old thing, tighten the constraints. As a separate
     deployment, later.

  A one-time data copy in step 1 is not enough: while the window lasts, old pods write
  only to the old column. Either the new code writes to both fields, or the copy is
  repeated before the contract step — otherwise `NOT NULL` in step 3 fails.

- **What this really buys:** the ability to roll back the code. The schema does not roll
  back — `DROP COLUMN` took the data with it, and no reverse migration exists for it. As
  long as the schema is compatible with both versions, a rollback is a change of the
  image tag. A contract done too early leaves you where going forward is scary and going
  back is impossible.

- **Prevention:** treat schema changes as two different classes of operations. Additive
  ones are safe and ship together with the code. Subtractive ones need a separate
  deployment after the previous version of the code is guaranteed to be gone. Migration
  autogeneration does not help here: it reads a column rename as a drop plus an add,
  which means it proposes a contract step in its most dangerous form.
