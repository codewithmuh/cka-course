# Application failures

> **Module 5** · Lesson 5.2 · 45 minutes

The usual ways an app breaks on the exam, each as symptom, cause and fix, and four broken scenarios to practice the method on.

## Learning Objectives

- You can name the cause of a Pod failure from its STATUS and one describe, without guessing.
- You can fix image, command, environment, probe, scheduling and volume problems with one kubectl command each.
- You can tell when a Pod must be recreated, and do it in one step with replace --force.


Most troubleshooting tasks on the exam are app failures: one setting in a Pod is wrong, and the Pod shows it. There are only about ten patterns. For each one, this lesson gives the symptom, the cause and the fastest fix. You find them with the loop from [the method lesson](/cka/troubleshooting/troubleshooting-method). The tasks at the end each break one thing, like the exam.

**How each pattern reads**

*Every pattern in this lesson has the same three parts: what you see, the line that names the cause, and one command that fixes it.*

`You see` (`ImagePullBackOff`) → `The event says` (`nginx:1.72: not found`) → `You fix it` (`kubectl set image …`)

It also helps to know the order in which a Pod starts. The status tells you which step broke, and so where to look:

**Where a Pod's start can fail**

*A Pod starts in four steps. The code in each box is the status you see when that step fails.*

`Find a node` — the scheduler's job (`Pending`) → `Prepare` — pull the image, mount volumes (`ImagePullBackOff`) → `Run` — your process starts (`CrashLoopBackOff`) → `Ready` — the readiness probe passes (`READY 0/1`)

## Image problems

- **Symptom:** `ErrImagePull`, then `ImagePullBackOff`, as the kubelet waits longer between tries. Or `ContainerCreating` with a *Pulling image* event that never ends.
- **Cause:** read the Failed event. It quotes the full image name and the registry's answer, as in the table below.
- **Fix:** correct the image in the Deployment, not in a Pod.

| The registry says | The cause |
| --- | --- |
| *not found*, *manifest unknown* | A wrong image name or tag |
| *unauthorized*, *pull access denied* | A private registry, and the Pod has no login for it |
| *no such host*, *i/o timeout* | The node cannot reach that registry name |

**Fix a wrong tag**

```bash
# Wrong tag: change the template, the rollout replaces the Pods
kubectl -n $ns set image deploy/web nginx=nginx:1.27
```

<details>
<summary>Line-by-line explanation</summary>

- `set image deploy/web nginx=nginx:1.27` — Points container `nginx` at the right tag. Fix the Deployment rather than a Pod: its ReplicaSet would replace a hand-fixed Pod with one built from the old template.

</details>

For a private registry, the Pod needs a login Secret listed under `imagePullSecrets`. [ConfigMaps and Secrets](/cka/workloads/configmaps-and-secrets) shows how to create one.

## CrashLoopBackOff

- **Symptom:** RESTARTS keeps climbing. STATUS switches between `Running`, `Error` and `CrashLoopBackOff`, with longer pauses each time.
- **Cause:** the process exits. Read `kubectl logs` first. Then read the Exit Code under Last State in `describe`; the table below decodes it.
- **Common reasons:** a misspelled command or argument, a missing environment variable or config file, or a service the app cannot reach. Or the command simply finishes: it exits 0, and the kubelet restarts it forever.

| Exit code | Meaning | Look at |
| --- | --- | --- |
| 0 | The process finished normally. With restartPolicy Always, it is restarted anyway | the command: does it run a server, or a one-off job? |
| 1 | The app reported an error | the logs |
| 127 | Command not found | the command's spelling, and whether the image has that program |
| 137 | Killed by force (SIGKILL): OOMKilled, or a process that did not stop in time after a failed liveness probe | `describe` → Last State Reason, and the probe events |
| 143 | Asked to stop (SIGTERM): a normal stop, a liveness restart, or an eviction | the events: Killing, and the probe |

**Reading a crash**

```bash
kubectl -n $ns get pod worker                          # RESTARTS 5 (2m ago)
kubectl -n $ns logs worker                             # e.g. sh: sleeep: not found
kubectl -n $ns logs worker --previous                  # when the container is Running again
kubectl -n $ns describe pod worker | grep -A6 'Last State'
kubectl -n $ns get pod worker -o jsonpath='{.spec.containers[0].command} {.spec.containers[0].args}'
```

<details>
<summary>Line-by-line explanation</summary>

- `get pod worker` — RESTARTS counts how often the kubelet has restarted the container, and *(2m ago)* says when it last did. A number that keeps growing means the process keeps exiting.
- `logs worker` — The output of the last crashed run. A misspelled command shows up here as the shell's own *not found* message.
- `--previous` — Needed once the container is Running again after a restart: the crash output then belongs to the previous instance, not the current one.
- `grep -A6 'Last State'` — Jumps to the container's **Last State**: Reason, Exit Code, and when it started and finished. The exit code tells you which kind of failure it was; the table above decodes it.
- `{.spec.containers[0].command}` — Prints the container's `command` and `args` side by side. Together they decide which process starts, so this is where a misspelled program or flag hides.

</details>

**Fix:** correct the command, args or env. For a Deployment, change the template and the rollout recreates the Pods. A bare Pod must be recreated; see **Bare Pods are mostly immutable** below. If describe shows `StartError` with *executable file not found in $PATH*, the command could not even start. The fix is the same.

## Pending

- **Symptom:** `Pending`, with NODE ``.
- **Cause:** the scheduler found no node that fits. The *FailedScheduling* event says why each node was rejected. Four phrases cover the exam:

| The event says | What it means | The fix |
| --- | --- | --- |
| *didn't match Pod's node affinity/selector* | The nodeSelector or affinity asks for a label that no node has | Correct the selector. Label a node only if the question asks you to |
| *Insufficient cpu*, *Insufficient memory* | The Pod asks for more than any node has free | Lower the request with `kubectl set resources`, unless the question gives the number |
| *had untolerated taint(s)* | A node has a taint the Pod does not accept. Normal for the control plane | A problem only if it hits every node. Then add a toleration or remove the taint, as the question asks |
| *unbound immediate PersistentVolumeClaims* | The Pod's PVC is not Bound | Fix the claim, or create a PV for it |

A PVC in a `WaitForFirstConsumer` StorageClass is *not* a failure: it waits for the Pod to be scheduled, then binds. And Pending with **no event at all** means nothing has looked at the Pod: the scheduler is down. [Control plane failures](/cka/troubleshooting/control-plane-failures) covers that.

## ContainerCreating that never ends

- **Symptom:** the Pod has a node, but stays in `ContainerCreating`.
- **Cause:** a *FailedMount* event. A ConfigMap or Secret volume points to an object that does not exist (*secret "db-creds" not found*), or a PVC is not Bound.
- **Fix:** create the missing object. Or mark the volume `optional: true`, if the question says the app can run without it.

After the fix, the Pod can take up to two minutes to start, because the kubelet retries the mount with a growing delay. If you are in a hurry, recreate the Pod.

## OOMKilled

- **Symptom:** restarts with exit code 137, and `Reason: OOMKilled` under Last State.
- **Cause:** the container used more memory than its limit, `resources.limits.memory`.
- **Fix:** raise the limit; the question usually gives the number. On a Deployment, run `kubectl set resources deploy/x -c name --limits=memory=512Mi`. Recreate a bare Pod with the new limit.

## Liveness probes that kill healthy containers

- **Symptom:** the app works, yet RESTARTS climbs. The events say *Liveness probe failed: … connection refused* or *HTTP probe failed with statuscode: 404*. Then: *Container nginx failed liveness probe, will be restarted*.
- **Cause:** the probe checks the wrong port or path. Or it starts checking before the app is up, because `initialDelaySeconds` is too short.
- **Fix:** fix the probe, not the app.

**See the probe, fix the probe**

```bash
kubectl -n $ns get deploy api -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'; echo
kubectl -n $ns get deploy api -o jsonpath='{.spec.template.spec.containers[0].ports}'; echo
kubectl -n $ns patch deploy api --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'
kubectl -n $ns rollout status deploy/api --timeout=120s
```

<details>
<summary>Line-by-line explanation</summary>

- `containers[0].livenessProbe}'` — Prints the first container's liveness probe as JSON: its type (`httpGet`), path, port and timings. The port is the number to check.
- `containers[0].ports}'` — Prints the ports the container declares. If the probe asks a port the app does not listen on, the kubelet gets *connection refused* and restarts a perfectly healthy container.
- `patch deploy api --type=json` — A JSON patch on the Deployment's template. The `\` at the end of the line continues the command on the next one.
- `-p='[{"op":"replace"` — `op` is the action, `path` the field written as a slash-separated path (`containers/0` is the first container), and `value` the new port. Nothing else in the probe changes.
- `rollout status deploy/api` — The template changed, so new Pods roll out; this waits until they are all available, or 120 seconds have passed.

</details>

Do not mix it up with a **readiness** probe. A failing readiness probe never restarts anything: the Pod shows READY 0/1 and gets no Service traffic. [Probes, restart policies and disruption budgets](/cka/workloads/probes-and-self-healing) explains the probe types.

## Three more patterns, in short

- **Pods Running and Ready, but the Service does not answer.** That is a Service problem, not a Pod problem. [Service and DNS failures](/cka/troubleshooting/service-and-dns-failures) covers it.
- **Init:Error or Init:CrashLoopBackOff.** An init container fails, so the app never starts. Read its logs with `kubectl logs  -c `. [Pods, init containers and sidecars](/cka/workloads/pods-and-multi-container) teaches init containers.
- **A wrong ConfigMap key or Secret name.** The Pod shows `CreateContainerConfigError`, and the event names the key. The second task of [the method lesson](/cka/troubleshooting/troubleshooting-method) is this case.

A typo in a *variable name* is sneakier. It gives no error at all: the app starts and misbehaves. `kubectl exec  -- env` shows which variables the container really has.

## The catalog on one screen

| You see | First command | Usual fix |
| --- | --- | --- |
| ImagePullBackOff | `describe pod | tail` | `set image`, or add imagePullSecrets |
| CrashLoopBackOff | `logs`, then `logs --previous` | fix the command, args or env; recreate the Pod or roll out the Deployment |
| Pending, NODE  | `describe pod | tail` | lower the requests, fix the nodeSelector or affinity, add a toleration, or bind the PVC |
| ContainerCreating, FailedMount | `describe pod | tail` | create the ConfigMap, Secret or PVC it names |
| CreateContainerConfigError | `describe pod | tail`, then `get cm` or `get secret` | match the key name; recreate the Pod |
| OOMKilled, exit 137 | `describe pod | grep -A6 'Last State'` | raise `limits.memory` |
| Restarts with probe events | `get deploy -o jsonpath=…livenessProbe` | fix the port, path or initialDelaySeconds |
| Running, READY 0/1 | `describe pod | tail` | fix the readiness probe |
| Init:Error | `logs  -c ` | fix the init command, or create what it waits for |

> [!IMPORTANT] **One broken thing, fixed where the question says**
> Exam scenarios break a single field. If the question says *fix the Deployment*, the grader checks the Deployment's template and its available replicas. A Pod you patched by hand will be replaced. If it says *do not change the nodes* or *do not modify the ConfigMap*, that rule is graded too. Read the rule, fix the named object, prove it with `kubectl get`, and move on.

> [!WARNING] **Bare Pods are mostly immutable**
> You cannot change the command, args, env, volumes, probes, nodeSelector or resources of a running Pod; `kubectl edit` cannot save the change. Instead, export the Pod with `-o yaml`, fix the file, and run `kubectl replace --force -f` on it. That deletes the Pod and creates it again. Add `--grace-period=0` if the process ignores the stop signal, as a shell running `sleep` does.

## 📝 Key Takeaways

- The STATUS tells you which step failed: Pending is finding a node, ImagePullBackOff and ContainerCreating are preparing, CrashLoopBackOff is your process.
- Read the event or the logs before you change anything. They usually quote the bad value.
- Exit code 127 means command not found. Exit code 137 usually means OOMKilled.
- A failing liveness probe restarts a healthy container. A failing readiness probe only takes it out of the Service.
- Fix the Deployment, not its Pods. A bare Pod's command, env or probes need `replace --force`.

**📖 Official documentation:**

- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) *(search: "debug pods")*
- [Determine the Reason for Pod Failure](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/) *(search: "reason for pod failure")*
- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) *(search: "liveness readiness probes")*
- [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/) *(search: "private registry imagePullSecrets")*

---

### 🎯 Task: A Deployment that stays Pending

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

The Deployment `frontend` in namespace `ts-app` shows 0 of 2 Pods ready. It is required to run on the node `cka-worker`. Correct the Deployment's node selector so that both Pods are Running on that node. Do not add, change or remove labels on any node.

<details>
<summary>💡 Hints</summary>

- NODE is  for both Pods, so read the FailedScheduling event. Which phrase appears for the workers?
- kubectl get nodes --show-labels: the hostname label of the worker you need is kubernetes.io/hostname=cka-worker.
- Patch the nodeSelector in the template. The rollout replaces the Pending Pods.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-app get pods -l app=frontend -o wide
kubectl -n ts-app describe pod -l app=frontend | tail -4
kubectl get nodes --show-labels
kubectl -n ts-app patch deploy frontend -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"cka-worker"}}}}}'
kubectl -n ts-app rollout status deploy/frontend --timeout=120s
kubectl -n ts-app get pods -l app=frontend -o wide
```

**Explanation:**

- `get pods -l app=frontend -o wide` — Both Pods are Pending and NODE says ``: the scheduler has not placed them, so this is a scheduling problem.
- `describe pod -l app=frontend | tail -4` — The FailedScheduling event reads *didn't match Pod's node affinity/selector* for the workers: the template asks for a node that no label matches.
- `get nodes --show-labels` — Every node's labels. Each carries `kubernetes.io/hostname` set to its own name, so the right value is `cka-worker`; `cka-worker1` does not exist.
- `patch deploy frontend` — Sets the nodeSelector in the Pod template. The key is the same as the broken one, so the merge patch overwrites its value rather than adding a second rule. No node label is touched, as the task demands.
- `rollout status deploy/frontend` — New Pods are created from the fixed template and the Pending ones go away; this waits until both new ones are available.
- `get pods -l app=frontend -o wide` — Proof: both Pods Running, with `cka-worker` in the NODE column.

**Notes:** The event says *2 node(s) didn't match Pod's node affinity/selector*. The template asks for `kubernetes.io/hostname: cka-worker1`, a node that does not exist. A merge patch on `nodeSelector` replaces the value of a key that is already there. If the broken selector had used a different key (say `disk: ssd`), the patch would add yours beside it. You would then need `kubectl edit`, or a JSON patch `remove`, to drop the old one. Labeling a node to match would also schedule the Pods. But the question forbids it, and the grader checks the selector.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-app

kubectl -n $ns get deploy frontend >/dev/null 2>&1 && p "deployment frontend exists" || f "deployment frontend exists"
sel=$(kubectl -n $ns get deploy frontend -o jsonpath='{.spec.template.spec.nodeSelector}' 2>/dev/null)
[ "$sel" = '{"kubernetes.io/hostname":"cka-worker"}' ] && p "nodeSelector is kubernetes.io/hostname=cka-worker" || f "nodeSelector is kubernetes.io/hostname=cka-worker (got: $sel)"
[ "$(kubectl -n $ns get deploy frontend -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
bad=$(kubectl -n $ns get pods -l app=frontend -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.spec.nodeName}|{.status.phase}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && ($2!="cka-worker" || $3!="Running")' | wc -l | tr -d ' ')
[ "$bad" = "0" ] && p "every pod Running on cka-worker" || f "every pod Running on cka-worker"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Pod that restarts forever

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

The Pod `queue-worker` in namespace `ts-app` restarts over and over and never becomes Ready. Fix it so that it runs continuously. Keep the same name, namespace and image. When you are done the Pod must be Running and Ready with no restarts since your fix.

<details>
<summary>💡 Hints</summary>

- kubectl logs queue-worker: one line is enough to spot it.
- The exit code under Last State in describe is 127. What does 127 mean?
- command cannot be changed on a running Pod. Export it, fix it, then kubectl replace --force -f.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n ts-app logs queue-worker || true
kubectl -n ts-app get pod queue-worker -o yaml > /tmp/cka/queue-worker-broken.yaml
kubectl -n ts-app replace --force -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: queue-worker
  namespace: ts-app
  labels:
    app: queue-worker
spec:
  containers:
    - name: worker
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
YAML
kubectl -n ts-app wait --for=condition=Ready pod/queue-worker --timeout=90s
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the folder for the backup file, if it is not there yet.
- `logs queue-worker || true` — Prints *sh: sleeep: not found*: the shell has no program with that spelling. `|| true` makes the line count as a success even if `logs` returns an error, so a script keeps going.
- `-o yaml > /tmp/cka/queue-worker-broken.yaml` — Saves the broken Pod as a file first. On the exam, this is the file you would fix in vim.
- `replace --force -f - <<'YAML'` — Deletes the old Pod and creates a fresh one from the YAML below. A new Pod is the only way to change `command`, and it starts with RESTARTS at 0, as the task requires.
- `image: busybox:1.36` — Same image as before: the task says to keep it.
- `command:` — The fix: `sleep` spelled correctly. `sh -c` runs the string as a shell command, and `sleep 3600` keeps the container busy for an hour, so it does not exit.
- `wait --for=condition=Ready` — Waits for the new Pod to become Ready, up to 90 seconds.

**Notes:** `kubectl logs queue-worker` prints *sh: sleeep: not found*, and Last State shows exit code 127: command not found. On the exam: run `kubectl get pod queue-worker -o yaml > qw.yaml`, fix the command in vim, then run `kubectl replace --force -f qw.yaml`. The old Pod goes away at once, because its process is not running at that moment. If it were, `--grace-period=0` would save you 30 seconds. The new Pod starts with RESTARTS 0, as the question asks.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-app
g="kubectl -n $ns get pod queue-worker -o jsonpath"

kubectl -n $ns get pod queue-worker >/dev/null 2>&1 && p "pod queue-worker exists" || f "pod queue-worker exists"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
[ "$($g='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && p "container Ready" || f "container Ready"
[ "$($g='{.status.containerStatuses[0].restartCount}' 2>/dev/null)" = "0" ] && p "restartCount = 0" || f "restartCount = 0"
[ "$($g='{.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image still busybox:1.36" || f "image still busybox:1.36"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Deployment whose healthy Pods keep restarting

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

The Pods of Deployment `api` in namespace `ts-app` restart again and again even though the web server inside them answers requests. Fix the Deployment so its Pods stop restarting. The health check must stay in place. When you are done, both replicas must be Running and Ready with a restart count of 0.

<details>
<summary>💡 Hints</summary>

- describe one Pod. The Unhealthy events quote the URL the kubelet checks. Compare its port with the container's port.
- Fix the template's livenessProbe with a JSON patch (op replace on .../livenessProbe/httpGet/port) or with kubectl edit. Then run kubectl rollout status.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-app get pods -l app=api
kubectl -n ts-app describe pod -l app=api | grep -m3 'probe'
kubectl -n ts-app get deploy api -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet}'; echo
kubectl -n ts-app patch deploy api --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'
kubectl -n ts-app rollout status deploy/api --timeout=120s
kubectl -n ts-app get pods -l app=api
```

**Explanation:**

- `get pods -l app=api` — The RESTARTS column keeps climbing, even though the Pods look Running most of the time.
- `grep -m3 'probe'` — Keeps the first 3 lines of describe that contain *probe*: the *Liveness probe failed* event, with the URL and port the kubelet tried, and *failed liveness probe, will be restarted*. `-m3` stops after 3 matches.
- `livenessProbe.httpGet}'` — Shows just the probe's `httpGet` settings: path `/` on port 8080. nginx listens on 80, so every check is refused.
- `patch deploy api --type=json` — Replaces only the probe's port with 80. The probe itself stays in place, which the task requires.
- `rollout status deploy/api` — Waits for both replacement Pods. They are new Pods, so their restart counts begin at 0.
- `get pods -l app=api` — Final check: 2 Pods Running, READY 1/1, RESTARTS 0.

**Notes:** The events read *Liveness probe failed: Get "http://10.x.x.x:8080/": dial tcp … connection refused*, then *Container nginx failed liveness probe, will be restarted*. nginx listens on port 80, but the probe asks 8080. Either `port: 80` or `port: http` (the name of the container port) is correct. With `kubectl edit deploy api` you change one number. The rollout then replaces both Pods, and the new ones start with RESTARTS 0. Deleting the probe would also stop the restarts, but the question says the health check must stay.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-app
d="kubectl -n $ns get deploy api -o jsonpath"

kubectl -n $ns get deploy api >/dev/null 2>&1 && p "deployment api exists" || f "deployment api exists"
port=$($d='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null)
{ [ "$port" = "80" ] || [ "$port" = "http" ]; } && p "liveness probe targets port 80 (got: $port)" || f "liveness probe targets port 80 (got: $port)"
[ -n "$($d='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)" ] && p "liveness probe still present" || f "liveness probe still present"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
bad=$(kubectl -n $ns get pods -l app=api -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.status.containerStatuses[0].restartCount}|{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && ($2!="0" || $3!="true")' | wc -l | tr -d ' ')
[ "$bad" = "0" ] && p "every pod Ready with 0 restarts" || f "every pod Ready with 0 restarts"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Pod stuck in ContainerCreating

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

The Pod `db-client` in namespace `ts-app` never leaves `ContainerCreating`. The developers say it reads its database password from a Secret that the platform team was supposed to create, with the key `password` and the value `s3cr3t`. Make the Pod Running and Ready. The Pod's specification must stay as it is.

<details>
<summary>💡 Hints</summary>

- describe the Pod. The FailedMount event names the volume and the Secret it cannot find.
- kubectl create secret generic  --from-literal=password=s3cr3t, in the same namespace.
- The kubelet retries the mount with a growing delay. Give it up to two minutes, or recreate the Pod.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-app describe pod db-client | tail -4
kubectl -n ts-app create secret generic db-creds --from-literal=password=s3cr3t
kubectl -n ts-app wait --for=condition=Ready pod/db-client --timeout=180s
```

**Explanation:**

- `describe pod db-client | tail -4` — The FailedMount event names the volume `creds` and the missing Secret `db-creds`. The kubelet will not start the container until every volume can be mounted.
- `create secret generic db-creds` — Creates the Secret the Pod is waiting for. `generic` is the ordinary type of Secret; `--from-literal=password=s3cr3t` adds the key `password` with that value, and kubectl does the base64 encoding.
- `wait --for=condition=Ready pod/db-client` — The kubelet retries the mount on a growing delay that reaches about two minutes, hence the generous 180-second timeout. The Pod's spec is never touched.

**Notes:** The event reads *MountVolume.SetUp failed for volume "creds" : secret "db-creds" not found*. The Secret's name comes from the event (or from `kubectl get pod db-client -o jsonpath='{.spec.volumes}'`). The key and value come from the question. The kubelet retries the mount with a delay that grows to about two minutes, so the Pod can take that long to notice the new Secret. `kubectl get pod db-client -w` shows it turn Running. If you do not want to wait, recreate the Pod with `kubectl replace --force` from its own exported YAML. The spec stays the same, which is what the question requires.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-app

kubectl -n $ns get secret db-creds >/dev/null 2>&1 && p "secret db-creds exists" || f "secret db-creds exists"
[ "$(kubectl -n $ns get secret db-creds -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)" = "s3cr3t" ] && p "password = s3cr3t" || f "password = s3cr3t"
[ "$(kubectl -n $ns get pod db-client -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
[ "$(kubectl -n $ns get pod db-client -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && p "container Ready" || f "container Ready"
[ "$(kubectl -n $ns get pod db-client -o jsonpath='{.spec.volumes[0].secret.secretName}' 2>/dev/null)" = "db-creds" ] && p "pod still mounts secret db-creds" || f "pod still mounts secret db-creds"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
