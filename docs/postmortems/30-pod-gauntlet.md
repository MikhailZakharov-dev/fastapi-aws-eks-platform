# A pod that will not start: four statuses, four actors (theme 30)

Four induced failures on one stand, one replica in `dev`. The main lesson: **the word in
the `STATUS` column is not the cause.** It is what kubelet is busy with right now. The
cause is written by different components into different fields, and you look for it
where the component that stopped the pod writes.

## Cheat sheet

| status | where the pod's path stopped | who stopped it / formed the code | decisive field | command |
|---|---|---|---|---|
| `Pending` | ① assignment to a node | scheduler | `Events` → `FailedScheduling` (what did not fit), `Conditions` → `PodScheduled False` | `describe pod` |
| `ImagePullBackOff` | ② pulling the image | the registry answered "no such tag", kubelet recorded it | `Events` → `Failed to pull image … not found` | `describe pod` |
| `CrashLoopBackOff`, `StartError`, code 128 | ③ starting the process | the runtime (runc): `exec` failed, the application process never started | `Last State` → `Reason: StartError`, `Message`, `Started: 1970` (zero time) | `describe pod`; `logs --previous` is empty |
| `CrashLoopBackOff`, `Error`, code 1 | after ③, the process exited on its own | the application | `Last State` → `Reason: Error`, `Exit Code` | `logs --previous` |
| `OOMKilled` → `CrashLoopBackOff`, code 137 | ④ the process is running | the kernel: the cgroup memory counter crossed `limits.memory` | `Last State` → `Reason: OOMKilled`; there is **no** kill event in `Events` | `describe pod` |

How to read it:

- `State` is what the container is doing **now** (often just waiting before a retry).
  `Last State` is how the **previous** run ended. Look for the cause of a crash in the
  second one.
- Code 137 = `128 + 9` (SIGKILL) comes both from the kernel on memory and from kubelet
  when `terminationGracePeriodSeconds` runs out (theme 26). The code cannot tell them
  apart — `Reason` can.
- Code 127 is formed by the shell **inside** the container (`sh -c nope`): the `sh`
  process started, did not find the command and exited on its own. Then it is
  `Reason: Error`, a normal start time and the shell's line in `logs --previous`. Code 128
  with `StartError` is the runtime; the application was never reached.
- The pause between restarts grows up to 5 minutes and then stops growing — hence
  `RESTARTS (5m ago)` in `get pods -w`.

## What monitoring sees

| act | passed ① (has an IP)? | `up{…}` of the new pod | fired |
|---|---|---|---|
| broken tag | yes | `0` | `AppDown` |
| OOM | yes | `0` | `AppDown` |
| `requests.cpu: 10` | **no** | no series | **nothing** |
| broken command | yes | `0` | `AppDown` |

- A pod gets its IP when it is created on a node, that is, only after ①. A non-Ready
  address lands in the EndpointSlice with `ready=false`, and Prometheus scrapes those too:
  readiness cuts the pod off from traffic, but not from scraping. Hence `up=0` and a
  firing `AppDown` in three acts.
- A `Pending` pod has no address, so there is no target, no `up` series, and `AppDown`
  stays silent. `AppTargetMissing` is silent too: `absent()` looks at the whole selector,
  and the old pod's series with `up=1` is still there.
- In all four acts the user **did not see** the failure: with one replica, a Deployment
  does not remove the old pod until the new one is Ready. So `AppDown` in its current form
  pages `critical` while the service is fully alive. Better is `sum(up{…}) == 0` (zero
  live targets), with the built-in `KubeDeploymentRolloutStuck` catching a stuck rollout.
  Not applied; the decision is open.

## How it was broken and what did not go to plan

- The first attempt at the "broken tag" act through `values-dev` never reached the
  Deployment: the tag is shared by the application and the migration, the PreSync hook
  failed first, the sync stalled, the old ReplicaSet was not touched, and the alerts were
  green. The act was redone with `kubectl set image` with automated sync removed from
  root and `app-dev`. A mistake in the tutor's scenario.
- An unplanned failure during teardown: `helm_release.eso` — `context deadline exceeded`.
  Deleting the ESO CRDs cascaded to the `ExternalSecret` objects; their
  `externalsecret-cleanup` finalizer is removed only by the ESO controller, and that
  controller was removed by the same uninstall. The objects hung in `Terminating`. Fixed
  in `make down` (`9b427bd`): `ExternalSecret` objects are deleted before the teardown,
  while the controller is still alive.

## What changed in the system

- The chart got a `resources` block (`76997eb`); `dev` got values from measurement
  (`ea16564`): `requests` 50m / 96Mi, `limits.memory` 192Mi, no CPU limit. The pod's QoS
  class changed from `BestEffort` to `Burstable`.
