# A troubleshooting method you can run under pressure

> **Module 5** · Lesson 5.1 · 35 minutes

One fixed loop of commands that finds the cause of almost any broken app in minutes, a map from each Pod status to the place its cause is written, and the habit of fixing with one command instead of an editor.

## Learning Objectives

- You can run the same loop on any broken object (get, describe, logs, exec, then the node and the control plane) without stopping to think what to type next.
- You can read a Pod's STATUS and go straight to the one place where its cause is written.
- You can fix the problem with kubectl set, patch or replace --force, and prove the result before you move on.


Troubleshooting is 30% of the exam, the biggest part. Most of its tasks are not hard once you know where the cause is written. What costs time is wandering: running `get pods` three times, or opening `kubectl edit` before you know what to change. This lesson gives you one loop to run every time, and a map from each Pod status to the place that explains it.

## The loop

Run the same steps, in the same order, on every broken object. Stop at the first step that names the cause.

**The troubleshooting loop**

*Most tasks are solved in these four steps. If the Pod itself looks fine, look wider: first its node, then the control plane.*

`get` — what state is it in? → `describe` — the Events say why → `logs` — what did the app print? → `fix, then get again` — prove the end state

1. **Read the question twice.** Note the namespace, the object names, and what *fixed* means: Running, Ready, reachable through a Service, or a file written. That end state is what the grader checks.
2. **get.** Run `kubectl -n  get all -o wide` and read the STATUS, READY, RESTARTS and NODE columns. Note that `all` skips ConfigMaps, Secrets, PVCs, Ingresses and NetworkPolicies. Ask for those by name when the question mentions them.
3. **describe, read from the bottom.** The Events at the end usually name the cause: a missing key, a bad image tag, a failing probe, or why no node fits.
4. **logs.** What the app itself printed. A wrong command, a missing file or a refused connection shows up here. [Logs, events and container output streams](/cka/troubleshooting/logs-and-output-streams) covers `--previous` and the other options.
5. **exec.** If the container runs, look from the inside: `env`, `ls /etc/config`, `wget -qO- localhost:8080`. This shows what the Pod really sees.
6. **The node.** Run `kubectl get nodes`. If the node is NotReady, the Pod is only a symptom: go to [Worker node failures](/cka/troubleshooting/worker-node-failures).
7. **The control plane.** Run `kubectl -n kube-system get pods`. Pods Pending with no events, Deployments that create nothing, or kubectl refusing to connect point at a cluster part, not at the app. See [Control plane failures](/cka/troubleshooting/control-plane-failures).

**The loop as commands (replace ns and pod)**

```bash
ns=ts-method
kubectl -n $ns get all -o wide
kubectl -n $ns get events --sort-by=.lastTimestamp | tail -20   # or: kubectl -n $ns events --types=Warning
kubectl -n $ns describe pod <pod> | tail -25
kubectl -n $ns logs <pod> [-c <container>] [--previous]
kubectl -n $ns exec <pod> -- env
kubectl get nodes -o wide
kubectl -n kube-system get pods
```

<details>
<summary>Line-by-line explanation</summary>

- `ns=ts-method` — Saves the namespace in a shell variable called `ns`, so every later line can say `-n $ns`. Point it at another namespace and the whole loop follows.
- `get all -o wide` — Lists the namespace's Pods, Services, Deployments and ReplicaSets in one go. Read STATUS, READY, RESTARTS and NODE first. `all` leaves out ConfigMaps, Secrets, PVCs and Ingresses, so ask for those by name when the task mentions them.
- `get events --sort-by=.lastTimestamp` — Every event in the namespace, oldest first, so `tail -20` keeps the 20 newest. The comment shows the newer `kubectl events` command, where `--types=Warning` hides the routine events and leaves only the problems.
- `describe pod <pod>` — Replace `` with the Pod's name. `tail -25` keeps the last 25 lines, which is where describe puts the Events, the part that usually states the cause.
- `logs <pod> [-c <container>]` — Square brackets mark optional parts; do not type them. Add `-c` to choose a container in a multi-container Pod, and `--previous` to read the instance that ran before the current one.
- `exec <pod> -- env` — Runs `env` inside the running container and prints the environment variables it really has. Everything after `--` is the command for the container, not a kubectl flag.
- `kubectl get nodes -o wide` — No `-n` here: nodes belong to no namespace. A NotReady node means the Pod is only a symptom and the real problem is the node.
- `kubectl -n kube-system get pods` — The cluster's own components live in `kube-system`: API server, scheduler, controller-manager, etcd, CoreDNS and the network plugin. One that is not Running explains failures that no change to the app can fix.

</details>

## What each status tells you

Stop at the first step that names a cause. The exam breaks one thing per task, so hunting for a second problem only costs time. Often step 2 is enough, because the STATUS column already says where to look:

| STATUS you see | Where the cause is written |
| --- | --- |
| Pending, NODE  | `describe pod` → Events: *FailedScheduling* says why each node said no |
| ContainerCreating, for minutes | `describe pod` → Events: *FailedMount* names the missing ConfigMap, Secret or PVC |
| ErrImagePull, ImagePullBackOff | `describe pod` → Events: the image name it tried and the registry's answer |
| CreateContainerConfigError | `describe pod` → Events: the ConfigMap or Secret key it could not find |
| CrashLoopBackOff, Error | `logs`, then `describe pod` → Last State: Exit Code |
| OOMKilled | `describe pod` → Last State: Reason OOMKilled. Compare it with the memory limit |
| Init:Error, Init:CrashLoopBackOff | `logs  -c ` |
| Running, but READY 0/1 | `describe pod` → Events: *Readiness probe failed* |
| Unknown, or Terminating for minutes | `kubectl get nodes`: the Pod's node is probably NotReady |

The next lesson, [Application failures](/cka/troubleshooting/application-failures), explains each of these statuses with an example.

## Reading describe from the bottom

`kubectl describe pod` prints the settings first and the useful part last. So read it from the bottom up:

1. **Events.** The From column says who complained: the scheduler or the kubelet. The Message is usually the cause, in plain words.
2. **State and Last State** of each container, with its Reason and Exit Code.
3. **Conditions.** `PodScheduled` False: no node yet. `Initialized` False: an init container has not finished. `ContainersReady` False: a probe fails or a container crashed.

Events are kept for only one hour. If the Pod broke *yesterday*, its events may be gone, but Last State and the logs are still there. To see only the problems in a whole namespace, run `kubectl -n  events --types=Warning`.

## Fix with a command, not an editor

`kubectl edit` is fine when you know the exact field. But it has two traps:

- You can save YAML with a wrong indent, then lose a minute reading the error.
- On a bare Pod most fields are locked, so the save is refused anyway.

So prefer a command that changes one field and nothing else. The grader reads only the result. It does not care how you got there.

**One-line fixes for the common causes**

```bash
kubectl -n $ns set image deploy/web nginx=nginx:1.27
kubectl -n $ns set resources deploy/web -c nginx --limits=memory=256Mi --requests=memory=128Mi
kubectl -n $ns patch deploy web -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"cka-worker"}}}}}'
kubectl -n $ns patch deploy web --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80}]'

# A bare Pod with a wrong command, env, volume or probe cannot be patched in place: export, fix, recreate.
kubectl -n $ns get pod app -o yaml > app.yaml
vim app.yaml
kubectl -n $ns replace --force -f app.yaml      # add --grace-period=0 if the old Pod takes 30s to die
```

<details>
<summary>Line-by-line explanation</summary>

- `set image deploy/web` — Changes the image of the container called `nginx`: the part before `=` is the container's name, not the image. The Deployment then rolls out new Pods.
- `set resources deploy/web` — Sets the memory request and limit of container `nginx`. The **request** is what the scheduler reserves on a node; the **limit** is the most the container may use before it is OOMKilled.
- `patch deploy web -p` — A strategic merge patch, the default kind: you write only the path down to the field you change, as JSON, and the rest stays. This one sets the template's nodeSelector so new Pods must run on `cka-worker`.
- `--type=json` — A JSON patch names an operation and an exact path. `containers/0` is the first container, so this replaces its liveness probe's port with 80. Handy for one field deep inside a list.
- `get pod app -o yaml > app.yaml` — Saves the live Pod to a file. It also holds `status` and fields the server filled in; you can leave them, `replace --force` copes with them.
- `vim app.yaml` — Fix the one wrong field, then save and quit with `:wq`.
- `replace --force -f app.yaml` — Deletes the Pod and creates it again from the file in a single command, the only way to change fields a running Pod refuses. `--grace-period=0` skips the wait for the old process to stop.

</details>

Most fields of a running Pod are locked. You can change its image, but a normal edit cannot change the command, args, env, volumes, probes, nodeSelector or resources. For those, save the Pod to a file, fix it, and recreate it with `replace --force`, as the last three lines above do.

When the Pod belongs to a Deployment, never fix the Pod. Change the Deployment's template, and the rollout replaces the Pods for you:

**Fix the owner, not the Pod**

*The ReplicaSet builds new Pods from the Deployment's template. A fix you make on one of its Pods is lost as soon as that Pod is replaced.*

`Deployment` — fix the template here → `ReplicaSet` — makes Pods from the template → `Pod` — a fix made here does not last

## Worked example: a Deployment that never comes up

The question says: *Deployment report in namespace ts-method has no available Pods. Fix it.* Here are steps 2 and 3 of the loop, cut to the lines that matter:

**get, then describe the Pod and read its last event**

```text
$ kubectl -n ts-method get deploy,pods -o wide
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/report   0/1     1            0           2m
NAME                          READY   STATUS    RESTARTS   AGE   IP       NODE
pod/report-677544647f-9m7nq   0/1     Pending   0          2m    <none>   <none>

$ kubectl -n ts-method describe pod report-677544647f-9m7nq | tail -2
  Type     Reason            Age   From               Message
  Warning  FailedScheduling  2m    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient memory. no new claims to deallocate, preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

<details>
<summary>Line-by-line explanation</summary>

- `get deploy,pods -o wide` — The `$` marks a command you type; the lines below it are its output. `deploy,pods` lists two kinds of object in one call.
- `deployment.apps/report` — READY 0/1 and AVAILABLE 0: the Deployment wants one Pod and has none working. UP-TO-DATE 1 says the Pod already uses the current template, so look at that Pod next.
- `pod/report-677544647f-9m7nq` — A Deployment's Pod is named after the Deployment, the ReplicaSet's hash and a random suffix. Pending with NODE `` means the scheduler has not placed it.
- `describe pod report-677544647f-9m7nq | tail -2` — Only the last two lines of describe: the heading of the Events table and the newest event.
- `FailedScheduling` — From `default-scheduler`: the scheduler is running and said no. It counts nodes per reason: one rejected for its taint (the control plane), two for memory. The preemption part says evicting other Pods would not help either.

</details>

NODE is ``, so the scheduler never placed the Pod. The event says why, node by node:

- The control plane said no because of its taint. That is normal: the taint keeps ordinary Pods off it.
- The two workers said no because of memory: *Insufficient memory*.

So the Pod asks for more memory than any worker has. Check the request, fix it with one command, and prove the result:

**Confirm, fix, verify**

```bash
kubectl -n ts-method get deploy report -o jsonpath='{.spec.template.spec.containers[0].resources}'
# {"requests":{"memory":"64Gi"}}
kubectl describe node cka-worker | grep -A6 '^Allocatable'

kubectl -n ts-method set resources deploy report --requests=memory=64Mi
kubectl -n ts-method rollout status deploy/report --timeout=60s
kubectl -n ts-method get pods -o wide        # Running, 1/1, a NODE name
```

<details>
<summary>Line-by-line explanation</summary>

- `containers[0].resources` — Prints only the `resources` of the first container in the Deployment's Pod template. The comment below is the output: a request for 64Gi of memory, far more than any lab node has.
- `grep -A6 '^Allocatable'` — Shows the node's **Allocatable** block: the CPU, memory and Pod count the scheduler can hand out. `-A6` prints the matching line and the 6 after it; `^` means the line must start with the word.
- `set resources deploy report` — Lowers the memory request to 64Mi; with no `-c` it applies to every container. The template changed, so the Deployment creates a new Pod, and this one fits on a worker.
- `rollout status deploy/report` — Waits until the new Pod is available, or gives up after 60 seconds. *successfully rolled out* means the fix worked.
- `get pods -o wide` — The proof: Running, READY 1/1 and a real node name, the state the grader checks.

</details>

That is three commands to find the cause, one to fix it and one to prove it. Note who decides the right value: the question. If it had said *the app needs 2Gi*, you would set 2Gi. The events only tell you what is wrong.

> [!IMPORTANT] **What the grader reads, and two ways to lose the points anyway**
> The grader checks only the final state: the Deployment's `status.availableReplicas`, the Pod's phase and readiness, or a file's contents. It cannot see your commands. You can still lose the points in two ways. You fix the wrong object, such as a Pod its ReplicaSet will replace. Or you leave before the state settles. End every task with a `get` that shows the state the question asked for.

## 📝 Key Takeaways

- Run the same loop every time: get, describe, logs, then fix and get again.
- Read `describe` from the bottom. The Events usually name the cause in plain words.
- The STATUS tells you where to look. Pending: read the scheduling events. ImagePullBackOff: check the image name. CrashLoopBackOff: read the logs.
- Fix the owner, not the Pod: change the Deployment's template. A bare Pod's command or env needs `replace --force`.
- Stop at the first cause you find, and finish with a `get` that proves the end state.

**📖 Official documentation:**

- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) *(search: "debug pods")*
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/) *(search: "debug running pod")*
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) *(search: "pod lifecycle container states")*
- [kubectl Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) *(search: "kubectl quick reference")*

---

### 🎯 Task: A Deployment with no ready Pods

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

The Deployment `web` in namespace `ts-method` is supposed to serve nginx 1.27 but has had no ready Pods since it was created. Find out why and fix it. When you are done, both replicas must be Running and Ready and the Deployment must use the image `nginx:1.27`.

<details>
<summary>💡 Hints</summary>

- Step 2 of the loop: the STATUS column of the Pods points at the image, not at the app.
- describe one Pod and read the last event. It quotes the exact image name the runtime tried to pull.
- kubectl set image deploy/web =nginx:1.27, then kubectl rollout status.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-method get pods -l app=web -o wide
kubectl -n ts-method describe pod -l app=web | tail -8
kubectl -n ts-method set image deploy/web nginx=nginx:1.27
kubectl -n ts-method rollout status deploy/web --timeout=180s
kubectl -n ts-method get deploy web -o wide
```

**Explanation:**

- `get pods -l app=web -o wide` — Lists the Deployment's Pods by label: `kubectl create deployment web` labels them `app=web`. STATUS reads `ErrImagePull` or `ImagePullBackOff`, which points at the image.
- `describe pod -l app=web | tail -8` — Describes every Pod with that label and keeps the last 8 lines: the events quote the reference the runtime tried, `nginx:1.72`, and the registry's answer, *not found*.
- `set image deploy/web nginx=nginx:1.27` — Fixes the tag in the Deployment's template, not in the Pods. The container is called `nginx` because `create deployment` names it after the image.
- `rollout status deploy/web` — Waits for both new Pods to become available, allowing up to 180 seconds for the image pull. The broken Pods are removed as part of the rollout.
- `get deploy web -o wide` — `-o wide` adds the IMAGES column, so one line shows READY 2/2 and `nginx:1.27`: both things the task asks for.

**Notes:** The Pods show `ErrImagePull` or `ImagePullBackOff`. While the registry is slow, they may sit in `ContainerCreating` with a *Pulling image "nginx:1.72"* event. The event quotes `docker.io/library/nginx:1.72: not found`: two digits of the tag are swapped. The container is called `nginx` because `kubectl create deployment --image=nginx:…` names it after the image. If unsure, check with `kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].name}'`. `kubectl edit deploy web` and changing the image line works too. It creates the same new ReplicaSet.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-method
d="kubectl -n $ns get deploy web -o jsonpath"

kubectl -n $ns get deploy web >/dev/null 2>&1 && p "deployment web exists" || f "deployment web exists"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image is nginx:1.27" || f "image is nginx:1.27"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "replicas = 2" || f "replicas = 2"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
bad=$(kubectl -n $ns get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.status.phase}|{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | awk -F'|' '$1=="" && ($2!="Running" || $3!="true")' | wc -l | tr -d ' ')
[ "$bad" = "0" ] && p "every pod Running and Ready" || f "every pod Running and Ready"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Pod waiting on configuration that is not there

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

The Pod `app` in namespace `ts-method` has not started. It reads its settings from the ConfigMap `app-config`, which the application team has confirmed is correct and must not be modified. Make the Pod Running and Ready without changing the ConfigMap.

<details>
<summary>💡 Hints</summary>

- The STATUS is neither Pending nor CrashLoopBackOff. The last event names the key it could not find, and the ConfigMap it looked in.
- Compare the key in the Pod's env with kubectl get cm app-config -o yaml. Upper and lower case matter.
- env cannot be changed on a running Pod. Export it with -o yaml, fix the key, then kubectl replace --force -f.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n ts-method describe pod app | tail -6
kubectl -n ts-method get cm app-config -o jsonpath='{.data}'; echo
kubectl -n ts-method get pod app -o yaml > /tmp/cka/app-broken.yaml
kubectl -n ts-method replace --force -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: ts-method
  labels:
    app: app
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo mode=$APP_MODE level=$LOG_LEVEL; sleep 3600"]
      env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_MODE
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
YAML
kubectl -n ts-method wait --for=condition=Ready pod/app --timeout=90s
```

**Explanation:**

- `mkdir -p /tmp/cka` — Makes sure the folder for the backup copy exists. `-p` means no error if it is already there.
- `describe pod app | tail -6` — The last events explain the `CreateContainerConfigError`: *couldn't find key app_mode in ConfigMap ts-method/app-config*.
- `get cm app-config -o jsonpath='{.data}'` — Prints the ConfigMap's keys and values as JSON: the key is `APP_MODE`, in capitals. `; echo` adds the line break jsonpath leaves out, so your prompt does not end up on the same line.
- `-o yaml > /tmp/cka/app-broken.yaml` — Keeps a copy of the broken Pod before replacing it. On the exam you would fix this file in vim instead of typing the YAML again.
- `replace --force -f - <<'YAML'` — Deletes the Pod and recreates it from the YAML below, up to the line `YAML`. `-f -` reads that heredoc; quoting `'YAML'` stops the shell from replacing `$APP_MODE` before kubectl sees it.
- `apiVersion: v1` — Every manifest starts with an API version and a kind. Pods belong to the core API group, so the version is just `v1`.
- `metadata:` — Same name, namespace and label as the original, so the new Pod takes the old one's place.
- `command:` — A shell that prints both variables and then sleeps for an hour, which keeps the container running. The shell fills in `$APP_MODE` from the container's environment.
- `env:` — Each entry defines one environment variable. `valueFrom.configMapKeyRef` takes the value from a key in a ConfigMap instead of writing it here.
- `key: APP_MODE` — The fix. ConfigMap keys are case-sensitive, and `app_mode` does not exist, which is what kept the container from being created.
- `wait --for=condition=Ready pod/app` — Waits until the new Pod is Ready, or fails after 90 seconds.

**Notes:** The Pod sits in `CreateContainerConfigError`. The event reads *couldn't find key app_mode in ConfigMap ts-method/app-config*. The ConfigMap has `APP_MODE`, in capitals, but the Pod asks for `app_mode`. On the exam: run `kubectl get pod app -o yaml > app.yaml`, fix `key: app_mode` in vim, then run `kubectl replace --force -f app.yaml`. The exported file also holds status and fields the server filled in. That is fine: `replace --force` deletes the Pod, creates it again and ignores them. Adding an `app_mode` key to the ConfigMap would also start the Pod. But the question forbids touching it, and the grader checks.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-method

kubectl -n $ns get pod app >/dev/null 2>&1 && p "pod app exists" || f "pod app exists"
[ "$(kubectl -n $ns get pod app -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
[ "$(kubectl -n $ns get pod app -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && p "container Ready" || f "container Ready"
[ "$(kubectl -n $ns exec app -- sh -c 'echo $APP_MODE' 2>/dev/null)" = "production" ] && p "APP_MODE resolves to production inside the container" || f "APP_MODE resolves to production inside the container"
[ "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.APP_MODE}' 2>/dev/null)" = "production" ] && p "ConfigMap unchanged (APP_MODE=production)" || f "ConfigMap unchanged (APP_MODE=production)"
[ -z "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.app_mode}' 2>/dev/null)" ] && p "ConfigMap has no added app_mode key" || f "ConfigMap has no added app_mode key"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
