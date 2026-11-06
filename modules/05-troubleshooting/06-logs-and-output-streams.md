# Logs, events and container output streams

> **Module 5** · Lesson 5.6 · 40 minutes

Where a container's output goes, how to read exactly the lines you need, how to show a log file, and how events help.

## Learning Objectives

- You can read the logs of any container: one named container, the run before a crash, or every Pod with a label.
- You can find a container's log file on its node.
- You can add a native sidecar that prints an app's log file to stdout, without changing the app container.
- You can sort and filter events, and you know when to use describe and when to use get events.


This exam skill is called **Manage and evaluate container output streams**. The tasks are small and exact. Save one container's error lines to a file. Find the Pod that crashed with a given message. Make an app's log file readable with `kubectl logs`.

A container's log is everything its app prints. A program prints to two **output streams**: **stdout** for normal output and **stderr** for errors. The container runtime saves both streams into one file on the node. `kubectl logs` reads that file back for you.

**Where a container's log goes**

*A file the app writes inside its own container is not on this path, so kubectl logs never sees it.*

`Your app` — prints to stdout and stderr → `Container runtime` — saves both streams to one file → `Log file on the node` (`/var/log/pods/…`) → `kubectl logs` — asks the kubelet to read the file

## Reading logs with kubectl logs

**kubectl logs, every option you will use**

```bash
kubectl -n shop logs web-7d9c                      # the default container (see the trap below)
kubectl -n shop logs web-7d9c -c sidecar           # one named container (init containers too)
kubectl -n shop logs web-7d9c --all-containers     # every container, init containers included
kubectl -n shop logs web-7d9c --previous           # the instance before the current one (-p)
kubectl -n shop logs web-7d9c -f                   # follow; Ctrl-C to stop
kubectl -n shop logs web-7d9c --since=10m          # only recent lines (also --since-time=2026-10-17T09:00:00Z)
kubectl -n shop logs web-7d9c --tail=50            # last 50 lines
kubectl -n shop logs web-7d9c --timestamps         # prefix each line with the runtime's RFC3339 timestamp
kubectl -n shop logs -l app=web --prefix           # every Pod with the label; lines start [pod/<name>/<container>]
kubectl -n shop logs deploy/web                    # one Pod picked from the Deployment

# The typical exam shape: one container, one pattern, into a file
kubectl -n shop logs web-7d9c -c app | grep 'ERROR' > /tmp/cka/web-errors.txt
```

<details>
<summary>Line-by-line explanation</summary>

- `# the default container` — Prints everything the container has written to stdout and stderr since it started. `web-7d9c` stands for a real Pod name. With several containers you get the default one, and kubectl says which.
- `-c sidecar` — `-c` (`--container`) picks one container by name, init containers included. `kubectl describe pod` lists the names if you do not know them.
- `--all-containers` — Every container's log, one after another. Good for a first look. Add `--prefix` to see which container each line came from.
- `--previous` — The log of the container's last finished run. After a crash and restart, the error is usually here, while the current run shows only a fresh start. On a container that never restarted it returns an error instead.
- `web-7d9c -f` — `-f` (`--follow`) keeps the stream open and prints new lines as they arrive, like `tail -f`. Handy while you reproduce a problem.
- `--since=10m` — Only lines from the last 10 minutes. `s`, `m` and `h` work as units. `--since-time` takes an exact start time instead.
- `--tail=50` — Only the last 50 lines. The quickest look at a chatty app, since the newest lines are usually the interesting ones.
- `--timestamps` — Adds the time the runtime recorded each line, which helps you line logs up with events. Keep it out of any answer file.
- `-l app=web --prefix` — Logs of every Pod labeled `app=web`, each line marked with its Pod and container. With `-l` you get only the last 10 lines per Pod unless you set `--tail`.
- `deploy/web` — Given a Deployment, kubectl picks one of its Pods and shows that log, not every copy's. Use `-l` with the Pod labels to see all of them.
- `-c app | grep 'ERROR'` — Sends container `app`'s log through `grep`, which keeps only lines containing `ERROR`. `>` writes them to the file, replacing what was there. Quote the pattern so the shell leaves it alone.

</details>

- **Name the container.** In a Pod with several containers, `kubectl logs` without `-c` picks a default. That is the one named in the `kubectl.kubernetes.io/default-container` annotation, or else the first. It prints `Defaulted container "app" out of: …`. Always pass `-c` when the question names a container.
- **Labels cut the output.** With `-l`, you get only the last 10 lines of each Pod. Add `--tail=-1` when you need the full log.
- **The output is the answer.** When you write a file the grader compares, do not add `--timestamps` or `--prefix`. You also do not need `2>&1`: stderr lines are already in the container log.

## Which run do you see after a crash?

When a container crashes, the kubelet starts it again. That is a new *run*, with a new log. The kubelet keeps the current run and normally one run before it.

**Two runs of one container**

*Once the container is Running again, the crash output is only in --previous.*

`Run 1: crashed` — the kubelet keeps its log (`kubectl logs POD --previous`) → `Run 2: running now` — started by the restart (`kubectl logs POD`)

| The container… | Where the crash output is |
| --- | --- |
| Crashed and is waiting to restart (`CrashLoopBackOff`) | Plain `kubectl logs` shows the run that just died. |
| Crashed, restarted, and is Running again | Only in `kubectl logs --previous`. Plain logs show the fresh run. |
| Never restarted | There is no crash. `--previous` answers *previous terminated container not found*. |

If `--previous` answers *unable to retrieve container logs*, the old run is already gone. When you are unsure, run both commands. All of these logs disappear when the Pod is deleted.

## Where the logs live on the node

The log files sit on the node that runs the Pod. Each container has a folder: `/var/log/pods/__//`. The file name is the restart count: `0.log` for the first run, `1.log` after one restart. `/var/log/containers/` holds shortcuts (symlinks) to the same files.

**On the node (exam: ssh ; lab: docker exec -it cka-worker bash)**

```bash
kubectl -n shop get pod web-7d9c -o wide          # which node?
docker exec -it cka-worker bash

ls /var/log/pods/ | grep web-7d9c
tail -n 3 /var/log/pods/shop_web-7d9c_*/app/0.log
# 2026-10-17T10:35:46.709286291Z stderr F connection reset by peer
ls -l /var/log/containers/ | grep web-7d9c
```

<details>
<summary>Line-by-line explanation</summary>

- `# which node?` — Run this on your own machine first. The NODE column tells you which node holds this Pod's log files.
- `docker exec -it cka-worker bash` — On the lab each node is a Docker container, so this opens a root shell inside node `cka-worker`. `-it` makes it interactive. On the exam you `ssh` to the node instead.
- `ls /var/log/pods/ | grep web-7d9c` — Each Pod has a folder here named `__`, with one subfolder per container. grep picks out this Pod's folder.
- `tail -n 3` — Prints the last 3 lines of container `app`'s log file. The `*` fills in the Pod UID. `0.log` is the first run; after a restart the next run writes `1.log`.
- `stderr F` — A raw line: the timestamp, the stream it came from (`stdout` or `stderr`), `F` for a full line (`P` marks part of a long one), then the message. `kubectl logs` shows only the message.
- `ls -l /var/log/containers/` — This folder holds shortcuts (symlinks) to the files in `/var/log/pods`, and `-l` shows where each one points. Log collectors such as Fluent Bit read this folder.

</details>

When the API server is down, `kubectl logs` cannot work, but `crictl logs` on the node still can. [Control plane failures](/cka/troubleshooting/control-plane-failures) shows how.

## When the app writes to a file

Some apps write their log to a file instead of stdout. Then `kubectl logs` shows nothing. The fix is a helper container that reads the file and prints it to its own stdout.

The right helper is a **native sidecar**: an init container with `restartPolicy: Always`, which runs for the Pod's whole life. [Pods, init containers and sidecars](/cka/workloads/pods-and-multi-container) teaches it. Below is the block you add, for a Pod `report` whose app writes `/data/report.log` to a shared volume named `data`.

**The sidecar block you add to the Pod**

```yaml
spec:
  initContainers:                      # add this list, beside containers
    - name: log-tail
      image: busybox:1.36
      restartPolicy: Always            # this line makes it a sidecar
      command: ["sh", "-c", "tail -n +1 -F /data/report.log"]
      volumeMounts:
        - name: data                   # the volume the app writes to
          mountPath: /data
```

<details>
<summary>Line-by-line explanation</summary>

- `initContainers:` — Add this list under `spec`, at the same indent as `containers`. The app container and the rest of the Pod stay as they are.
- `restartPolicy: Always` — On an init container this turns it into a **native sidecar**: it starts first, the Pod moves on without waiting for it to finish, and it is restarted if it dies.
- `tail -n +1 -F` — `sh -c` runs the quoted text as a shell command. `tail -n +1` starts at line 1, so no early entry is missed. `-F` keeps following the file by name, even before it exists or after it is rotated.
- `volumeMounts:` — Mounts the Pod's existing volume `data` at `/data`, the folder the app writes to. Both containers now see the same file.

</details>

You cannot add a container to a running Pod. So you rebuild the Pod:

1. Export it: `kubectl -n shop get pod report -o yaml > report.yaml`.
2. Add the `initContainers` block to the file.
3. Replace it: `kubectl replace --force -f report.yaml` deletes the Pod and creates it again, with the same name.
4. Check it: `kubectl -n shop logs report -c log-tail` shows the app's log.

For a Deployment, edit its Pod template instead. It then rolls out new Pods by itself.

## Events

Events are short notes that Kubernetes writes about what it did and what failed: *Scheduled*, *Pulled*, *BackOff*, *FailedScheduling*. The scheduler, the kubelet and the controllers write them. There are two ways to read them:

| Command | What it shows | Use it when |
| --- | --- | --- |
| `kubectl describe pod web-7d9c` | The events of that one object, at the bottom of the output | You know which object is broken |
| `kubectl get events` | Every event in the namespace, also for objects that are gone or that you did not describe | You do not know yet. Example: a ReplicaSet's `FailedCreate` when a quota blocks its Pods |

- **Events expire** after one hour by default. For an older problem, read the logs instead.
- **`kubectl get events` is not sorted by time.** Add `--sort-by=.metadata.creationTimestamp`, or use `kubectl events`, which sorts by itself.

**Events, sorted, filtered and watched**

```bash
kubectl -n shop get events --sort-by=.metadata.creationTimestamp
kubectl -n shop get events --field-selector type=Warning
kubectl -n shop get events --field-selector involvedObject.kind=Pod,involvedObject.name=web-7d9c
kubectl -n shop get events -w                       # stream new events while you fix things
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -20
kubectl -n shop events --for pod/web-7d9c --types=Warning   # kubectl events sorts by time itself
```

<details>
<summary>Line-by-line explanation</summary>

- `-n shop get events --sort-by` — Lists the namespace's events oldest first, so the newest sit at the bottom. Read REASON and MESSAGE: `FailedScheduling`, `BackOff` or `Unhealthy` usually name the problem outright.
- `--field-selector type=Warning` — Only Warning events, the ones that report something failing. Normal events such as Scheduled, Pulled and Started are hidden.
- `involvedObject.kind=Pod` — Events about one object only. `involvedObject` is the object an event is about, and the comma means both conditions must hold.
- `get events -w` — Watches: prints each new event as it happens. Leave it running in a second terminal tab while you fix things, and stop it with Ctrl+C.
- `get events -A --sort-by` — Every namespace, sorted, and `tail -20` keeps the 20 newest. A quick sweep for trouble anywhere, kube-system included.
- `events --for pod/web-7d9c` — The newer `kubectl events` command sorts by time on its own. `--for` limits it to one object and `--types` to one event type.

</details>

`kubectl describe pod` also shows the exit code of the last crash, under `Last State`. [Application failures](/cka/troubleshooting/application-failures) explains what each exit code means.

> [!IMPORTANT] **File answers are compared exactly**
> When a task says *write the lines to /opt/course/…*, the grader compares the file's content. So pick the right source. Name the container with `-c`. If the container restarted, read the crashed run with `--previous`. Keep timestamps and prefixes out. Write only what was asked: a Pod name means `payments`, not `pod/payments`. Check the file with `cat` before you move on.

## 📝 Key Takeaways

- A container's log is what its app prints to stdout and stderr. A file the app writes inside the container is not part of it.
- Use `-c` to name the container. Without it, kubectl picks one for you.
- After a crash and a restart, the crash output is in `kubectl logs --previous`.
- On the node, the log files are under `/var/log/pods`.
- To show a log file, add a native sidecar that runs `tail -F` on it. Rebuild the Pod with `kubectl replace --force`.

**📖 Official documentation:**

- [Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/) *(search: "logging architecture")*
- [kubectl logs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/) *(search: "kubectl logs")*
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) *(search: "sidecar containers")*
- [kubectl events](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_events/) *(search: "kubectl events")*

---

### 🎯 Task: Stream a log file with a native sidecar

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

Pod `ledger` in namespace `tsx-logs` writes its log to `/var/log/ledger/ledger.log`, so `kubectl logs` shows nothing. Add a container named `sidecar` using image `busybox:1.36` that streams that file to its standard output for the whole life of the Pod, so that `kubectl -n tsx-logs logs ledger -c sidecar` shows the ledger entries. Implement it as a native sidecar container. The Pod must keep the name `ledger`, and the container `app` must stay unchanged.

<details>
<summary>💡 Hints</summary>

- A native sidecar is an entry under initContainers with restartPolicy: Always.
- Mount the existing volume logs in the sidecar and run tail -n +1 -F on the file. You cannot add a container to a running Pod: export it, edit the file, then replace --force.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/ledger.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: ledger
  namespace: tsx-logs
  labels:
    app: ledger
spec:
  initContainers:
    - name: sidecar
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "tail -n +1 -F /var/log/ledger/ledger.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/ledger
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          trap 'exit 0' TERM
          i=0
          while true; do
            i=$((i+1))
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) INFO ledger entry $i posted" >> /var/log/ledger/ledger.log
            sleep 2
          done
      volumeMounts:
        - name: logs
          mountPath: /var/log/ledger
  volumes:
    - name: logs
      emptyDir: {}
YAML
kubectl replace --force -f /tmp/cka/ledger.yaml
kubectl -n tsx-logs wait --for=condition=Ready pod/ledger --timeout=120s
for i in $(seq 1 15); do
  if kubectl -n tsx-logs logs ledger -c sidecar 2>/dev/null | grep -q 'ledger entry'; then break; fi
  sleep 2
done
kubectl -n tsx-logs logs ledger -c sidecar --tail=3
```

**Explanation:**

- `mkdir -p /tmp/cka` — Makes sure the folder for the manifest exists.
- `cat > /tmp/cka/ledger.yaml <<'YAML'` — Writes the whole Pod manifest to a file with a heredoc ending at the line `YAML`. The quotes in `'YAML'` stop the shell from expanding `$i` and `$(date …)`, so they reach the container as written.
- `initContainers:` — The only addition to the original Pod: an `initContainers` list at the same indent as `containers`.
- `restartPolicy: Always` — Makes `sidecar` a native sidecar: it starts before `app` and runs for the Pod's whole life.
- `tail -n +1 -F` — Prints the log file from its first line and keeps following it, so every ledger entry ends up on the sidecar's stdout.
- `volumeMounts:` — Mounts the Pod's existing `logs` volume at the folder the app writes to, so the sidecar reads the same file.
- `containers:` — From here down is the original `app` container, copied unchanged, as the question demands.
- `trap 'exit 0' TERM` — A shell running as the container's main process ignores the TERM signal unless told otherwise. This line makes it exit cleanly when the Pod is deleted, instead of waiting to be killed.
- `kubectl replace --force` — A running Pod cannot gain a container, so `replace --force` deletes `ledger` and creates it again from the file, under the same name.
- `wait --for=condition=Ready` — Waits until the new Pod is Ready, which with a sidecar means both containers are running.
- `logs ledger -c sidecar 2>/dev/null | grep -q` — Retries until the sidecar's log contains `ledger entry`. `grep -q` prints nothing and only reports found or not found; `2>/dev/null` hides errors while the container starts.
- `--tail=3` — Shows the three newest entries: proof that the file now reaches `kubectl logs`.

**Notes:** On the exam, run `kubectl -n tsx-logs get pod ledger -o yaml > ledger.yaml`. Add an `initContainers:` list at the same indent as `containers:`. Put the sidecar in it: its name, image, `restartPolicy: Always`, the `tail` command and a `volumeMounts` entry for `logs`. Then run `kubectl replace --force -f ledger.yaml`. The exported status and `nodeName` do no harm. A second entry under `containers` would also print the file, but it is not a native sidecar. It starts at the same time as the app, with no start order. A grader that checks for `restartPolicy: Always` on an init container fails it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-logs
j="kubectl -n $ns get pod ledger -o jsonpath"

kubectl -n $ns get pod ledger >/dev/null 2>&1 && p "pod ledger exists" || f "pod ledger exists"
[ "$($j='{.spec.initContainers[?(@.name=="sidecar")].restartPolicy}' 2>/dev/null)" = "Always" ] && p "sidecar is an init container with restartPolicy Always" || f "sidecar is an init container with restartPolicy Always"
[ "$($j='{.spec.initContainers[?(@.name=="sidecar")].image}' 2>/dev/null)" = "busybox:1.36" ] && p "sidecar image busybox:1.36" || f "sidecar image busybox:1.36"
[ "$($j='{.spec.containers[?(@.name=="app")].volumeMounts[0].mountPath}' 2>/dev/null)" = "/var/log/ledger" ] && p "container app unchanged" || f "container app unchanged"
[ -n "$($j='{.status.initContainerStatuses[?(@.name=="sidecar")].state.running.startedAt}' 2>/dev/null)" ] && p "sidecar is running" || f "sidecar is running"
ok=""
for i in 1 2 3 4 5 6; do
  kubectl -n $ns logs ledger -c sidecar 2>/dev/null | grep -Eq 'INFO ledger entry [0-9]+ posted' && { ok=1; break; }
  sleep 2
done
[ -n "$ok" ] && p "kubectl logs ledger -c sidecar shows ledger entries" || f "kubectl logs ledger -c sidecar shows ledger entries"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Extract one container's error lines

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 3% |
| **Time** | 3 min |

**Question:**

Pod `billing` in namespace `tsx-grep` runs two containers. Write every log line of the container `worker` that contains the string `ERROR` to `/tmp/cka/billing-errors.txt`, one per line, in the order they were logged and exactly as the container printed them.

<details>
<summary>💡 Hints</summary>

- kubectl logs needs -c worker here. Without it you get the api container.
- One of the error lines went to stderr. It is still part of the container log.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n tsx-grep logs billing -c worker | grep 'ERROR' > /tmp/cka/billing-errors.txt
cat /tmp/cka/billing-errors.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answer folder if it is missing.
- `logs billing -c worker | grep 'ERROR'` — Reads only container `worker`'s log, the stderr line included, keeps the lines containing `ERROR` in their original order and writes them to the answer file.
- `cat /tmp/cka/billing-errors.txt` — Check the result: three `ERROR invoice …` lines and nothing from `api`.

**Notes:** Without `-c`, kubectl picks the first container, `api`, and you capture the wrong error. Do not add `--timestamps`: the grader expects the lines exactly as printed. The stderr line is already in the log, because the runtime saves both streams in the same file. So you do not need `2>&1`. It would only redirect kubectl's own messages.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-grep
out=/tmp/cka/billing-errors.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
want=$(kubectl -n $ns logs billing -c worker 2>/dev/null | grep ERROR)
[ "$(echo "$want" | grep -c 'ERROR invoice')" = "3" ] && p "worker logged 3 ERROR lines" || f "worker logged 3 ERROR lines"
[ -n "$want" ] && [ "$(cat $out 2>/dev/null)" = "$want" ] && p "file holds exactly the worker's ERROR lines" || f "file holds exactly the worker's ERROR lines"
grep -q 'timed out' $out 2>/dev/null && f "no lines from container api" || p "no lines from container api"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Find the Pod that crashed with a given error

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Some Pods in namespace `tsx-crash` keep restarting. One of them crashes right after logging `connection refused`. Write only that Pod's name to `/tmp/cka/crashed-pod.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl get pods shows which Pods restart. A healthy Pod can print the same words in a warning, so read what the crashed run said.
- If the container is Running again, the crash is in kubectl logs --previous. If it is still waiting to restart, plain kubectl logs shows the run that died. kubectl describe pod shows the exit code.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n tsx-crash get pods
# Only Pods that restarted are candidates; read the current run and the previous one
for p in $(kubectl -n tsx-crash get pods --no-headers -o custom-columns='N:.metadata.name,R:.status.containerStatuses[0].restartCount' | awk '$2 > 0 {print $1}'); do
  out="$(kubectl -n tsx-crash logs "$p" 2>/dev/null || true) $(kubectl -n tsx-crash logs "$p" --previous 2>/dev/null || true)"
  case "$out" in *"connection refused"*) echo "$p" ;; esac
done > /tmp/cka/crashed-pod.txt
cat /tmp/cka/crashed-pod.txt
```

**Explanation:**

- `kubectl -n tsx-crash get pods` — The RESTARTS column narrows it down: `inventory` and `payments` keep restarting, with STATUS `Error` or `CrashLoopBackOff`. The other three never restarted.
- `for p in $(kubectl` — Prints each Pod's name and its first container's restart count without headers. `awk '$2 > 0 {print $1}'` keeps the names whose count is above zero, and the loop visits each one.
- `out="$(kubectl` — Joins the current log and the `--previous` log into one string. Either can fail depending on whether the container is up at that moment, so `2>/dev/null || true` ignores the error.
- `case "$out" in` — Matches when `connection refused` appears anywhere in that text (the `*` on each side means anything), and then prints the Pod's name.
- `done > /tmp/cka/crashed-pod.txt` — Everything the loop prints goes into the answer file: just `payments`, since `inventory` died on a missing file.
- `cat /tmp/cka/crashed-pod.txt` — Confirm the file holds one bare name, without `pod/`.

**Notes:** `kubectl get pods` shows two restarting Pods, `inventory` and `payments`. The crashed run of `payments` ends with the `connection refused` panic and exit code 2. Read it with `kubectl logs payments` while it waits to restart, or with `--previous` once it is Running again. `inventory` dies on a missing config file. `search` also prints `connection refused`, but only as a warning, and it never restarted. That is why searching every Pod's log gives two names. Write `payments`, not `pod/payments`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-crash
out=/tmp/cka/crashed-pod.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
[ "$(tr -d '[:space:]' < $out 2>/dev/null)" = "payments" ] && p "answer is payments" || f "answer is the crashed Pod's name"
[ "$(kubectl -n $ns get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "5" ] && p "all five Pods still exist" || f "all five Pods still exist"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
