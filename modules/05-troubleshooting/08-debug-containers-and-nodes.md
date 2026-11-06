# kubectl debug, ephemeral containers and crictl

> **Module 5** · Lesson 5.8 · 35 minutes

How to debug when the image has no shell: ephemeral containers, debug copies, node debugging Pods and crictl.

## Learning Objectives

- You can add an ephemeral debug container to a running Pod and see the app's processes, without restarting the Pod.
- You can debug a crashing Pod through a changed copy, and delete the copy afterwards.
- You can start a node debugging Pod, read the node's files through it, and delete it when you are done.
- You can find a Pod's containers on the node with crictl and run a command in one.


Many production images are *distroless*: they hold the app and nothing else. No shell, no `ps`, no `wget`. So `kubectl exec` into them fails with *executable file not found*. `kubectl debug` fixes that: it brings a second image that has the tools. The exam expects you to use it quickly, and to clean up what it leaves behind.

When the API server itself is broken, `kubectl` cannot help at all. Then `crictl`, run on the node, is the fallback.

**Three ways to use kubectl debug**

*All three bring their own image, such as busybox:1.36, with the tools the app image lacks.*

`Ephemeral container` — joins a running Pod, which is not restarted (`kubectl debug POD --target=app`)   `Debug copy` — a new Pod you are free to break (`kubectl debug POD --copy-to=NEW`)   `Node debugger` — a Pod on the node, with the node's files at /host (`kubectl debug node/NODE`)

## Which tool, when

| Tool | What you get | Use it when |
| --- | --- | --- |
| `kubectl exec` | A command inside an existing container, with that image's tools | The image has a shell and the container is running |
| `kubectl debug POD --image=… --target=C` | An ephemeral container in the same Pod, which sees container C's processes | The image has no shell, and the Pod must not restart |
| `kubectl debug POD --copy-to=NEW …` | A new Pod made from the original, with a changed image or command | The container crashes at start, or you need a different image |
| `kubectl debug node/NODE --image=…` | A Pod on that node that shares the node's processes and network, with the node's files at `/host` | You need the node's files, processes or network |
| `crictl` on the node | The container runtime's own view: Pods, containers, logs, exec | The kubelet or the API server is broken |

## Ephemeral containers

An **ephemeral container** is a temporary container you add to a Pod that is already running. The Pod is not restarted. Use one to look inside an app whose image has no tools.

- **It is limited.** It has no ports, probes or resource settings, and it is never restarted.
- **It stays.** You cannot change or remove it. It stays in `spec.ephemeralContainers` until the Pod is deleted.
- **`--target=app`** puts it in the same process list as container `app`. Then `ps` shows the app's processes, and `/proc/1/root` is the app's filesystem.
- **Pass `--profile=general`,** as the examples do. It gives the debug container the rights it needs to look at the app's processes.

**Attach, use and inspect an ephemeral container**

```bash
# Interactive, the usual way: you land in a busybox shell next to the app's processes
kubectl -n shop debug -it api-0 --image=busybox:1.36 --target=app -c dbg --profile=general -- sh
#   ps                      # the app's processes, PID 1 is its entrypoint
#   ls /proc/1/root/etc     # the app container's filesystem
#   wget -qO- -T 3 http://localhost:8080/healthz

# Non-interactive: start it with a long-running command, then exec into it
kubectl -n shop debug api-0 --image=busybox:1.36 --target=app -c dbg --profile=general -- sleep 3600
kubectl -n shop exec api-0 -c dbg -- ps

# What it added to the Pod
kubectl -n shop get pod api-0 -o jsonpath='{.spec.ephemeralContainers[*].name}{"\n"}'
kubectl -n shop get pod api-0 -o jsonpath='{.status.ephemeralContainerStatuses[?(@.name=="dbg")].state}{"\n"}'
```

<details>
<summary>Line-by-line explanation</summary>

- `debug -it api-0` — Adds an ephemeral container named `dbg` (`-c`) to the running Pod `api-0` and opens a terminal in it (`-it`). `--target=app` joins container `app`'s processes. Everything after `--` is the command: a shell.
- `#   ps ` — These three lines are typed inside the debug shell. `ps` lists the app's processes next to your own `sh`, which proves that `--target` worked.
- `/proc/1/root/etc` — `/proc/1/root` is the filesystem as process 1, the app, sees it. So you can browse the app's files with busybox tools. Reading it needs the `SYS_PTRACE` right, which `--profile=general` gives.
- `http://localhost:8080/healthz` — Containers in a Pod share one network, so `localhost:8080` reaches the app directly. If this answers but the Service does not, look at the Service, not the app.
- `-- sleep 3600` — The non-interactive form: kubectl adds the container and returns at once, and `sleep 3600` keeps it running for an hour. Use it instead of the first command, not after it: a container name can be used only once per Pod.
- `exec api-0 -c dbg -- ps` — Runs `ps` inside `dbg`. `exec` works on a running ephemeral container, and `-c dbg` picks it over the app container.
- `{.spec.ephemeralContainers[*].name}` — Names of every ephemeral container in the Pod spec. They stay listed until the Pod is deleted, even after their command ends.
- `ephemeralContainerStatuses` — `dbg`'s current state: `running` with a start time, `waiting` while its image is pulled, or `terminated` with an exit code once its command ends.

</details>

## Debugging a copy

Some containers crash before you can look inside. For those, make a copy of the Pod with one change, for example a command that only sleeps. The original Pod is not touched.

**--copy-to: a new Pod you are free to break**

```bash
# Same Pod plus a busybox container, sharing one process namespace
kubectl -n shop debug api-0 --copy-to=api-debug --image=busybox:1.36 --share-processes -- sleep 3600

# Same Pod, but container app gets a different image
kubectl -n shop debug api-0 --copy-to=api-debug --set-image=app=busybox:1.36

# Same Pod, but container app runs a different command (it crashed on start)
kubectl -n shop debug api-0 --copy-to=api-debug --container=app -- sh -c 'sleep 3600'

kubectl -n shop get pod api-debug
kubectl -n shop delete pod api-debug        # the copy is yours to clean up
```

<details>
<summary>Line-by-line explanation</summary>

- `--share-processes` — Creates a new Pod, `api-debug`: a copy of `api-0` plus a busybox container running `sleep 3600`. `--share-processes`, on by default with `--copy-to`, puts all its containers in one process list. The original is untouched.
- `--set-image=app=busybox:1.36` — Another variant. Each one creates `api-debug`, so delete the previous copy first. Here the copy's container `app` gets a different image, written `container=image`: a quick test of whether another image fixes the problem.
- `--container=app -- sh -c 'sleep 3600'` — Keeps the image but replaces container `app`'s command with `sleep 3600`. The copy stays up, so you can `kubectl exec` in and start the real program by hand to see why it crashes.
- `get pod api-debug` — Check that the copy is Running. It is a standalone Pod: nothing recreates it if it dies.
- `delete pod api-debug` — Removes the copy. Nothing does it for you, and a leftover Pod can fail a grader that counts Pods.

</details>

The copy is a plain Pod with a new name. No controller manages it, so nothing deletes it for you. It also drops the original's labels and probes, so no Service sends it traffic. To find why a container crashes, start a copy that only sleeps. Then `kubectl exec` into it and run the real program by hand, to see its error.

## Debugging a node

`kubectl debug node/cka-worker --image=busybox:1.36` starts a Pod on that node. Through it you can look at the node as if you had logged in:

- It shares the node's processes and network, so `ps` shows the kubelet.
- The node's whole filesystem is mounted at `/host`. `chroot /host` makes the shell use the node's own programs.
- The Pod is named `node-debugger-cka-worker-` and lands in the current namespace. Pass `-n` so you know where it went.
- Exiting the shell does not delete it. It stays as `Completed` until you delete it.
- Add `--profile=sysadmin` only when you need a privileged container.

**A node debugging Pod**

```bash
kubectl debug node/cka-worker -n shop -it --image=busybox:1.36 --profile=general -- sh
#   cat /host/etc/hostname
#   ps | grep kubelet                   # you see the node's processes
#   ls /host/var/log/pods
#   chroot /host                        # from here on, the node's own programs
kubectl -n shop get pods | grep node-debugger
kubectl -n shop delete pod node-debugger-cka-worker-x7k2p

# Non-interactive variant
kubectl debug node/cka-worker -n shop --image=busybox:1.36 --profile=general -- sleep 600
kubectl -n shop exec node-debugger-cka-worker-x7k2p -- cat /host/etc/hostname
```

<details>
<summary>Line-by-line explanation</summary>

- `debug node/cka-worker -n shop -it` — Starts a Pod on node `cka-worker` that shares the node's processes and network, with the node's filesystem at `/host`, and opens a shell in it. `-n shop` decides which namespace the Pod lands in.
- `#   cat /host/etc/hostname` — Typed inside that shell. Anything under `/host` is the node's own file, so this prints the node's hostname, `cka-worker`.
- `#   ps | grep kubelet` — The Pod shares the node's process list, so `ps` shows every process on the node, including the kubelet and its full command line.
- `#   ls /host/var/log/pods` — The node's Pod log folders from the *Logs* lesson, reached without ssh.
- `#   chroot /host` — Makes `/host` the shell's root folder, so commands now run the node's own programs and read its config instead of busybox's. `exit` leaves the chroot, a second `exit` leaves the Pod.
- `get pods | grep node-debugger` — Back on your machine: the debugging Pod is still there, `Completed` after you exit. Its name is `node-debugger-cka-worker-` plus a random suffix.
- `delete pod node-debugger-cka-worker-x7k2p` — Deletes it. `x7k2p` stands for the real suffix. Copy the name from the line above.
- `debug node/cka-worker -n shop --image` — Without `-it`, kubectl creates the Pod running `sleep 600` and returns, ready for `exec`. After 10 minutes the sleep ends and the Pod turns Completed, but it is still not deleted.
- `exec node-debugger-cka-worker-x7k2p` — Reads a node file through the Pod without an interactive shell. Use this form when the output goes into an answer file.

</details>

## crictl on the node

`crictl` talks to the container runtime directly, without the API server. You run it in a shell on the node. These three commands find a Pod's containers and run a command in one:

**crictl on the node**

```bash
# exam: ssh <node>, then sudo -i    lab: docker exec -it cka-worker bash
crictl pods --name api-0                      # Pod sandbox ID and state
crictl ps --pod <pod-id>                      # running containers of that Pod
crictl exec <container-id> cat /etc/hostname  # only works if the image has the binary
```

<details>
<summary>Line-by-line explanation</summary>

- `crictl pods --name api-0` — Lists the Pods the runtime knows on this node, filtered by name. The first column is the Pod ID. STATE is `Ready` or `NotReady`.
- `crictl ps --pod` — The running containers of that Pod. Paste the Pod ID from the line above. The first column is the container ID.
- `crictl exec` — Runs a command in the container through the runtime, like `kubectl exec`. The program must exist in the image, so a distroless image fails here too.

</details>

`crictl` can also list stopped containers and read their logs. [Control plane failures](/cka/troubleshooting/control-plane-failures) covers those commands.

> [!IMPORTANT] **Clean up what kubectl debug leaves behind**
> Node debugging Pods and `--copy-to` Pods stay after you leave them. A grader that counts the Pods in a namespace sees them, so delete them as the last step of the task. You cannot remove an ephemeral container, so add one only to the Pod the question names. When a task only wants the debug container to exist and keep running, start it without `-it` and with a `sleep` command. This course's solutions do the same.

## 📝 Key Takeaways

- `kubectl debug POD --target=app` adds an ephemeral container to a running Pod. It sees the app's processes, and it cannot be removed.
- `--copy-to` makes a new Pod that you can change and break. Delete it when you are done.
- `kubectl debug node/NODE` starts a Pod on the node, with the node's files at `/host`. It stays as Completed until you delete it.
- When the API server is down, use `crictl` on the node.

**📖 Official documentation:**

- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/) *(search: "debug running pods ephemeral")*
- [Ephemeral Containers](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/) *(search: "ephemeral containers")*
- [Debugging Kubernetes Nodes With Kubectl](https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/) *(search: "kubectl debug node")*
- [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) *(search: "crictl")*

---

### 🎯 Task: Debug a Pod that has no shell

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Pod `payroll` in namespace `tsx-debug` runs an image without a shell, so `kubectl exec` into it fails. Without restarting or recreating the Pod, add a debug container named `dbg` using image `busybox:1.36` that shares the process namespace of container `app` and keeps running with the command `sleep 3600`. Then, from `dbg`, write the command line of process ID 1 to `/tmp/cka/payroll-pid1.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl debug with --target adds an ephemeral container to the running Pod. Put the command after --.
- Once dbg is running, use kubectl exec payroll -c dbg -- cat /proc/1/cmdline. The arguments are separated by NUL bytes, and tr can turn them into spaces.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n tsx-debug exec payroll -c app -- sh -c true 2>&1 || true
kubectl -n tsx-debug debug payroll --image=busybox:1.36 --target=app -c dbg --profile=general -- sleep 3600
for i in $(seq 1 30); do
  s=$(kubectl -n tsx-debug get pod payroll -o jsonpath='{.status.ephemeralContainerStatuses[?(@.name=="dbg")].state.running.startedAt}')
  [ -n "$s" ] && break
  sleep 2
done
kubectl -n tsx-debug exec payroll -c dbg -- ps
kubectl -n tsx-debug exec payroll -c dbg -- cat /proc/1/cmdline | tr '\0' ' ' > /tmp/cka/payroll-pid1.txt
cat /tmp/cka/payroll-pid1.txt; echo
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answer folder.
- `exec payroll -c app -- sh -c true` — Shows the problem first: the pause image has no shell, so exec fails with *executable file not found*. `2>&1` merges the error into normal output, and `|| true` lets the script carry on.
- `debug payroll --image=busybox:1.36` — Adds ephemeral container `dbg` to the running Pod, inside `app`'s process namespace, running `sleep 3600`. There is no `-it`, so kubectl returns at once, and the Pod is not restarted.
- `for i in $(seq 1 30); do` — Waits up to a minute for `dbg` to be running before using it.
- `s=$(kubectl` — `[?(@.name=="dbg")]` picks dbg's entry from the ephemeral container statuses, and `startedAt` exists only while it runs. The next line's `[ -n "$s" ]` is true once the value is not empty.
- `exec payroll -c dbg -- ps` — Lists what dbg can see: PID 1 is `/pause` from container `app`, then `sleep 3600` and `ps` itself. Seeing `/pause` proves the target worked.
- `cat /proc/1/cmdline` — `/proc/1/cmdline` holds PID 1's command line with NUL bytes between arguments. The pipe runs on your machine: `tr '\0' ' '` turns those bytes into spaces before the answer is saved.
- `cat /tmp/cka/payroll-pid1.txt; echo` — Shows the answer, `/pause`. The file has no newline at the end, so `echo` adds one to keep your prompt on its own line.

**Notes:** You might want to look around first with `kubectl debug -it payroll -n tsx-debug --image=busybox:1.36 --target=app -c dbg -- sh`. But then `dbg` runs `sh` and stops when you exit, and you cannot reuse the name. So start it with `-- sleep 3600`, then use `kubectl exec … -c dbg`. With `--target=app`, PID 1 is the app container's `/pause`. Without it, `dbg` has its own process list, and PID 1 is its own `sleep`. Seeing `sleep` as PID 1 tells you the target was missed.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-debug
j="kubectl -n $ns get pod payroll -o jsonpath"

kubectl -n $ns get pod payroll >/dev/null 2>&1 && p "pod payroll exists" || f "pod payroll exists"
[ "$($j='{.status.containerStatuses[?(@.name=="app")].restartCount}' 2>/dev/null)" = "0" ] && p "container app was not restarted" || f "container app was not restarted"
[ "$($j='{.spec.ephemeralContainers[?(@.name=="dbg")].name}' 2>/dev/null)" = "dbg" ] && p "ephemeral container dbg exists" || f "ephemeral container dbg exists"
[ "$($j='{.spec.ephemeralContainers[?(@.name=="dbg")].image}' 2>/dev/null)" = "busybox:1.36" ] && p "dbg image busybox:1.36" || f "dbg image busybox:1.36"
[ "$($j='{.spec.ephemeralContainers[?(@.name=="dbg")].targetContainerName}' 2>/dev/null)" = "app" ] && p "dbg targets container app" || f "dbg targets container app"
[ -n "$($j='{.status.ephemeralContainerStatuses[?(@.name=="dbg")].state.running.startedAt}' 2>/dev/null)" ] && p "dbg is running" || f "dbg is running"
grep -q '/pause' /tmp/cka/payroll-pid1.txt 2>/dev/null && p "PID 1 command line is the app's /pause" || f "PID 1 command line is the app's /pause"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Read a node file through a node debugging Pod

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Using `kubectl debug`, start a node debugging Pod on node `cka-worker` in namespace `tsx-node` with image `busybox:1.36`. Through that Pod, read the node's file `/etc/hostname` and write its content to `/tmp/cka/worker-hostname.txt`. Delete the debugging Pod when you are done.

<details>
<summary>💡 Hints</summary>

- kubectl debug node/cka-worker -n tsx-node --image=busybox:1.36 -- sleep 600 creates the Pod and returns.
- The node's root filesystem is mounted at /host inside the debugging Pod.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl debug node/cka-worker -n tsx-node --image=busybox:1.36 --profile=general -- sleep 600
pod=$(kubectl -n tsx-node get pods -o name | grep node-debugger-cka-worker | awk 'NR==1')
kubectl -n tsx-node wait --for=condition=Ready "$pod" --timeout=120s
kubectl -n tsx-node exec "$pod" -- cat /host/etc/hostname > /tmp/cka/worker-hostname.txt
cat /tmp/cka/worker-hostname.txt
kubectl -n tsx-node delete "$pod" --grace-period=1
```

**Explanation:**

- `kubectl debug node/cka-worker` — Creates the node debugging Pod in `tsx-node` on `cka-worker`, running `sleep 600` so it stays up for exec. kubectl prints the generated Pod name and returns.
- `pod=$(` — Finds that name: `-o name` prints `pod/` lines, grep keeps the debugger, and `awk 'NR==1'` takes the first line. The result is stored in the variable `pod`.
- `wait --for=condition=Ready` — Waits until the busybox container is running, so the exec below does not race it.
- `cat /host/etc/hostname >` — Reads the node's `/etc/hostname` through the `/host` mount; `>` saves the output, `cka-worker`, to the answer file on your machine.
- `cat /tmp/cka/worker-hostname.txt` — Should print `cka-worker`.
- `delete "$pod" --grace-period=1` — Cleans up, as the task requires. `--grace-period=1` gives the Pod one second to stop instead of the default 30, which a `sleep` would otherwise use up.

**Notes:** The interactive way: run `kubectl debug node/cka-worker -n tsx-node -it --image=busybox:1.36 -- sh`, then `cat /host/etc/hostname`, then exit. Write the value into the answer file from your own terminal. Then delete the Pod, which `kubectl -n tsx-node get pods` still shows as Completed. Always read node files under `/host`. Without the prefix you read the debug container's own `/etc/hostname`. With `hostNetwork` it also shows the node's name, but other files differ, so build the habit.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-node
out=/tmp/cka/worker-hostname.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
[ "$(tr -d '[:space:]' < $out 2>/dev/null)" = "cka-worker" ] && p "file content is cka-worker" || f "file content is cka-worker"
[ -z "$(kubectl -n $ns get pods --no-headers 2>/dev/null | grep node-debugger)" ] && p "no node-debugger Pod left in $ns" || f "no node-debugger Pod left in $ns"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
