# A rollout returns 5xx while every pod is healthy (theme 26)

Measured result: **0.94 % errors → zero**, and throughput went up by 15 %. Both figures
were taken on the same stand, with the same load, two manifest lines apart.

| run | requests | 200 | 502 | 504 | error rate |
|---|---|---|---|---|---|
| without graceful shutdown | 14 967 | 14 826 | 121 | 20 | **0.94 %** |
| with graceful shutdown | 17 189 | 17 189 | 0 | 0 | **0** |

*90 seconds, 20 concurrent clients, `hey` through the ALB, rollout of a single replica.*

---

- **Symptom:** on every rollout a small share of requests returns 5xx. New pods come up
  healthy, probes pass, the Deployment controller honestly waits for the new pod to be
  ready before killing the old one. Single `curl` calls never catch it — it shows only
  under load.

- **Signal:**

  ```
  Status code distribution:
    [200] 14826 responses
    [502] 121 responses
    [504] 20 responses
  ```

  Two different codes are two consecutive phases of a pod's death, not "just 5xx":

  - **502** — a connection was established and then **cut**. Someone was at that
    address: the application closed the socket, the kernel answered with a reset, and the
    load balancer instantly turned that into a 502.
  - **504** — there was **no answer at all**. With `target-type: ip` the pod's address is
    removed from the node's network interface together with the pod. A packet to a
    nonexistent address inside the VPC is simply lost: there is nobody to answer, not even
    with a reset. The load balancer waits until its own timeout.

  The number of 504s matched the number of concurrent clients — every working client hung
  at the same moment, when the address disappeared. That also explains the drop in
  throughput: the cost was not only errors but also occupied slots.

- **Cause:** deleting a pod does not stop traffic — it only starts a **notification**
  that traffic should stop. From the moment the pod is marked for deletion, two
  independent processes run, and neither waits for the other:

  - **dying** is driven by kubelet: preStop → SIGTERM → termination budget → SIGKILL.
    A hard clock, a guaranteed deadline;
  - **detaching from traffic** is driven by controllers: the endpoints controller removes
    the address from the EndpointSlice, then every consumer reacts at its own pace —
    kube-proxy rewrites rules on the nodes, the load balancer controller calls the AWS API
    and moves the target to `draining`. None of these steps has a deadline.

  The asymmetry is the source of the race. The application closes its socket within a
  fraction of a second after SIGTERM — and gets ahead of the notification. Everything the
  load balancer managed to send using its stale target table lands on an address that has
  closed or already vanished.

  The key point: **the stale view of the world is held by the load balancer**, not by the
  client. The client just asks. There is nothing wrong in its behaviour, just as there is
  nothing wrong in the application's — it shut down flawlessly, just too fast.

- **Fix:** a `preStop` sleep before SIGTERM. The hook does not signal the application or
  tell it anything — what works is exactly that kubelet **touches nothing** during that
  time, and the container keeps serving requests as usual. The notification has time to
  reach the load balancer while the pod is still fully functional.

  Three numbers live in three different systems and know nothing about each other:

  - the `preStop` duration — covers the propagation of the notification;
  - `terminationGracePeriodSeconds` — the overall budget, counted **from the moment the
    pod is marked for deletion**, not from SIGTERM, so preStop eats into it. The rule:
    `budget ≥ preStop + the longest request + a margin`;
  - the deregistration delay of the target group — how patient the load balancer is with
    requests already in flight. It does not close the race: that interval starts only
    after new requests have stopped arriving. It is worth shortening for a different
    reason — with `target-type: ip` the group otherwise keeps the addresses of dead pods
    for a long time, and the CNI may hand them out to new pods.

  The smallest and earliest timer always wins. The load balancer's patience is useless if
  the pod did not live long enough.

- **Prevention:**

  **Check rollouts under load, not by eye.** The window lasts a few seconds and does not
  depend on the traffic volume — only the number of affected requests does. One request
  per second shows a couple of errors, a thousand per second shows thousands, with the
  very same window. Without a live request loop the defect is not observable at all and
  ships to prod unnoticed.

  **Remember that the effect lags by one rollout.** A dying pod terminates according to
  the spec it was **created** with. The first rollout after the configuration is broken
  goes clean — it is still killing correctly configured pods. Hence the false conclusion
  "I removed preStop and nothing broke".

  **Check the form of ENTRYPOINT.** In the shell form PID 1 is the shell, and it does not
  forward SIGTERM to the child process: the application never sees the signal and waits
  for SIGKILL, burning the whole budget. The symptom is characteristic — the pod hangs for
  exactly the termination budget, the logs have no line about stopping, exit code 137.

  **Check that the binary used by an `exec` hook exists in the image.** `exec` runs a
  process inside the container; in a distroless image there is no `sleep`, the hook fails
  silently, and kubelet moves straight to SIGTERM. The configuration still looks set up.

  **Zero errors does not prove the number is right** — only that it was enough. The
  propagation time of the notification was never measured directly; a value three times
  smaller might have been enough.
