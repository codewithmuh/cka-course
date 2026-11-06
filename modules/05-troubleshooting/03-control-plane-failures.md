# Control plane failures

> **Module 5** · Lesson 5.3 · 40 minutes

Where the control plane lives on a kubeadm node, what each part's failure looks like from kubectl, and how to debug with crictl and the kubelet's log when kubectl itself does not work.

## Learning Objectives

- You can tell from one symptom which part is down: the API server, the scheduler, the controller manager or etcd.
- You can find and fix a typo in a static Pod file under /etc/kubernetes/manifests, and watch the kubelet bring the part back.
- You can read a part's logs with crictl and journalctl when the API server is not answering.


This lesson and the next cover two exam topics: **Troubleshoot clusters and nodes** and **Troubleshoot cluster components**.

In a typical task, you ssh to the control plane node and find a file with one wrong character. You fix it and wait for the part to come back. These tasks look scary, because kubectl may not work when you start. But a kubeadm control plane is just four files in one folder, and every tool you need is on the node.

## Where the control plane lives

A quick recap from [Control plane and node components](/cka/architecture/control-plane-and-nodes): the four control plane parts are **static Pods**. The kubelet runs them from files in `/etc/kubernetes/manifests`, the folder named by `staticPodPath` in `/var/lib/kubelet/config.yaml`. In kubectl, each shows up as a read-only *mirror Pod* named `-`, such as `kube-apiserver-cka-control-plane`. So to fix a part, edit its file, never the mirror Pod.

**Find them (exam: ssh cka-control-plane; lab: docker exec -it cka-control-plane bash)**

```bash
grep staticPodPath /var/lib/kubelet/config.yaml
ls -l /etc/kubernetes/manifests
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

# From anywhere, while the API server works
kubectl -n kube-system get pods -o wide
kubectl -n kube-system get pod kube-apiserver-cka-control-plane -o jsonpath='{.metadata.annotations.kubernetes\.io/config\.source}'   # file
```

<details>
<summary>Line-by-line explanation</summary>

- `grep staticPodPath` — Runs on the control-plane node (after `sudo -i` on the exam), because this file is on the node's disk, not in the API. It prints the folder the kubelet reads static Pod manifests from, normally `/etc/kubernetes/manifests`.
- `ls -l /etc/kubernetes/manifests` — One file per control-plane component. The kubelet runs whatever it finds here, with no scheduler involved: change a file and the component restarts, move it out and the component stops.
- `kubectl -n kube-system get pods -o wide` — From your usual terminal: the *mirror Pods* the kubelet publishes for those files, named component plus node, such as `kube-apiserver-cka-control-plane`. They let you see static Pods; they do not control them.
- `get pod kube-apiserver-cka-control-plane` — Reads one annotation of the mirror Pod. The dots inside its key are escaped as `\.` so jsonpath does not read them as path steps. The answer `file` means the Pod comes from a manifest on disk.

</details>

Each part reads its settings from flags in its file. These are the ones that break most often:

| Part and its file | Talks to | Settings worth checking |
| --- | --- | --- |
| **kube-apiserver**, `kube-apiserver.yaml` | etcd on 127.0.0.1:2379. Listens on port 6443 | `--etcd-servers`, `--client-ca-file`, `--tls-cert-file`, `--service-cluster-ip-range`, and every path under /etc/kubernetes/pki |
| **kube-scheduler**, `kube-scheduler.yaml` | the API server, through /etc/kubernetes/scheduler.conf | `--kubeconfig`, `--authentication-kubeconfig`, `--authorization-kubeconfig` |
| **kube-controller-manager**, `kube-controller-manager.yaml` | the API server, through /etc/kubernetes/controller-manager.conf | `--kubeconfig`, `--cluster-signing-cert-file` and `-key-file`, `--service-account-private-key-file`, `--root-ca-file` |
| **etcd**, `etcd.yaml` | listens on 2379 (clients) and 2380 (other etcd members). Keeps its data in /var/lib/etcd | `--data-dir`, `--listen-client-urls`, `--cert-file`, `--key-file`, `--trusted-ca-file` |

## Symptoms by part

**Which part is down? Read the symptom**

*Each part fails in its own way. In all four cases, Pods that are already running keep running.*

`API server` — kubectl: connection refused   `Scheduler` — new Pods Pending, no events   `Controller manager` — Deployments make no Pods   `etcd` — kubectl hangs or times out

- **kube-apiserver down.** Every kubectl command fails with *The connection to the server :6443 was refused*, or with an *i/o timeout*. Pods already running keep serving traffic, but nothing can be created, scaled or deleted. This is the one failure you must debug entirely on the node.
- **kube-scheduler down.** New Pods stay `Pending` with NODE `` and **no events** at all, not even FailedScheduling. Nothing is looking at them. `kubectl -n kube-system get pods` shows the scheduler Pod in CrashLoopBackOff or Error, or missing.
- **kube-controller-manager down.** The API accepts every change, but nothing acts on it. A new Deployment shows `0/3`, with no ReplicaSet and no Pods. Scaling does nothing, Jobs never start, and a node you shut down is never marked NotReady.
- **etcd down.** The API server runs, but cannot read or write its data. kubectl hangs, or says *etcdserver: request timed out* or *context deadline exceeded*. On the node, `crictl ps -a` shows the etcd container Exited or missing.

## Debugging while kubectl works

**While the API server answers, read the other parts through it**

```bash
kubectl -n kube-system get pods
kubectl -n kube-system describe pod kube-scheduler-cka-control-plane | tail -15
kubectl -n kube-system logs kube-scheduler-cka-control-plane
kubectl -n kube-system logs kube-controller-manager-cka-control-plane --previous
kubectl get --raw '/readyz?verbose'             # one [+] ok or [-] failed line per check, etcd included
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl -n kube-system get pods` — Look for a control-plane Pod that is not Running, or whose RESTARTS keeps growing. Their names end in the node's name.
- `describe pod kube-scheduler-cka-control-plane` — A mirror Pod has events and container states like any other Pod. The last 15 lines show why the scheduler's container cannot start or keeps exiting.
- `logs kube-scheduler-cka-control-plane` — The scheduler's own output, fetched through the API server. That works while the API server is up, even when the scheduler itself is broken.
- `logs kube-controller-manager-cka-control-plane --previous` — `--previous` reads the crashed instance after the controller-manager has restarted. The last lines usually name the bad flag or the file it could not open.
- `/readyz?verbose` — `--raw` sends a request straight to an API server path. `/readyz?verbose` lists every readiness check as `[+]` ok or `[-]` failed, then a verdict; look for the `etcd` lines. The quotes stop zsh from reading `?` as a file pattern.

</details>

A mirror Pod has events and logs like any other Pod, so `describe` and `logs` usually show the typo. The table in **What goes wrong in a manifest** below lists which typo gives which message. Whatever you find, fix it in the manifest file.

## Debugging when kubectl does not work

When the API server is down, kubectl cannot reach anything. Two tools still work, because they run on the node and do not need the API server:

| Tool | What it asks | Works when the API server is down? |
| --- | --- | --- |
| `kubectl` | the API server | No |
| `crictl` | the container runtime (containerd) on this node | Yes |
| `journalctl -u kubelet` | the kubelet's own log on this node | Yes |

In `crictl ps -a`, read two columns. STATE says Running or Exited. ATTEMPT counts restarts: if it keeps climbing, the part is crash-looping. If a part has no container at all, it never started. The kubelet could not pull its image or could not read its file.

**On the control-plane node**

```bash
crictl ps -a                                   # every container, including Exited ones
crictl ps -a --name kube-apiserver
crictl logs <container-id>                     # the component's own output; add --tail 50
crictl pods                                    # sandboxes, including ones with no container
journalctl -u kubelet --since '10 min ago' --no-pager | grep -iE 'apiserver|manifest|static|failed' | tail -20
journalctl -u kubelet -f                       # watch while you fix
systemctl status kubelet --no-pager
cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `crictl ps -a` — `crictl` asks the container runtime (containerd) directly, so it works even when the API server, and with it kubectl, is down. `-a` adds stopped containers; without it you see only running ones.
- `--name kube-apiserver` — Only containers whose name matches. Read STATE (Running or Exited) and ATTEMPT: an ATTEMPT that keeps rising means the kubelet keeps restarting a component that crashes.
- `crictl logs <container-id>` — Use an ID from the CONTAINER column of `crictl ps`. This is the component's own output, the same text `kubectl logs` would show if the API server were up.
- `crictl pods` — Lists Pod sandboxes, the environment the runtime sets up for a Pod before its containers. A sandbox with no container in `ps -a` means the container was never created: look in the kubelet journal for an image or start error.
- `journalctl -u kubelet --since` — The kubelet runs as a system service, not a Pod, so its log is in the journal, out of kubectl's reach. `-u kubelet` picks its lines, `--since` the last 10 minutes; `grep -iE` keeps lines with any of the words, in any case.
- `journalctl -u kubelet -f` — `-f` follows the log, printing new lines as they arrive, so you see the kubelet react the moment you save a manifest. Ctrl+C stops it.
- `systemctl status kubelet` — Whether the kubelet service is running, since when, and its last few log lines. `--no-pager` prints straight to the terminal instead of a viewer you must leave with `q`.
- `cat /etc/kubernetes/manifests/kube-apiserver.yaml` — Prints the API server's manifest so you can read its image, flags and paths. A control-plane fix always goes in this file, never in the mirror Pod.

</details>

On the lab, run those after `docker exec -it cka-control-plane bash`. On the exam, run them after `ssh `, and `sudo -i` if you are not root. Either way, type `exit` before the next question. kubectl on the node has no kubeconfig, so it fails with *connection refused to localhost:8080*. That looks like a second outage, but it is not.

## What goes wrong in a manifest

| Mistake | What you see |
| --- | --- |
| A typo in the image tag | No container in `crictl ps -a`. The kubelet journal says *Failed to pull image*, with the bad name. Once the API server is up, the mirror Pod shows ErrImagePull. Compare with the other manifests: the API server, controller manager and scheduler use the same version tag. |
| A typo in the command | The container cannot start. `describe` on the mirror Pod, or the kubelet journal, quotes *exec: "kube-schedulerr": executable file not found in $PATH*. |
| A typo in a flag | The container starts and exits within a second. `crictl logs` prints *Error: unknown flag: --etcd-serverss*. ATTEMPT climbs. |
| A wrong path in a flag | `--kubeconfig` or a certificate flag points at a missing file. The log says *open /etc/kubernetes/…: no such file or directory*. Check that the path exists on the node, and that a `hostPath` volume mounts it into the container. |
| YAML that does not parse | The part simply disappears: no mirror Pod, no container. Only the kubelet journal says why: *Could not process manifest file*, with the path. |

A file moved out of the folder makes its part stop, too. And never keep a backup copy inside the folder: the kubelet runs every file there, as [Control plane and node components](/cka/architecture/control-plane-and-nodes) warns.

**Three fast checks for a suspicious manifest**

```bash
cd /etc/kubernetes/manifests
grep -n 'image:' *.yaml                                   # tags agree? (etcd has its own)
grep -o '/etc/kubernetes/[a-z./-]*' kube-apiserver.yaml | sort -u | xargs ls -ld    # every path exists?
diff /tmp/kube-apiserver.yaml.bak kube-apiserver.yaml     # if you (or the task) made a backup
```

<details>
<summary>Line-by-line explanation</summary>

- `cd /etc/kubernetes/manifests` — Moves into the manifest folder so the next commands can use short file names.
- `grep -n 'image:' *.yaml` — The image line of all four manifests, with file name and line number (`-n`). API server, controller-manager and scheduler share one version tag, so an odd one out is the typo.
- `grep -o '/etc/kubernetes/` — `-o` prints only the matched text, here every `/etc/kubernetes/…` path in the file. `sort -u` drops duplicates and `xargs ls -ld` lists each one; a path that does not exist answers *No such file or directory*.
- `diff /tmp/kube-apiserver.yaml.bak` — Prints only the lines that differ between the backup and the current file, so a one-character change shows up in seconds.

</details>

## Fix, then wait: the rhythm

The kubelet watches the folder, so it notices a saved file within seconds. It stops the old container and starts a new one. After an API server fix, allow up to a minute before kubectl answers. The server must start, pass its own health checks and reconnect to etcd. Watch with `crictl ps` on the node, or with `watch kubectl -n kube-system get pods` once kubectl answers.

**The rhythm for a manifest fix**

`Back up` — outside the folder (`cp … /tmp/`) → `Edit the file` — fix the one wrong character → `Watch` — the kubelet restarts the part (`crictl ps`) → `Exit and prove` — from your own terminal (`kubectl get …`)

**The rhythm for a manifest fix**

```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak   # outside the directory
vim /etc/kubernetes/manifests/kube-apiserver.yaml                               # fix the one character
journalctl -u kubelet -f | grep -i apiserver                                    # Ctrl-C when it says the pod was created
crictl ps --name kube-apiserver                                                 # Running, ATTEMPT stable
exit
kubectl get nodes                                                               # back in business
```

<details>
<summary>Line-by-line explanation</summary>

- `cp /etc/kubernetes/manifests/kube-apiserver.yaml` — Back up first, and outside the folder: the kubelet reads every file in it, so a copy left there would be treated as one more Pod to run.
- `vim /etc/kubernetes/manifests/kube-apiserver.yaml` — Edit the live file. The moment you save, the kubelet notices and recreates the API server container; there is no apply step.
- `journalctl -u kubelet -f | grep -i apiserver` — Follows the kubelet's log but shows only lines that mention the API server, so you watch the old container go and the new one start.
- `crictl ps --name kube-apiserver` — No `-a` this time, so only running containers. The fix worked when the API server is listed and its ATTEMPT stops increasing.
- `exit` — Leaves the node. On the exam, if you used `sudo -i`, the first `exit` leaves the root shell and a second one closes the ssh session.
- `kubectl get nodes` — Back where kubectl has a kubeconfig. An answer means the API server is serving again; give it up to a minute after the fix.

</details>

> [!IMPORTANT] **The grader checks the part, and the fix must be in the file**
> A control plane task is graded on state: the part's mirror Pod Running, a Deployment reaching its replicas, or a node joining. The grader cannot see what you edited. But a fix outside the manifest file is lost when the kubelet restarts the Pod. So fix the file. Then prove it with `kubectl -n kube-system get pods`, plus the `get` for what the task said should work again.

> [!WARNING] **These tasks break your lab on purpose**
> The two disruptive tasks below edit a manifest on `cka-control-plane`. Their setup saves a backup in `/tmp` on the node, and their cleanup restores it and waits for the part to come back. But while you work, the cluster really is broken. Run them one at a time, finish each with its cleanup, and run nothing else on the lab in between.

## 📝 Key Takeaways

- The four control plane parts are static Pods: files in `/etc/kubernetes/manifests`. Fix the file, never the mirror Pod.
- Read the symptom: kubectl refused means the API server. Pending with no events means the scheduler. A Deployment with no ReplicaSet means the controller manager.
- When kubectl does not work, use `crictl ps -a`, `crictl logs` and `journalctl -u kubelet` on the node.
- Before you edit a manifest, back it up outside the folder. The kubelet runs every file inside it.
- After the fix, wait, exit the node, and prove it with kubectl from your own terminal.

**📖 Official documentation:**

- [Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/) *(search: "troubleshooting clusters")*
- [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) *(search: "static pod")*
- [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) *(search: "crictl")*
- [Cluster Architecture](https://kubernetes.io/docs/concepts/architecture/) *(search: "control plane components")*

---

### 🎯 Task: Map the control plane's static Pods

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 2% |
| **Time** | 4 min |

**Question:**

On `cka-control-plane` the kubelet runs the control-plane components as static Pods. Write to `/tmp/cka/static-pods.txt`: on the first line, the absolute path of the directory the kubelet on that node reads static Pod manifests from, taken from the kubelet's configuration file rather than from memory; then the names of the control plane's static Pods exactly as `kubectl get pods -n kube-system` shows them, one per line.

<details>
<summary>💡 Hints</summary>

- The kubelet's configuration is /var/lib/kubelet/config.yaml on the node. The field is staticPodPath.
- Static Pods appear in kube-system as mirror Pods named -. Their annotation kubernetes.io/config.source is file.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
dir=$(docker exec cka-control-plane awk '/^staticPodPath:/{print $2}' /var/lib/kubelet/config.yaml)
echo "$dir" > /tmp/cka/static-pods.txt
kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.annotations.kubernetes\.io/config\.mirror)]}{.metadata.name}{"\n"}{end}' | grep 'cka-control-plane$' >> /tmp/cka/static-pods.txt
cat /tmp/cka/static-pods.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answer folder if it is missing.
- `dir=$(docker exec` — Runs `awk` on the lab node and stores what it prints in the variable `dir`. The awk program finds the line starting `staticPodPath:` and prints its second field, the path. On the exam: `ssh` to the node and grep there.
- `echo "$dir" > /tmp/cka/static-pods.txt` — Writes the path as the file's first line. A single `>` creates the file or overwrites it.
- `kubectl -n kube-system get pods -o jsonpath` — Keeps only Pods carrying the `kubernetes.io/config.mirror` annotation, the mark of a static Pod, and prints one name per line. `grep 'cka-control-plane$'` keeps names ending in the node's name; `>>` appends them to the file.
- `cat /tmp/cka/static-pods.txt` — Check the file: the path first, then the four Pod names.

**Notes:** On the exam, the first command is `ssh  grep staticPodPath /var/lib/kubelet/config.yaml`. For the Pod names, the quickest way is `kubectl -n kube-system get pods`: copy the four whose name ends in the node's name. The solution uses a jsonpath filter instead, because the `kubernetes.io/config.mirror` annotation reliably tells a static Pod from, say, a DaemonSet Pod when the names are less obvious. The grader compares the file with the live cluster, so copy the names exactly.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/static-pods.txt

[ -s "$file" ] && p "file $file exists" || f "file $file exists"
want=$(docker exec cka-control-plane awk '/^staticPodPath:/{print $2}' /var/lib/kubelet/config.yaml 2>/dev/null)
[ -n "$want" ] && [ "$(head -1 "$file" 2>/dev/null | tr -d '[:space:]')" = "$want" ] && p "first line is the manifest directory ($want)" || f "first line is the manifest directory ($want)"
live=$(kubectl -n kube-system get pods -o jsonpath='{range .items[?(@.metadata.annotations.kubernetes\.io/config\.mirror)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep 'cka-control-plane$')
[ "$(echo "$live" | grep -c .)" -ge 4 ] 2>/dev/null && p "found the control-plane static pods live" || f "found the control-plane static pods live"
for pod in $live; do
  grep -qx "$pod" "$file" 2>/dev/null && p "lists $pod" || f "lists $pod"
done

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Nothing gets scheduled

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 7% |
| **Time** | 10 min |

**Question:**

The Deployment `web` in namespace `ts-cp` was created a few minutes ago and all of its Pods are still Pending; new Pods anywhere in the cluster do not start either. Find the cause on the control-plane node and fix it there. When you are done the Deployment must have 2 Pods Running and the component you repaired must be healthy.

<details>
<summary>💡 Hints</summary>

- describe a Pending Pod. No FailedScheduling event means nothing is scheduling. Which kube-system Pod is not Running?
- describe that Pod, or crictl logs its container on the node. The runtime says what it could not run.
- The fix goes in /etc/kubernetes/manifests on cka-control-plane. The kubelet restarts the part when the file changes.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-cp get pods -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system describe pod kube-scheduler-cka-control-plane | tail -12
docker exec cka-control-plane bash -c 'sed -i "/^ *- kube-schedulerr$/s/kube-schedulerr/kube-scheduler/" /etc/kubernetes/manifests/kube-scheduler.yaml'
for i in $(seq 1 60); do
  [ "$(kubectl -n kube-system get pod kube-scheduler-cka-control-plane -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && break
  sleep 3
done
kubectl -n ts-cp rollout status deploy/web --timeout=120s
kubectl -n ts-cp get pods -o wide
```

**Explanation:**

- `kubectl -n ts-cp get pods -o wide` — Both Pods Pending with NODE ``. Describe one and you find no events at all: nothing is even trying to schedule them.
- `kubectl -n kube-system get pods -o wide` — The scheduler's mirror Pod is not Running (`RunContainerError` or `CrashLoopBackOff`). That is the component to look at.
- `describe pod kube-scheduler-cka-control-plane` — Its last state and events quote the runtime: *exec: "kube-schedulerr": executable file not found in $PATH*. The manifest's command names a program that does not exist.
- `docker exec cka-control-plane bash -c 'sed -i` — Fixes the manifest on the node without an editor. `sed -i` edits the file in place: on the line that is exactly `- kube-schedulerr`, it replaces the misspelled name. On the exam you would `ssh` in and use vim.
- `for i in $(seq 1 60)` — A wait loop: up to 60 times, ask whether the scheduler's container is ready, stop as soon as it is, otherwise sleep 3 seconds. About three minutes at most.
- `rollout status deploy/web` — With the scheduler back, the Pending Pods get nodes; this waits until both are available.
- `kubectl -n ts-cp get pods -o wide` — Proof: both Pods Running, each with a node name.

**Notes:** The Pending Pods have no events. `kubectl -n kube-system get pods` shows `kube-scheduler-cka-control-plane` in `RunContainerError` or `CrashLoopBackOff`. describe quotes the runtime: *exec: "kube-schedulerr": executable file not found in $PATH*. On the node, run `vim /etc/kubernetes/manifests/kube-scheduler.yaml` and fix the first entry of `command`. Within seconds, `crictl ps --name kube-scheduler` shows a new Running container, and the Pending Pods get nodes. Do not try `kubectl delete` or `kubectl edit` on the mirror Pod: only the file counts.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-cp

[ "$(kubectl -n kube-system get pod kube-scheduler-cka-control-plane -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && p "kube-scheduler pod is Ready" || f "kube-scheduler pod is Ready"
docker exec cka-control-plane grep -q '^ *- kube-scheduler$' /etc/kubernetes/manifests/kube-scheduler.yaml 2>/dev/null && p "manifest command is kube-scheduler" || f "manifest command is kube-scheduler"
[ "$(kubectl -n $ns get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "web has 2 available pods" || f "web has 2 available pods"
[ -z "$(kubectl -n $ns get pods -l app=web -o jsonpath='{.items[?(@.status.phase=="Pending")].metadata.name}' 2>/dev/null)" ] && p "no Pending pods" || f "no Pending pods"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Deployment that creates nothing

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 7% |
| **Time** | 10 min |

**Question:**

The Deployment `api` in namespace `ts-cp` was created with 3 replicas but has no Pods at all, and `kubectl get rs -n ts-cp` shows nothing. Find the failing control-plane component on `cka-control-plane` and repair it. When you are done the Deployment must have 3 Pods Running.

<details>
<summary>💡 Hints</summary>

- A Deployment with no ReplicaSet means no controller is acting on it. Which kube-system Pod is restarting?
- kubectl -n kube-system logs  (or crictl logs on the node) prints the path it cannot open.
- Compare the flag with the hostPath volumes in the same manifest. Fix the file, and watch the Deployment catch up.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ts-cp get deploy,rs,pods
kubectl -n kube-system get pods
kubectl -n kube-system logs kube-controller-manager-cka-control-plane --tail=5 || true
docker exec cka-control-plane bash -c 'sed -i "/^ *- --kubeconfig=/s#controler-manager.conf#controller-manager.conf#" /etc/kubernetes/manifests/kube-controller-manager.yaml'
for i in $(seq 1 60); do
  [ "$(kubectl -n kube-system get pod kube-controller-manager-cka-control-plane -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && break
  sleep 3
done
kubectl -n ts-cp rollout status deploy/api --timeout=180s
kubectl -n ts-cp get deploy,rs,pods
```

**Explanation:**

- `get deploy,rs,pods` — The Deployment exists with 0/3 ready, but there is no ReplicaSet and no Pod. Creating the ReplicaSet is the controller-manager's job, which makes it the suspect.
- `kubectl -n kube-system get pods` — `kube-controller-manager-cka-control-plane` is in `CrashLoopBackOff`, its RESTARTS count rising.
- `--tail=5 || true` — The last 5 lines of its output end with *no such file or directory* for `/etc/kubernetes/controler-manager.conf`: one letter missing. `|| true` stops a failed `logs` from ending a script.
- `docker exec cka-control-plane bash -c 'sed -i` — Corrects the `--kubeconfig` flag in place. `#` separates the parts of the `s` command instead of `/`, so paths need no escaping. The kubelet sees the change and restarts the component.
- `for i in $(seq 1 60)` — The same wait loop as in the previous task, now for the controller-manager to report ready.
- `rollout status deploy/api` — Once the controller-manager holds its leader lease it creates the ReplicaSet and three Pods; this waits for all three.
- `get deploy,rs,pods` — Proof: one ReplicaSet and three Running Pods.

**Notes:** `kube-controller-manager-cka-control-plane` is in CrashLoopBackOff. Its log ends with *no such file or directory* for `/etc/kubernetes/controler-manager.conf`: one letter is missing. The manifest mounts the real file, `/etc/kubernetes/controller-manager.conf`, through a hostPath volume. So the fix is the `--kubeconfig` flag, not the volume. After the kubelet restarts the container, the controller manager needs a few seconds to win its leader lease. Then it creates the ReplicaSet and the Pods in one go. Your signal is `kubectl -n ts-cp get rs` going from empty to one line.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ts-cp

[ "$(kubectl -n kube-system get pod kube-controller-manager-cka-control-plane -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && p "kube-controller-manager pod is Ready" || f "kube-controller-manager pod is Ready"
docker exec cka-control-plane grep -q '^ *- --kubeconfig=/etc/kubernetes/controller-manager.conf$' /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null && p "manifest --kubeconfig points at controller-manager.conf" || f "manifest --kubeconfig points at controller-manager.conf"
[ "$(kubectl -n $ns get rs -l app=api --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] 2>/dev/null && p "a ReplicaSet exists for api" || f "a ReplicaSet exists for api"
[ "$(kubectl -n $ns get deploy api -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "api has 3 available pods" || f "api has 3 available pods"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
