# HPA added replicas, and the database started refusing (theme 32)

One induced failure on the `dev` stand: a pool of 25 connections per replica with no
overflow, HPA with a ceiling of 4 replicas. The main lesson: **HPA counts only the pods'
CPU and knows nothing about the database.** Every new replica brings its own pool, so the
replica ceiling is also a ceiling on connections to Postgres. If it is not calculated,
extra replicas do not speed the service up — they break it.

## The rule

```
maxReplicas × (pool_size + max_overflow)  ≤  available to pods
```

"Available to pods" is not `max_connections`, but what remains after the reserves and the
other clients. Measured on `dev` (db.t3.micro, PG16), 2026-09-27:

```
81  max_connections = LEAST(DBInstanceClassMemory / 9531392, 5000)
−3  superuser_reserved_connections   empty slots, superuser only
−2  reserved_connections             empty slots, rds_reserved role only (since PG16)
−3  rdsadmin                         occupied: the AWS service user
−1  migration (PreSync hook)
−1  psql during diagnosis
= 71 for pods;  4 × (5 + 10) = 60;  margin 11
```

The reserves are empty slots that the `app` user will simply not be given. Only the
`rdsadmin` connections are really occupied. The number is written next to `autoscaling`
in `values-dev.yaml`.

## What happened

| what | expected | observed |
|---|---|---|
| HPA under `hey -c150` | 1 → 4 in one step | 1 → 4 at once: utilization 1288 % against a 70 % target; the formula wanted ⌈1 × 1288 / 70⌉ = 19 and hit `maxReplicas` |
| who forms the refusal | the database, 500 in the application logs | exactly so, see the chain below |
| `app` connections in `pg_stat_activity` | hit the limit | ≈ 72: 1 `active`, 66–68 `idle`, 3–5 `idle in transaction` |
| client (`hey`, 5 minutes) | a noticeable share of 500s | 297 810 × 200, 501 × 500 (**0.17 %**), p95 0.40 s, slowest 3.94 s |
| alerts | `HighErrorRate`, maybe `SlowResponses` | **none** |

### The chain of one failed request

```
hey → uvicorn/FastAPI → SQLAlchemy pool: own connections busy, pool < 25 → open a new one
    → psycopg → RDS :5432 → FATAL                                   ← the DATABASE forms the refusal
    → psycopg.OperationalError → sqlalchemy.exc.OperationalError
    → the endpoint does not catch it → Starlette ServerErrorMiddleware → 500   ← the APPLICATION forms the code
```

The database refused with three messages — three levels of slot exhaustion:

- `sorry, too many clients already` — all slots are gone;
- `remaining connection slots are reserved for roles with the SUPERUSER attribute`;
- `remaining connection slots are reserved for roles with privileges of the "rds_reserved" role`.

Each one comes with a `no pg_hba.conf entry … no encryption` line. That is not a second
problem: libpq runs in `sslmode=prefer` by default and retries without TLS after a
refusal, while RDS with `rds.force_ssl=1` only accepts TLS. The cause is the first
message; the second is a trace of the retry.

### Why so few refusals with so many connections

- `idle` means the connection is open and **holds a slot** in the database; nothing is
  running on it at the moment. It is free for its own pod, not for another one: each
  replica has its own pool.
- SQLAlchemy never closes the permanent part of the pool (`pool_size`). Every replica
  tried to grow to 25: 4 × 25 = 100 against 71 available. Only requests that needed a
  **new** connection after the slots ran out were refused. The rest went through
  connections that were already open — hence 0.17 %.
- After the load the connections stay open: the budget is taken even at rest.
- `idle in transaction` means a `Session` started a transaction and holds the connection
  until the end of the request. There is almost no `active` in a snapshot because the SQL
  itself takes milliseconds.

## What monitoring sees

| rule | threshold | observed |
|---|---|---|
| `HighErrorRate` | more than 5 % of 5xx for 5 minutes | 0.17 % |
| `SlowResponses` | p95 above 1 s for 10 minutes | 0.40 s |

By its own thresholds the monitoring is right: the user barely noticed the failure. But
the budget rule was broken, and **no signal sees that** — nobody compares the number of
connections with what is available. Raising `maxReplicas` or the pool in `values` goes
unnoticed until the 500s start. What is needed is a check on the cause (for example, RDS
`DatabaseConnections` against 71), not on the symptom. **Not done; the gap is open.**

## How it was broken and what did not go to plan

- At first HPA did not get a single number: `v1beta1.metrics.k8s.io` sat in
  `FailedDiscoveryCheck`. The metrics-server add-on listens on 10251, the EKS module does
  not open that port on the node group, and packets from the apiserver were dropped
  silently. Fixed with a rule in `infra/eks.tf` (`4cd2359`).
- The logs of the first run were lost: 5 minutes after the load HPA removed the extra
  replicas, and a pod's logs go away with the pod. The load was repeated for 2 minutes,
  and a loop caught the errors into a file while the pods were alive.
- In the first budget calculation the tutor missed `reserved_connections = 2` and got 73.
  It surfaced through the `rds_reserved` error text during the break. Recalculated: 71,
  and the ceiling of 4 still fits.

## What changed in the system

- metrics-server as an EKS add-on (`06e85ca`), port 10251 open from the control plane to
  the nodes (`4cd2359`).
- Application: the connection pool sizes are read from the environment — `DB_POOL_SIZE`,
  `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT`, defaults 5 / 10 / 30 (`06e85ca`).
- Chart: an HPA template (`autoscaling/v2`, CPU target relative to `requests`), the pool
  from `values` (gitops `eb68d48`). In `dev` HPA is on: 1–4 replicas, target 70 %
  (`9daa3ce`).
- `replicas` is handed over to HPA: `app-dev` got `ignoreDifferences` on `/spec/replicas`
  and `RespectIgnoreDifferences=true`. Otherwise ArgoCD with `selfHeal` would restore the
  number from git and fight HPA over the field. Decided up front during the design step;
  the fight itself was not reproduced.
- The failure: pool 25 + 0 (`f959a14`), reverted (`26cf192`). After the revert there were
  3 `app` connections.
