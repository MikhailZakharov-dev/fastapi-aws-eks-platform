# The app cannot reach RDS, and for two minutes nothing says so (theme 20)

One security group rule was removed on purpose: the only ingress rule on the RDS
security group. The pod kept showing `1/1 Running` for more than two minutes before it
crashed, and every cycle repeated the same wait. The diagnosis was done layer by layer
from inside the cluster, without touching the configuration.

| layer | test (from a pod in the same namespace) | result | conclusion |
|---|---|---|---|
| name | `dig +short $HOST` | `10.0.2.42` | DNS works, the name resolves to a private address |
| route / filter | `time nc -zv $HOST 5432` | `Operation timed out`, `real 2m10.915s` | the packet is dropped silently; a timeout cannot tell a route from a filter |
| listener | — | not reached | unknown: the request never got that far |

---

- **Symptom:** after a restart the pod stays `1/1 Running` for about 2m15s, then goes to
  `Error` and `CrashLoopBackOff`. Every restart repeats the two-minute wait.

  ```
  talk-booking-7f8549c64f-bnr6z   1/1     Running             0               12s
  talk-booking-7f8549c64f-bnr6z   0/1     Error               0               2m17s
  talk-booking-7f8549c64f-bnr6z   1/1     Running             1 (1s ago)      2m18s
  talk-booking-7f8549c64f-bnr6z   0/1     Error               1 (2m15s ago)   4m32s
  talk-booking-7f8549c64f-bnr6z   0/1     CrashLoopBackOff    1 (13s ago)     4m44s
  ```

- **Signal:** the log of the crashed container (`kubectl logs --previous`):

  ```
  sqlalchemy.exc.OperationalError: (psycopg.errors.ConnectionTimeout) connection timeout expired
  ERROR:    Application startup failed. Exiting.
  ```

  Plus the two tests in the table above, run from a `netshoot` pod in the same namespace,
  so the source matches the application's.

- **Cause:** the rule `aws_vpc_security_group_ingress_rule.rds_from_nodes` was destroyed
  with `terraform destroy -target`. The RDS security group had no ingress left, so the
  SYN from the pod was dropped at the database's network interface without a reply.

  - *Seen in the output:* the name resolves, the TCP connect times out, the application
    fails on a connection timeout during startup.
  - *Inferred:* a filter, not a route. The signal alone cannot tell the two apart. Both
    produce silence. Only the drill setup (we removed the rule ourselves) settles it.
    Without that knowledge, the next step would be Reachability Analyzer (static path
    check) or VPC Flow Logs (a `REJECT` on the inbound flow at the database's interface).
    Neither was run.
  - *Why two minutes:* the application sets no `connect_timeout`, so psycopg uses its
    built-in default of 130 seconds (`_DEFAULT_CONNECT_TIMEOUT` in psycopg 3.3). `nc` was
    bounded separately by the kernel's SYN retransmissions, which also add up to about
    two minutes. Had nobody been listening on the port, the host would have answered
    `connection refused` immediately. The duration itself is part of the signal.
  - *Why `Running`:* the chart had no probes at the time. Without them Kubernetes marks a
    container ready as soon as the process starts. `Running` meant "the process exists",
    while the process spent its whole life blocked in the startup connection check.

- **Fix:** `terraform apply` restored the rule, and the pod was restarted.

- **How we verified:** the restore commands were run at the end of the session. An
  explicit capture of the pod reaching `1/1 Running` after the restore is **not in the
  records**, because the session ended with a teardown. Indirect evidence: every later
  stand with the same rule starts, and the startup connection check passes (theme 21
  onwards).

- **Prevention:**
  - **Set an explicit, short `connect_timeout`.** Failing in seconds instead of two
    minutes keeps the timeout-versus-refused signal readable and shortens every
    crash loop. Not done yet.
  - **Probes** make `Running` stop lying: a readiness check that queries the database was
    added in theme 25.
  - **The rule references the node security group, not the subnet CIDRs.** It describes
    *what* the source is, not *where* it lives, so a new AZ or an unrelated resource in
    the same subnets does not change it. The known gap: any pod in the cluster can reach
    the database. Narrowing that needs NetworkPolicy or security groups for pods (theme
    33, deferred).
  - **Fail loudly at startup.** The application checks the connection during startup and
    exits, which turns a broken dependency into a visible `CrashLoopBackOff` instead of a
    500 on every request.

- **Where else this lives:** every hop guarded by a security group fails the same way.
  - The ALB → pod hop: the node security group must admit the load balancer's group
    (theme 23).
  - metrics-server in theme 32: the control plane could not reach port 10251 on the
    nodes, and the API service sat in `FailedDiscoveryCheck` with a healthy pod behind a
    closed door.
  - Any managed service in private subnets (ElastiCache, OpenSearch): there is no shell
    on the far side, so the checklist ends at `nc` and the cloud's own tools.

## Also found in the same session

The first rollout of the database-enabled image crashed with
`ModuleNotFoundError: No module named 'sqlalchemy'`. The Dockerfile used
`uv sync --frozen`, which installs exactly what is in `uv.lock` **without checking it
against `pyproject.toml`**. A dependency added to `pyproject.toml` without re-locking
produced a green pipeline and an image without the library. Fixed by `--locked`, which
fails the build when the lock drifts (`0b456f3`). This is a common class: a tool that
succeeds while doing less than the user assumes.
