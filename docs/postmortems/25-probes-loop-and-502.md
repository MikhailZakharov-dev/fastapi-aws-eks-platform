# Probes: a restart loop of a healthy application and a 502 window during rollout (theme 25)

Two different failures with a common root: `Ready` is the single signal on which three
independent decisions are made in the cluster, and both times that signal was corrupted.

---

## Failure 1 — liveness kills a working application

- **Symptom:** the pod restarts in a loop, `CrashLoopBackOff`, the restart counter grows.
  The application logs contain **not a single error**.

- **Signal:**

  ```
  $ kubectl -n dev get pods
  NAME                            READY   STATUS             RESTARTS
  talk-booking-85c445f748-pzlnv   0/1     CrashLoopBackOff   4 (26s ago)

  $ kubectl -n dev describe pod talk-booking-85c445f748-pzlnv
  Warning  Unhealthy  kubelet  Liveness probe failed: Get "http://10.0.1.103:8000/health":
                               dial tcp 10.0.1.103:8000: connect: connection refused
  Normal   Killing    kubelet  Container app failed liveness probe, will be restarted

  $ kubectl -n dev logs talk-booking-85c445f748-pzlnv --previous
  (a normal startup, no errors)
  ```

- **Cause:** the application needs a few seconds to open its port: `lifespan` checks the
  database connection before the server starts listening. A liveness probe without a
  startup probe in front of it polls the container almost immediately after start and
  gets `connection refused`. With `failureThreshold: 1` the first failure is terminal —
  kubelet kills the container, it starts again, and never lives long enough to open the
  port.

  `connection refused` matters here as a **signal class**: it is not an expired wait but
  an instant refusal from the kernel — nobody is listening on the port. `timeoutSeconds`
  plays no part in this scenario at all, although it looks like the culprit.

- **Fix:** a startup probe covers the whole boot period; liveness has no
  `initialDelaySeconds`, and its thresholds stay strict.

- **Prevention:** a clean `logs --previous` with a growing `restartCount` is the
  signature of an **external killer**: the application did not crash, it was stopped. In
  that case the cause is always in `describe` → Events, not in the logs.

  A rule for tuning: `failureThreshold × periodSeconds` is a time budget, not a number of
  attempts. The startup probe budget is checked by measurement, not by estimate:

  ```
  kubectl -n dev get pod -l app=talk-booking -o jsonpath='{range .items[0].status.conditions[*]}{.type}{"  "}{.lastTransitionTime}{"\n"}{end}'
  ```

  The difference between `Initialized` and `Ready` is the real startup time. Here it was
  7 seconds against a budget of 60.

---

## Failure 2 — a rollout without readiness returns 502

- **Symptom:** on every rollout the load balancer returns 5xx for a few seconds, then it
  passes by itself. Everything in the cluster looks correct.

- **Signal:** a `curl` loop through the ALB, once per second, during a rollout:

  ```
  23:25:55 200
  23:25:56 502
  23:26:02 000        <- -m 5 fired: the request hung
  23:26:03 200
  ```

  The missing seconds `23:25:57–23:26:01` are a signal too: the script sleeps exactly
  one second, so missing timestamps mean requests that hung. The failure window is about
  seven seconds.

  Meanwhile `kubectl get pods -w` shows the Deployment controller working flawlessly:

  ```
  talk-booking-55f6786f54-l7mh4   0/1   Running       1s
  talk-booking-55f6786f54-l7mh4   1/1   Running       6s
  talk-booking-77774f5d7f-dh89k   1/1   Terminating   7m42s
  ```

  The old pod is killed **only after** the new one becomes `Ready`.

- **Cause:** `Ready` is one value on which three parties act independently:
  - the Deployment controller decides whether the old pod may be killed;
  - the endpoints controller decides whether to send traffic;
  - the load balancer controller, through the endpoints, decides whether to register the
    target.

  Without a readiness probe kubelet sets `Ready` the moment the container starts, and all
  three act on a signal that means nothing. The `maxUnavailable: 0` guarantee is formally
  kept — the controller honestly waited for `Ready`.

  The second half of the cause is **two independent opinions about health**. The new pod
  is already `Ready` for Kubernetes, but its target in the target group is still
  `initial`, while the old one has already gone to `draining`. In that gap the load
  balancer has no target it is willing to send traffic to, and it returns the 5xx itself,
  without reaching the application.

- **Fix:** a readiness probe on `/ready`, which checks the database connection. Its
  thresholds are set so readiness fires noticeably earlier than liveness — first take the
  traffic away, then kill. The reverse order means cutting connections that requests are
  flying into right now.

- **Prevention:** the width of the failure window **does not depend on load** — only the
  number of affected requests does. One request per second gave seven failures; a
  thousand per second would give seven thousand in the same window. So a rollout has to
  be checked under load, not by eye: without a live request loop the window is not
  observable at all.

  And the split of responsibility between probes: liveness looks **only at itself** — a
  dependency in it turns a database outage into a simultaneous restart of the whole
  fleet. Dependencies are checked by readiness, which takes traffic away but kills
  nobody.
