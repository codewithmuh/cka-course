# Probes, restart policies and disruption budgets

> **Module 2** · Lesson 2.7 · 40 minutes

The three probes and what each one does when it fails, how readiness decides which Pods get traffic, and how a PodDisruptionBudget protects an app during a node drain.

## Learning Objectives

- You can add liveness, readiness and startup probes with the right check and timing, and say what each failure causes.
- You can trace a Pod that is Running but not Ready back to its probe, and see the effect on the Service's endpoints.
- You can create a PodDisruptionBudget and read whether it allows a disruption right now.


Kubernetes can only fix what it notices. If a container crashes, the kubelet sees the process exit and restarts it. But what if your Django app is still running, yet stuck and answering nothing? A **probe** is a regular health check that the kubelet runs against a container, so it can notice that too.

On the exam, you may add probes to a workload, or fix a probe that checks the wrong place. You may also protect a workload from a node drain with a PodDisruptionBudget.

## Three probes, three different questions

**When each probe runs**

*The startup probe runs first. Once it passes, readiness and liveness checks run side by side for the rest of the container's life.*

`Startup probe` — has the app finished starting? → `Then, for the container's whole life`
  - `Readiness probe` — can it take traffic now?
  - `Liveness probe` — is it stuck?

| Probe | Asks | When it fails | Typical check |
| --- | --- | --- | --- |
| `livenessProbe` | Is the app stuck? | The kubelet kills the container. `restartPolicy` decides what happens next | A cheap local check, such as a TCP port |
| `readinessProbe` | Can it take traffic right now? | The Pod is marked not Ready and gets no Service traffic. Nothing is restarted | A page that shows the app can serve |
| `startupProbe` | Has it finished starting? | Liveness and readiness wait until it passes. If it never passes, the container is killed | The liveness check, with more time allowed |

Example: your Django app takes 60 seconds to load. A startup probe gives it that time. After that, the readiness probe keeps it out of the Service while it cannot serve, and the liveness probe restarts it if it hangs.

Each probe uses one kind of check, called a **handler**. The common ones are `httpGet` (send an HTTP request), `tcpSocket` (open a port) and `exec` (run a command inside the container).

**All three probes, and the handler types**

```yaml
      containers:
        - name: web
          image: nginx:1.27
          ports:
            - containerPort: 80
              name: http
          startupProbe:
            httpGet:
              path: /
              port: http            # a named port works anywhere a port number does
            periodSeconds: 5
            failureThreshold: 24    # up to 24 x 5 = 120s to start
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: 80
            periodSeconds: 10
            failureThreshold: 3
        # Other handlers:
        #   exec:     { command: ["cat", "/tmp/healthy"] }   # exit code 0 = success
```

<details>
<summary>Line-by-line explanation</summary>

- `startupProbe:` — Probes are set per container, at the same indent as `image`. The startup probe runs first; liveness and readiness checks begin only after it has passed.
- `httpGet:` — An HTTP check: any status code from 200 to 399 counts as success.
- `readinessProbe:` — Checked for the container's whole life. While it fails, the Pod is not Ready and gets no Service traffic, but nothing is restarted.
- `livenessProbe:` — After 3 failures in a row (`failureThreshold`), the kubelet kills the container and it is restarted.
- `tcpSocket:` — A TCP check: success means the port accepts a connection. It proves the process listens, not that it answers correctly.

</details>

These timing fields work the same on all three probes:

| Field | Default | Meaning |
| --- | --- | --- |
| `initialDelaySeconds` | 0 | Seconds to wait after the container starts, before the first check |
| `periodSeconds` | 10 | How often to check |
| `timeoutSeconds` | 1 | How long one check may take |
| `failureThreshold` | 3 | Failures in a row before acting |
| `successThreshold` | 1 | Successes in a row to count as passing again. Must be 1 for liveness and startup |

- For a slow starter, use a startup probe, not a long `initialDelaySeconds` on liveness. The app gets time to start, and a later hang is still caught quickly.
- Keep liveness checks local. Say a liveness probe calls the database. When the database has a short outage, every replica fails its check and restarts at once: one outage becomes two.

## Readiness is what Services and rollouts trust

A Pod that fails readiness stays `Running`, but shows `READY 0/1`. Two things follow:

- **Services skip it.** Its address stays in the Service's EndpointSlices, marked `ready: false`, so no traffic is sent to it.
- **Rollouts wait for it.** A Deployment counts only Ready Pods as available. So a rollout whose new Pods never become Ready stops, instead of replacing healthy Pods.

A wrong readiness port is one of the most common cases of *it is running but nothing works*. Trace it like this:

**From symptom to probe**

```bash
kubectl -n wl-probe get pods -l app=catalog                    # Running, READY 0/1
kubectl -n wl-probe describe pod -l app=catalog | grep -E 'Readiness|Liveness|Unhealthy' | head
#   Warning  Unhealthy  ...  Readiness probe failed: Get "http://10.244.x.x:8080/": dial tcp ... connection refused
kubectl -n wl-probe get endpointslices -l kubernetes.io/service-name=catalog -o yaml | grep -A1 conditions
kubectl -n wl-probe get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'; echo
```

<details>
<summary>Line-by-line explanation</summary>

- `get pods -l app=catalog` — Running but `0/1` READY means the container started, and its readiness probe is failing.
- `grep -E` — `describe pod -l` describes every matching Pod. `grep -E 'A|B|C'` keeps lines that contain any of the three words: the probe settings and Unhealthy events. `head` keeps the first 10.
- `Readiness probe failed` — Sample event: it shows the exact URL and port the probe tried. Compare that port with the one the app listens on.
- `get endpointslices` — EndpointSlices list the Service's Pod addresses; the label `kubernetes.io/service-name` links them to the Service. `grep -A1 conditions` shows the line after each `conditions:`, which is `ready: true` or `ready: false`.
- `readinessProbe}'` — Prints the probe as the Deployment defines it, so you can compare its port and path with the container's.

</details>

## restartPolicy and CrashLoopBackOff

`restartPolicy` is set once per Pod and covers every container in it. Deployments, StatefulSets and DaemonSets accept only `Always`. Jobs use `OnFailure` or `Never`.

After a crash or a liveness kill, the kubelet restarts the container, and it waits a little longer each time. While it waits, the Pod shows `CrashLoopBackOff`. Finding out why is covered in [Application failures](/cka/troubleshooting/application-failures).

## PodDisruptionBudgets

Sometimes Pods are removed on purpose, for example when you drain a node to upgrade it. A **PodDisruptionBudget** (PDB) makes sure enough Pods of an app stay up while that happens. Example: your shop runs 3 cart Pods. A PDB with `minAvailable: 2` lets a drain take away only one of them at a time.

**policy/v1: keep at least two Pods through voluntary disruptions**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cart-pdb
  namespace: wl-probe
spec:
  minAvailable: 2          # or maxUnavailable: 1; never both. Integers or percentages.
  selector:
    matchLabels:
      app: cart
# Imperative: kubectl -n wl-probe create pdb cart-pdb --selector=app=cart --min-available=2
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: policy/v1` — PodDisruptionBudgets live in the `policy` API group.
- `minAvailable: 2` — An eviction is refused if it would leave fewer than 2 matching Pods healthy.
- `selector:` — Picks the Pods to protect by label, usually the same labels as the Deployment's selector. A PDB never names the Deployment itself.
- `# Imperative:` — The same object in one command. The flags are `--min-available` or `--max-unavailable`, with dashes.

</details>

**What happens during a drain**

`kubectl drain` — asks to evict a Pod → `PodDisruptionBudget` — would enough Pods stay up? → `Eviction` — allowed, or refused and tried again

**What a PDB protects against**

- It limits **voluntary** disruptions that go through the Eviction API: `kubectl drain`, a cluster autoscaler removing a node, and some upgrade tools.
- It does nothing when a node crashes.
- `kubectl delete pod` skips it completely.

**How to read it.** Run `kubectl get pdb` and look at `ALLOWED DISRUPTIONS`:

- 1 or more: a drain may evict that many of these Pods right now.
- 0: a drain of a node that runs one of these Pods will block.
- The trap: `minAvailable` equal to the replica count always leaves 0, so it blocks every drain.

> [!IMPORTANT] **What the grader reads**
> For probes, the grader reads the fields under `spec.template.spec.containers[]`: the handler type, `path`, `port` and the timing numbers, exactly as asked. It also reads `status.readyReplicas`. Changing a probe changes the Pod template and starts a rollout, so wait for `kubectl rollout status` before you check. For PDBs, it reads `spec.minAvailable` or `spec.maxUnavailable`, the selector, and often `status.expectedPods`. That is 0 when your selector matches nothing.

## 📝 Key Takeaways

- A startup probe gives a slow app time to start. Readiness and liveness checks wait until it passes.
- A failing readiness probe stops traffic to the Pod but restarts nothing. A failing liveness probe restarts the container.
- Running but `READY 0/1` means the readiness probe fails. `kubectl describe pod` shows where it connects.
- A PodDisruptionBudget limits drains and other evictions, not crashes or `kubectl delete`.
- `ALLOWED DISRUPTIONS` of 0 means a drain will block. Never set `minAvailable` equal to the replica count.

**📖 Official documentation:**

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) *(search: "liveness readiness startup probes")*
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) *(search: "pod lifecycle restart policy")*
- [Specifying a Disruption Budget for your Application](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) *(search: "disruption budget")*

---

### 🎯 Task: Add readiness and liveness probes to a Deployment

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

The Deployment `shop` in namespace `wl-probe` has no health checks. Add to its `nginx` container a readiness probe that sends an HTTP GET to `/` on port 80 every 5 seconds, starting 3 seconds after the container starts, and a liveness probe that opens a TCP connection to port 80 every 10 seconds, starting after 10 seconds, and restarts the container after 3 consecutive failures. All 3 replicas must be ready afterwards.

<details>
<summary>💡 Hints</summary>

- A `readinessProbe` with `httpGet`, `initialDelaySeconds: 3` and `periodSeconds: 5`.
- A `livenessProbe` with `tcpSocket`, `initialDelaySeconds: 10`, `periodSeconds: 10` and `failureThreshold: 3`. Then run `kubectl rollout status`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-probe patch deploy shop --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","readinessProbe":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":3,"periodSeconds":5},"livenessProbe":{"tcpSocket":{"port":80},"initialDelaySeconds":10,"periodSeconds":10,"failureThreshold":3}}]}}}}'
kubectl -n wl-probe rollout status deploy/shop --timeout=150s
```

**Explanation:**

- `patch deploy shop` — A strategic merge patch merges this JSON into the Deployment and matches the container by its name, so only the two probes are added. Readiness: GET / on port 80 after 3s, every 5s. Liveness: TCP 80 after 10s, every 10s, 3 failures.
- `rollout status` — Probes are part of the Pod template, so the patch rolls out new Pods. Wait for it to finish before checking readiness.

**Notes:** On the exam, run `kubectl edit deploy shop -n wl-probe` and add both blocks under the container, at the same indent as `image`. The strategic merge patch used here finds the container by its `name`, so nothing else in the template changes. Probes are part of the Pod template, so the change rolls out new Pods. Wait for it before you check.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-probe
c="{.spec.template.spec.containers[?(@.name==\"nginx\")]"
d="kubectl -n $ns get deploy shop -o jsonpath"

kubectl -n $ns get deploy shop >/dev/null 2>&1 && p "deployment shop exists" || f "deployment shop exists"
[ "$($d="$c.readinessProbe.httpGet.path}:$c.readinessProbe.httpGet.port}" 2>/dev/null)" = "/:80" ] && p "readiness httpGet / on port 80" || f "readiness httpGet / on port 80"
[ "$($d="$c.readinessProbe.initialDelaySeconds}/$c.readinessProbe.periodSeconds}" 2>/dev/null)" = "3/5" ] && p "readiness initialDelay 3, period 5" || f "readiness initialDelay 3, period 5"
[ "$($d="$c.livenessProbe.tcpSocket.port}" 2>/dev/null)" = "80" ] && p "liveness tcpSocket port 80" || f "liveness tcpSocket port 80"
[ "$($d="$c.livenessProbe.initialDelaySeconds}/$c.livenessProbe.periodSeconds}/$c.livenessProbe.failureThreshold}" 2>/dev/null)" = "10/10/3" ] && p "liveness initialDelay 10, period 10, failureThreshold 3" || f "liveness initialDelay 10, period 10, failureThreshold 3"
[ "$($d='{.status.readyReplicas}/{.status.updatedReplicas}/{.status.replicas}' 2>/dev/null)" = "3/3/3" ] && p "3 updated replicas ready" || f "3 updated replicas ready"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Protect a Deployment from drains with a PDB

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 4 min |

**Question:**

In namespace `wl-probe`, create a PodDisruptionBudget named `cart-pdb` for the Pods of Deployment `cart` so that voluntary disruptions such as a node drain can never leave fewer than 2 of them available.

<details>
<summary>💡 Hints</summary>

- Find the Pod labels with `kubectl get deploy cart -o jsonpath='{.spec.selector}'`.
- `kubectl create pdb cart-pdb --selector=app=cart --min-available=2`

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-probe create pdb cart-pdb --selector=app=cart --min-available=2
for i in $(seq 1 30); do [ "$(kubectl -n wl-probe get pdb cart-pdb -o jsonpath='{.status.expectedPods}')" = "3" ] && break; sleep 2; done
kubectl -n wl-probe get pdb cart-pdb
```

**Explanation:**

- `create pdb cart-pdb` — `--selector=app=cart` matches the label kubectl create deployment put on the cart Pods, and `--min-available=2` keeps at least 2 of the 3 through any drain.
- `for i in $(seq 1 30)` — Checks up to 30 times, 2 seconds apart, until the PDB's status counts all 3 Pods; `break` leaves the loop as soon as it does. `seq 1 30` prints the numbers 1 to 30.
- `get pdb cart-pdb` — Expect MIN AVAILABLE 2 and ALLOWED DISRUPTIONS 1. ALLOWED 0 while all 3 Pods are healthy would mean the selector matches nothing.

**Notes:** With 3 replicas, `maxUnavailable: 1` protects in the same way. The grader accepts either, because it reads the computed status: 3 expected Pods, 2 desired healthy, 1 disruption allowed. A PDB whose selector matches nothing shows `expectedPods: 0` and protects nothing. So always look at `kubectl get pdb` afterwards.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-probe
b="kubectl -n $ns get pdb cart-pdb -o jsonpath"

kubectl -n $ns get pdb cart-pdb >/dev/null 2>&1 && p "pdb cart-pdb exists" || f "pdb cart-pdb exists"
spec="$($b='{.spec.minAvailable}|{.spec.maxUnavailable}' 2>/dev/null)"
{ [ "$spec" = "2|" ] || [ "$spec" = "|1" ]; } && p "budget keeps 2 of 3 available" || f "budget keeps 2 of 3 available"
[ "$($b='{.status.expectedPods}' 2>/dev/null)" = "3" ] && p "selector matches the 3 cart pods" || f "selector matches the 3 cart pods"
[ "$($b='{.status.desiredHealthy}/{.status.disruptionsAllowed}' 2>/dev/null)" = "2/1" ] && p "2 desired healthy, 1 disruption allowed" || f "2 desired healthy, 1 disruption allowed"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Pods run but never become Ready

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `wl-probe`, the Pods of Deployment `catalog` are all Running, yet none of them is Ready and the Service `catalog` sends traffic nowhere. Find the cause and fix the Deployment so that all 3 replicas become Ready and are registered as ready endpoints of the Service. Do not remove the readiness probe.

<details>
<summary>💡 Hints</summary>

- Run `kubectl describe pod` on one of the Pods. The Events section says which probe fails and where it connects.
- Compare the probe's port with the port nginx listens on.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-probe patch deploy catalog --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
kubectl -n wl-probe rollout status deploy/catalog --timeout=150s
```

**Explanation:**

- `patch deploy catalog --type=json` — A JSON patch changes one exact field by its path: the readiness probe port of container 0, set to 80 where nginx listens. List items are addressed by index, not by name.
- `rollout status` — New Pods with the fixed probe roll out. Once Ready, they appear as ready endpoints of the Service.

**Notes:** The events show *Readiness probe failed … :8080 … connection refused*, while nginx listens on 80. Fix it with `kubectl edit deploy catalog -n wl-probe`: change the probe port to 80, or to a named port that points at 80. The Service was never the problem. Its `targetPort` was right; it simply had no Ready Pods to send traffic to. Confirm with `kubectl get endpointslices -n wl-probe -l kubernetes.io/service-name=catalog`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-probe
d="kubectl -n $ns get deploy catalog -o jsonpath"

kubectl -n $ns get deploy catalog >/dev/null 2>&1 && p "deployment catalog exists" || f "deployment catalog exists"
[ -n "$($d='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null)" ] && p "readiness probe still configured" || f "readiness probe still configured"
[ "$($d='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null)" = "3/3" ] && p "3 of 3 replicas ready" || f "3 of 3 replicas ready"
ready="$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=catalog -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{" "}{end}' 2>/dev/null | xargs -n1 | grep -c '^true$')"
[ "$ready" = "3" ] && p "service catalog has 3 ready endpoints" || f "service catalog has 3 ready endpoints"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
