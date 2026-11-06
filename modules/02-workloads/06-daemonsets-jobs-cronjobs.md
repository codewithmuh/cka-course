# DaemonSets, Jobs and CronJobs

> **Module 2** · Lesson 2.6 · 40 minutes

Three controllers beyond Deployments: DaemonSets run one Pod on each node, Jobs run work that finishes, and CronJobs run Jobs on a schedule.

## Learning Objectives

- You can write a DaemonSet from a Deployment skeleton, and decide whether it should tolerate the control-plane taint.
- You can size a Job with completions, parallelism, backoffLimit and activeDeadlineSeconds, and confirm it from .status.succeeded.
- You can schedule a CronJob with the right concurrencyPolicy and history limits, and start it by hand with kubectl create job --from.


A Deployment keeps a set number of Pods running forever. That fits a web app, but not every kind of work. Kubernetes has a controller for each shape:

**Three shapes of work**

`DaemonSet` — one Pod on every node   `Job` — runs until the work is done   `CronJob` — starts a Job on a schedule

| Controller | What it runs | Example |
| --- | --- | --- |
| Deployment | A set number of Pods, forever | Your Django web app |
| DaemonSet | One Pod on each node | A log collector that reads every node's logs |
| Job | Pods until enough of them succeed, then stops | A one-off database migration |
| CronJob | A new Job each time the schedule comes round | A report every night at 02:30 |

kubectl can generate Jobs and CronJobs, but not DaemonSets. So this lesson also shows the fastest way to write a DaemonSet by hand.

## DaemonSets: one Pod per node

A **DaemonSet** runs one copy of its Pod on every node that its rules allow. When a node joins the cluster, the DaemonSet adds a Pod there. When a node leaves, its Pod goes too. That is how network agents, kube-proxy and log collectors end up on every node.

The normal scheduler places these Pods, so taints still apply:

- The control plane has a NoSchedule taint. A DaemonSet adds a few tolerations by itself, but **not** one for this taint.
- So by default, a DaemonSet runs only on the worker nodes: 2 Pods on this lab.
- To cover every node, control plane included, write the control-plane toleration into the Pod template.

There is no `kubectl create daemonset`. Instead, generate a Deployment and turn it into a DaemonSet:

**There is no kubectl create daemonset; convert a Deployment**

```bash
kubectl -n wl-batch create deployment node-agent --image=registry.k8s.io/pause:3.10 --dry-run=client -o yaml \
  | sed -e 's/^kind: Deployment/kind: DaemonSet/' -e '/^  replicas:/d' -e '/^  strategy:/d' -e '/^status:/d' > ds.yaml
kubectl apply -f ds.yaml
kubectl -n wl-batch get ds node-agent        # DESIRED CURRENT READY per eligible node
kubectl -n wl-batch get pods -l app=node-agent -o wide
```

<details>
<summary>Line-by-line explanation</summary>

- `create deployment node-agent` — Generates a Deployment, which kubectl can do, as raw material. `pause` is a tiny image that only sleeps. The `\` at the end continues the command on the next line.
- `| sed` — `sed` edits the YAML on its way through. `s/old/new/` renames the kind, and each `/pattern/d` deletes the replicas, strategy or status line: fields a DaemonSet does not have.
- `kubectl apply -f ds.yaml` — Creates the DaemonSet: one Pod on each node that its rules and the node taints allow.
- `get ds node-agent` — DESIRED is the number of eligible nodes. With the control-plane taint and no toleration, that is 2 on this lab, one per worker.
- `-o wide` — The NODE column should list each worker once.

</details>

Here is a full DaemonSet. Keep the `tolerations` block to include the control plane, or remove it to stay on the workers:

**Every node including the control plane, or only some nodes**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  namespace: wl-batch
spec:
  selector:
    matchLabels:
      app: log-agent
  updateStrategy:
    type: RollingUpdate       # default, one node at a time; OnDelete waits for you to delete Pods
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:            # remove this block to stay off the control plane
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      # nodeSelector:         # or restrict to labeled nodes
      #   pool: logging
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "while true; do sleep 3600; done"]
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: DaemonSet` — Same `apps/v1` group and nearly the same shape as a Deployment, but there is no `replicas`: the number of eligible nodes sets the Pod count.
- `selector:` — As in a Deployment, `matchLabels` must match the template's labels.
- `updateStrategy:` — DaemonSets call this field `updateStrategy`; Deployments call theirs `strategy`.
- `tolerations:` — Lets the Pods onto the control plane despite its NoSchedule taint, so this DaemonSet covers all three nodes.
- `command:` — Keeps the container running forever. A DaemonSet's Pods must use `restartPolicy: Always`, so a container that exits is restarted.

</details>

## Jobs: run until enough Pods succeed

A **Job** runs Pods until a set number of them succeed, then stops. Example: a database migration for your Django app. It must run, finish, and not start again.

**The fields that shape a Job**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: resize-images
  namespace: wl-batch
spec:
  completions: 6                 # successful Pods needed (default 1)
  parallelism: 2                 # Pods running at once (default 1)
  backoffLimit: 3                # failed retries before the Job fails (default 6)
  activeDeadlineSeconds: 300     # hard wall-clock limit, beats backoffLimit
  ttlSecondsAfterFinished: 600   # delete the Job and its Pods 10 min after it ends
  template:
    spec:
      restartPolicy: Never       # Never or OnFailure; Always is rejected
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sh", "-c", "echo resizing; sleep 3"]
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: Job` — Jobs live in the `batch` API group. A Job runs Pods until enough of them exit successfully, then stops.
- `completions: 6` — Together with `parallelism: 2` on the next line: six successes needed, two Pods at a time.
- `activeDeadlineSeconds: 300` — Counted from the Job's start. After 300 seconds its running Pods are stopped, and the Job fails with reason DeadlineExceeded, even if retries remain.
- `ttlSecondsAfterFinished` — Without it, finished Jobs and their Pods stay until you delete them.
- `template:` — The Pod template, as in a Deployment, but without labels or a selector: the Job controller adds both itself.

</details>

A Job's Pods must use `restartPolicy: Never` or `OnFailure`. The two differ in what happens after a failure:

| restartPolicy | After a failure |
| --- | --- |
| `Never` | The failed Pod stays, which is handy for `kubectl logs`. The Job creates a new Pod. |
| `OnFailure` | The container restarts inside the same Pod. |

- Either way, each retry counts toward `backoffLimit`, and the wait between retries grows.
- A Job ends with the condition `Complete`, or with `Failed` and a reason: `BackoffLimitExceeded` or `DeadlineExceeded`.
- A Job's Pod template cannot be changed. To change a Job, delete it and create it again.

Create a Job, wait for it, then check it:

**Create, wait, inspect**

```bash
kubectl -n wl-batch create job once --image=busybox:1.36 -- sh -c 'echo done'   # writes restartPolicy: Never
kubectl -n wl-batch create job once --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo done' > job.yaml   # then add completions etc.
kubectl -n wl-batch wait --for=condition=complete job/once --timeout=120s
kubectl -n wl-batch get job once -o jsonpath='{.status.succeeded}/{.spec.completions}'; echo
kubectl -n wl-batch logs job/once
kubectl -n wl-batch get pods -l job-name=once
```

<details>
<summary>Line-by-line explanation</summary>

- `create job once --image=busybox:1.36 -- sh` — Creates the Job and starts it at once. Everything after `--` is the container's command.
- `--dry-run=client` — The same Job saved to a file instead, because `create job` has no flags for completions, parallelism or limits.
- `wait --for=condition=complete` — Blocks until the Job is Complete, or gives up after 120 seconds. A failed Job never completes, so a timeout means: look at its Pods.
- `{.status.succeeded}/{.spec.completions}` — Prints succeeded against required, for example `1/1`: two fields in one jsonpath, with a slash between them.
- `logs job/once` — Prints the logs of one of the Job's Pods without looking up its name.
- `job-name=once` — The Job controller labels its Pods with `job-name`, so this lists every Pod it created, failed attempts included.

</details>

## CronJobs: Jobs on a schedule

A **CronJob** creates a new Job each time its schedule comes round. Example: a report that your app emails every night at 02:30.

**What a CronJob creates**

*Each level has its own spec, so the Pod template sits deep inside the CronJob: `jobTemplate.spec.template.spec`.*

`CronJob` — holds the schedule (`30 2 * * *`) → `Job` — one per run → `Pod` — does the work, then exits

**A CronJob with its guardrails**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-report
  namespace: wl-batch
spec:
  schedule: "30 2 * * *"           # minute hour day-of-month month day-of-week
  concurrencyPolicy: Forbid        # Allow (default) | Forbid | Replace
  successfulJobsHistoryLimit: 3    # default 3
  failedJobsHistoryLimit: 1        # default 1
  suspend: false
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: report
              image: busybox:1.36
              command: ["sh", "-c", "date; echo report done"]
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: CronJob` — A CronJob creates a new Job from `jobTemplate` each time the schedule fires. It also lives in `batch/v1`.
- `schedule:` — Five fields, as the comment lists: this one is 02:30 every day. Always quote the value. Cron strings often start with `*`, which YAML would misread.
- `suspend: false` — Set it to true to pause the schedule without deleting anything. Jobs already running carry on.
- `jobTemplate:` — Under it is a Job spec, so the Pod template sits one level deeper than in a Job: `jobTemplate.spec.template.spec`.
- `restartPolicy: OnFailure` — A failed container restarts inside the same Pod. Each restart still counts toward `backoffLimit`.

</details>

The schedule uses the five classic cron fields: minute, hour, day of month, month and day of week. Some common ones:

| Schedule | Means |
| --- | --- |
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour, on the hour |
| `0 9 * * 1-5` | 09:00 on weekdays |
| `30 2 * * *` | 02:30 every day |

What if a run is due while the last one is still going? `concurrencyPolicy` decides:

| concurrencyPolicy | The next run is due, but the last one is still running |
| --- | --- |
| `Allow` (default) | Start another Job. Runs may overlap |
| `Forbid` | Skip this run. The running Job carries on |
| `Replace` | Delete the running Job and start the new one |

To test a CronJob without waiting, run `kubectl create job NAME --from=cronjob/CRON`. It copies the job template and records the CronJob as the owner, so the history limits count it too.

Apps that need a fixed name and their own disk, such as a database, use a **StatefulSet**, taught in [StatefulSets and volumeClaimTemplates](/cka/storage/statefulsets-and-storage).

> [!IMPORTANT] **What the grader reads**
> For Jobs, the grader reads `spec.completions`, `spec.parallelism`, `spec.backoffLimit` and `status.succeeded`. So wait for the Job to finish before you move on. For CronJobs, it reads `spec.schedule` as an exact string, `concurrencyPolicy` and the history limits. Those are easy to miss, because `kubectl create cronjob` has no flags for them. For DaemonSets, it checks that `desiredNumberScheduled` equals `numberReady`, on the nodes the task named.

## 📝 Key Takeaways

- A DaemonSet runs one Pod on each node its rules allow. It stays off the control plane unless you add the control-plane toleration.
- There is no `kubectl create daemonset`. Generate a Deployment, change the kind, and delete `replicas`, `strategy` and `status`.
- A Job runs Pods until `completions` succeed, `parallelism` at a time. `backoffLimit` caps the retries, and `activeDeadlineSeconds` caps the time.
- A CronJob creates a Job on each run. `concurrencyPolicy` and the history limits sit under `spec`, beside `schedule`.
- Test a CronJob right away with `kubectl create job NAME --from=cronjob/CRON`.

**📖 Official documentation:**

- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) *(search: "daemonset")*
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) *(search: "job completions parallelism")*
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) *(search: "cronjob concurrency policy")*

---

### 🎯 Task: Run an agent on every worker node

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `wl-batch` create a DaemonSet `node-agent` that runs exactly one Pod (image `registry.k8s.io/pause:3.10`, Pod label `app=node-agent`) on each worker node and none on the control plane. Each container requests `10m` CPU and `16Mi` memory.

<details>
<summary>💡 Hints</summary>

- Generate a Deployment with `--dry-run=client -o yaml`. Change the kind to DaemonSet, then delete `replicas`, `strategy` and `status`.
- The control-plane taint already keeps the Pods off `cka-control-plane`. Do not add a toleration for it.
- If a worker gets no Pod, run `kubectl describe nodes | grep Taints` and look for a taint left over from an earlier task.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: wl-batch
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
        - name: agent
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
YAML
kubectl -n wl-batch rollout status ds/node-agent --timeout=120s
```

**Explanation:**

- `kind: DaemonSet` — One Pod per eligible node. No toleration is added, so the control-plane taint keeps it off cka-control-plane, as the question wants.
- `image: registry.k8s.io/pause:3.10` — pause does nothing but sleep, which makes it a perfect placeholder agent.
- `requests:` — 10m CPU and 16Mi memory per container, exactly as asked.
- `rollout status ds/node-agent` — `rollout status` works for DaemonSets too: it waits until every eligible node runs an up-to-date, ready Pod.

**Notes:** The `sed` conversion shown above gives you the skeleton in one line. Then add the `resources` block. `kubectl rollout status ds/node-agent` works for DaemonSets too. If the task had said *every node*, you would add the control-plane toleration and expect 3 Pods.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-batch
d="kubectl -n $ns get ds node-agent -o jsonpath"

kubectl -n $ns get ds node-agent >/dev/null 2>&1 && p "daemonset node-agent exists" || f "daemonset node-agent exists"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "registry.k8s.io/pause:3.10" ] && p "image pause:3.10" || f "image pause:3.10"
[ "$($d='{.spec.template.metadata.labels.app}' 2>/dev/null)" = "node-agent" ] && p "pod label app=node-agent" || f "pod label app=node-agent"
[ "$($d='{.spec.template.spec.containers[0].resources.requests.cpu}/{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)" = "10m/16Mi" ] && p "requests 10m/16Mi" || f "requests 10m/16Mi"
[ "$($d='{.status.desiredNumberScheduled}/{.status.numberReady}' 2>/dev/null)" = "2/2" ] && p "2 desired, 2 ready" || f "2 desired, 2 ready"
nodes="$(kubectl -n $ns get pods -l app=node-agent -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}' 2>/dev/null)"
[ "$(echo $nodes | xargs -n1 | sort | xargs)" = "cka-worker cka-worker2" ] && p "one pod on each worker, none on the control plane" || f "one pod on each worker, none on the control plane"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Job that must succeed three times, one at a time

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `wl-batch` create a Job `process-items` using image `busybox:1.36` that runs `sh -c 'echo processing; sleep 2'`. The Job must finish after 3 successful Pods, run only one Pod at a time, retry a failure at most 2 times, never restart a failed container in place, and be stopped if it runs longer than 120 seconds. Wait until it has completed.

<details>
<summary>💡 Hints</summary>

- `kubectl create job process-items --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo processing; sleep 2'`
- You need `completions: 3`, `parallelism: 1`, `backoffLimit: 2`, `activeDeadlineSeconds: 120` and `restartPolicy: Never`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: process-items
  namespace: wl-batch
spec:
  completions: 3
  parallelism: 1
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: process-items
          image: busybox:1.36
          command: ["sh", "-c", "echo processing; sleep 2"]
YAML
kubectl -n wl-batch wait --for=condition=complete job/process-items --timeout=150s
```

**Explanation:**

- `completions: 3` — Three successful Pods finish the Job.
- `parallelism: 1` — One Pod at a time, so the three run one after another.
- `backoffLimit: 2` — At most 2 retries after failures before the Job is marked Failed.
- `activeDeadlineSeconds: 120` — Stops the whole Job if it runs longer than 120 seconds, however many retries are left.
- `restartPolicy: Never` — "Never restart a failed container in place": the container is not restarted, and the Job creates a new Pod instead.
- `wait --for=condition=complete` — Waits for Complete, a little longer than the Job's own 120-second deadline.

**Notes:** `kubectl create job` has no flags for completions or limits. So generate the YAML, then add the four `spec` fields above `template`. *Never restart in place* means `restartPolicy: Never`. Watch it with `kubectl get pods -l job-name=process-items -w`: you should see three Pods complete, one after another.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-batch
j="kubectl -n $ns get job process-items -o jsonpath"

kubectl -n $ns get job process-items >/dev/null 2>&1 && p "job process-items exists" || f "job process-items exists"
[ "$($j='{.spec.completions}/{.spec.parallelism}' 2>/dev/null)" = "3/1" ] && p "completions 3, parallelism 1" || f "completions 3, parallelism 1"
[ "$($j='{.spec.backoffLimit}' 2>/dev/null)" = "2" ] && p "backoffLimit 2" || f "backoffLimit 2"
[ "$($j='{.spec.activeDeadlineSeconds}' 2>/dev/null)" = "120" ] && p "activeDeadlineSeconds 120" || f "activeDeadlineSeconds 120"
[ "$($j='{.spec.template.spec.restartPolicy}' 2>/dev/null)" = "Never" ] && p "restartPolicy Never" || f "restartPolicy Never"
[ "$($j='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image busybox:1.36" || f "image busybox:1.36"
[ "$($j='{.status.succeeded}' 2>/dev/null)" = "3" ] && p "status.succeeded = 3" || f "status.succeeded = 3"
[ "$($j='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)" = "True" ] && p "job Complete" || f "job Complete"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Schedule a CronJob and run it once by hand

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

In namespace `wl-batch` create a CronJob `heartbeat` that runs every 5 minutes with image `busybox:1.36` and command `sh -c 'date; echo alive'`. A new run must never start while the previous one is still running. Keep the last 2 successful Jobs and the last 1 failed Job. Then, without waiting for the schedule, start a Job named `heartbeat-manual` from this CronJob and make sure it succeeds.

<details>
<summary>💡 Hints</summary>

- `kubectl create cronjob heartbeat --image=busybox:1.36 --schedule="*/5 * * * *" --dry-run=client -o yaml -- sh -c 'date; echo alive'`
- Add `concurrencyPolicy: Forbid`, `successfulJobsHistoryLimit: 2` and `failedJobsHistoryLimit: 1`. Then run `kubectl create job heartbeat-manual --from=cronjob/heartbeat`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: heartbeat
  namespace: wl-batch
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: heartbeat
              image: busybox:1.36
              command: ["sh", "-c", "date; echo alive"]
YAML
kubectl -n wl-batch create job heartbeat-manual --from=cronjob/heartbeat
kubectl -n wl-batch wait --for=condition=complete job/heartbeat-manual --timeout=120s
```

**Explanation:**

- `schedule: "*/5 * * * *"` — Every 5 minutes: `*/5` in the minute field means every minute divisible by 5. The quotes are needed because the value starts with `*`.
- `concurrencyPolicy: Forbid` — A run that comes due while the previous one is still going is skipped.
- `successfulJobsHistoryLimit: 2` — Keep the last 2 successful Jobs and, on the next line, 1 failed one; older Jobs are deleted. Both sit under `spec`, beside `schedule`.
- `jobTemplate:` — The Job each run creates. Its Pod template is under `jobTemplate.spec.template`.
- `--from=cronjob/heartbeat` — Starts a Job right now from the CronJob's `jobTemplate`, without waiting for the schedule. The CronJob is recorded as its owner.
- `wait --for=condition=complete` — Waits for the manual Job to succeed.

**Notes:** Quote the schedule on the command line, or the shell expands the asterisks. The policy and history fields go directly under `spec`, next to `schedule`, not inside `jobTemplate`. The manual Job gets an owner reference to `heartbeat` and the annotation `cronjob.kubernetes.io/instantiate: manual`. Deleting the CronJob deletes it too.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-batch
c="kubectl -n $ns get cronjob heartbeat -o jsonpath"
j="kubectl -n $ns get job heartbeat-manual -o jsonpath"

kubectl -n $ns get cronjob heartbeat >/dev/null 2>&1 && p "cronjob heartbeat exists" || f "cronjob heartbeat exists"
[ "$($c='{.spec.schedule}' 2>/dev/null)" = "*/5 * * * *" ] && p "schedule */5 * * * *" || f "schedule */5 * * * *"
[ "$($c='{.spec.concurrencyPolicy}' 2>/dev/null)" = "Forbid" ] && p "concurrencyPolicy Forbid" || f "concurrencyPolicy Forbid"
[ "$($c='{.spec.successfulJobsHistoryLimit}/{.spec.failedJobsHistoryLimit}' 2>/dev/null)" = "2/1" ] && p "history limits 2 successful, 1 failed" || f "history limits 2 successful, 1 failed"
[ "$($c='{.spec.jobTemplate.spec.template.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image busybox:1.36" || f "image busybox:1.36"
[ "$($j='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}' 2>/dev/null)" = "CronJob/heartbeat" ] && p "heartbeat-manual was created from the cronjob" || f "heartbeat-manual was created from the cronjob"
[ "$($j='{.status.succeeded}' 2>/dev/null)" = "1" ] && p "heartbeat-manual succeeded" || f "heartbeat-manual succeeded"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
