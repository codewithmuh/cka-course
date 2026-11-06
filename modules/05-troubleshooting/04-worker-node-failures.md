# Worker node failures

> **Module 5** · Lesson 5.4 · 40 minutes

What NotReady means, how to read a node's conditions, and the four things that take a worker down on the exam: the kubelet stopped, its config broken, its certificate or kubeconfig wrong, or the container runtime gone.

## Learning Objectives

- You can read a node's Conditions and say whether the kubelet, the runtime, the disk or the network is the problem.
- You can bring a NotReady node back with systemctl, journalctl and a one-line fix in /var/lib/kubelet/config.yaml.
- You can predict what happens to the Pods on a node that stays down.


This lesson covers the exam topic **Troubleshoot clusters and nodes**. The part it is really about is the kubelet. A typical task says: *node X is NotReady, fix it*. You do the whole job on the node, over ssh, with three tools: `systemctl`, `journalctl` and a text editor. This lesson shows the order to use them in, and the files that matter.

## NotReady and the node conditions

Every 10 seconds the kubelet sends a heartbeat to say it is alive. If the controller manager hears nothing for 50 seconds, it sets the node's `Ready` condition to `Unknown`. `kubectl get nodes` then shows `NotReady`. But NotReady comes in two kinds, and they send you to different places:

**Two kinds of NotReady**

*Both show as NotReady in kubectl get nodes. kubectl describe node tells you which one it is, with a Reason and a Message.*

`Ready = False` — the kubelet runs and reports a problem
  - `Example` — the container runtime is down
  - `Look at` — the condition's Message, then the journal   `Ready = Unknown` — the kubelet has gone silent
  - `Example` — the kubelet was stopped
  - `Look at` (`systemctl status kubelet`)

Here is every node condition, with what to check. For Ready, trouble is False or Unknown. For the other conditions, trouble is True:

| Condition | What it means | What to check |
| --- | --- | --- |
| Ready = False | The kubelet runs, but something it needs is broken: the container runtime, the network plugin, or its own startup checks | the condition's Message, then `journalctl -u kubelet` |
| Ready = Unknown | No heartbeat for 50 seconds: the kubelet stopped or keeps crashing, it cannot reach the API server, or the node is off | `systemctl status kubelet` on the node. Can it reach the API server? |
| MemoryPressure = True | Memory is running out. The kubelet starts evicting Pods | `kubectl top node`: what is using the memory? |
| DiskPressure = True | The node's disk is nearly full. The kubelet evicts Pods and refuses new ones | `df -h` on the node |
| PIDPressure = True | Too many processes on the node | `ps` on the node: is a workload starting processes without end? |
| NetworkUnavailable = True | The network plugin has not set up the node | the network plugin's Pod on that node (calico-node in the lab) |

**First, read the node from your own terminal**

```bash
kubectl get nodes -o wide
kubectl describe node cka-worker2 | sed -n '/^Conditions:/,/^Addresses:/p'
kubectl describe node cka-worker2 | grep -A3 '^Taints'
kubectl get pods -A -o wide --field-selector spec.nodeName=cka-worker2
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get nodes -o wide` — Every node's STATUS (Ready or NotReady), version and internal IP. `-o wide` also adds the OS image, kernel and container runtime columns.
- `sed -n '/^Conditions:/,/^Addresses:/p'` — Prints only the part of describe from `Conditions:` to `Addresses:`. `sed -n` prints nothing by default and `p` prints that range, so you get just the conditions with their Status, Reason and Message.
- `grep -A3 '^Taints'` — The node's taints. A dead node gets `node.kubernetes.io/unreachable` or `not-ready` added automatically; a cordoned one gets `unschedulable`.
- `--field-selector spec.nodeName=cka-worker2` — Every Pod scheduled on `cka-worker2`, in all namespaces: the workloads at risk while that node is down.

</details>

## The kubelet: stopped, crash-looping, or misconfigured

On the node, the first command is always `systemctl status kubelet`. Its Active line gives one of three answers:

- **inactive (dead):** someone stopped it. `systemctl start kubelet` brings the node back within seconds. Then run `systemctl enable kubelet`, so a reboot does not undo it. The exam often checks this.
- **activating (auto-restart):** the kubelet starts and exits, again and again. Its journal says why, and it is almost always a wrong path in its config file.
- **active (running), but the node is still NotReady:** the kubelet runs but cannot do its job. Again the journal says why: usually the API server address, a certificate, or the container runtime.

**On the node (exam: ssh cka-worker2; lab: docker exec -it cka-worker2 bash)**

```bash
systemctl status kubelet --no-pager
journalctl -u kubelet -n 50 --no-pager          # the last 50 lines; the error repeats near the end
journalctl -u kubelet -f                         # follow while you fix; Ctrl-C to stop
systemctl start kubelet
systemctl enable kubelet
systemctl restart kubelet                        # after editing its configuration
systemctl is-active kubelet; systemctl is-enabled kubelet
```

<details>
<summary>Line-by-line explanation</summary>

- `systemctl status kubelet --no-pager` — `systemctl` manages system services, and the kubelet is one: it runs on the node itself, not as a Pod, which is why kubectl cannot start or fix it. The Active line reads *inactive (dead)*, *activating (auto-restart)* or *active (running)*.
- `journalctl -u kubelet -n 50` — The kubelet's last 50 log lines. A kubelet that fails at startup logs the same error on every retry, so the cause sits near the bottom.
- `journalctl -u kubelet -f` — Streams new kubelet lines as they are written, so you see the effect of each change. Ctrl+C gives you the prompt back.
- `systemctl start kubelet` — Starts a stopped kubelet now. It says nothing about the next boot.
- `systemctl enable kubelet` — Makes systemd start the kubelet at every boot. A task that says the fix must survive a reboot is checking exactly this.
- `systemctl restart kubelet` — Stops and starts the kubelet so it rereads `/var/lib/kubelet/config.yaml`. It reads that file only at startup, so an edit does nothing until you restart.
- `systemctl is-active kubelet; systemctl is-enabled kubelet` — Two one-word answers, `active` and `enabled`, proving both halves of the fix. The `;` runs the second command whatever the first returned.

</details>

## Where the kubelet's configuration lives

Two files hold almost everything that breaks:

| File | What it holds | How it breaks |
| --- | --- | --- |
| `/var/lib/kubelet/config.yaml` | The kubelet's settings: staticPodPath, clientCAFile, containerRuntimeEndpoint, clusterDNS, cgroupDriver | A wrong path or a YAML typo. The kubelet refuses to start |
| `/etc/kubernetes/kubelet.conf` | The kubelet's kubeconfig: the API server's address and the path of its client certificate | A wrong host or port. The kubelet runs, but the node stays NotReady and the journal shows *connection refused* |

**Check the two files**

```bash
grep -nE 'staticPodPath|clientCAFile|containerRuntimeEndpoint|clusterDNS|cgroupDriver' /var/lib/kubelet/config.yaml
grep server: /etc/kubernetes/kubelet.conf
```

<details>
<summary>Line-by-line explanation</summary>

- `grep -nE` — Pulls the five settings that break most often out of the kubelet's configuration, with line numbers, so you can jump straight there in vim (`:12` goes to line 12). `-E` lets `|` mean *or*.
- `grep server: /etc/kubernetes/kubelet.conf` — The API server address the kubelet connects to. A wrong host or port here leaves the kubelet running but unable to report, so the node stays NotReady.

</details>

Here is the most common case, a broken `config.yaml`:

- **Symptom:** `systemctl status kubelet` says *activating (auto-restart)*.
- **Cause:** the journal names it. For example: *failed to run Kubelet: unable to load client CA file /etc/kubernetes/pki/ca.crtt: open …: no such file or directory*. A YAML typo gives an error with a line number instead.
- **Fix:** run `ls -l` on the path it quotes, correct the file, then run `systemctl restart kubelet`.

## An expired kubelet certificate

The kubelet proves who it is to the API server with a client certificate. Normally it renews that certificate by itself, before it expires. But if the node is off for longer than the certificate lasts, the certificate expires:

- **Symptom:** the kubelet is active, but the node stays NotReady. The journal shows *Unauthorized* or *x509: certificate has expired*.
- **Check:** `openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates` prints the certificate's dates.
- **Fix:** the node needs a new client certificate, through the CSR API, or it must join the cluster again. [Certificates, kubeconfig and the CSR API](/cka/architecture/certificates-and-kubeconfig) covers certificates.

## Container runtime down, disk full

| Problem | What you see | Fix |
| --- | --- | --- |
| containerd stopped | Ready = False, with reason `KubeletNotReady`. The journal repeats *container runtime is down*, and `crictl ps` fails | `systemctl start containerd`, then `systemctl enable containerd`. The kubelet reconnects by itself |
| Disk full | DiskPressure. Pods show `Evicted`, and no new Pods land on the node | `df -h` on the node shows which disk is full. `crictl rmi --prune` removes unused images |

## What happens to the Pods on a NotReady node

**When a node stays down**

*Nothing moves for about six minutes, so a short outage evicts nothing.*

`The kubelet stops` — containers keep running → `About 50 seconds later` — NotReady: tainted, no new Pods → `5 minutes after that` — Pods evicted, recreated elsewhere

- **The first minutes:** the containers keep running. About 50 seconds after the last heartbeat, the node is marked NotReady and gets a `NoExecute` taint: `node.kubernetes.io/unreachable`, or `not-ready` for Ready = False. The scheduler stops placing Pods there, and its Pods drop out of their Services.
- **About 5 minutes later:** every Pod has a default toleration for these taints that lasts 300 seconds. When it runs out, the Pods are deleted, and their Deployments create new ones on healthy nodes. The old Pods show `Terminating` until the kubelet comes back.
- **Exceptions:** DaemonSet Pods stay. Bare Pods are deleted and never come back. StatefulSet Pods are not replaced until the old one is really gone, so you must force-delete it.

If a sick node is still reachable, you do not have to wait: `kubectl drain` moves its Pods away now. [Upgrading clusters and draining nodes](/cka/architecture/cluster-upgrades) teaches cordon and drain.

## The node checklist on one screen

| Symptom | Check | Fix |
| --- | --- | --- |
| NotReady, Ready = Unknown | `ssh `, then `systemctl status kubelet` | `systemctl start kubelet`, then `systemctl enable kubelet` |
| kubelet activating (auto-restart) | `journalctl -u kubelet -n 50` | fix the path or key it quotes in /var/lib/kubelet/config.yaml, then restart the kubelet |
| kubelet active, node NotReady, *connection refused* in the journal | `grep server: /etc/kubernetes/kubelet.conf` | fix the host or port, then restart the kubelet |
| kubelet active, *Unauthorized* or *x509* in the journal | `openssl x509 -noout -dates -in /var/lib/kubelet/pki/kubelet-client-current.pem` | get a new kubelet client certificate (CSR, or join again) |
| Ready = False, KubeletNotReady, runtime down | `systemctl status containerd`, then `crictl ps` | `systemctl start containerd` |
| DiskPressure, Evicted Pods | `df -h`, then `crictl rmi --prune` | free up the disk, and find what fills it |
| Pods Terminating for a long time on a dead node | `kubectl get nodes` | bring the node back, or delete the Pods with `--force --grace-period=0` |

> [!IMPORTANT] **ssh in, fix, exit, prove it from outside**
> The grader checks that the node is Ready. Often it also checks that the fix lasts: the kubelet *enabled*, and the config file corrected. Work on the node, then `exit` and run `kubectl get nodes` from your own terminal. kubectl on a worker has no kubeconfig. Its *connection refused to localhost:8080* error has made more than one candidate think they broke the cluster.

> [!WARNING] **These tasks take cka-worker2 down on purpose**
> The two disruptive tasks below stop or break the kubelet on `cka-worker2`. Their cleanup restores the file, starts the kubelet and waits for Ready. But for a minute or two in between, kubectl cannot reach the Pods on that node. Run them one at a time, with nothing else running on the lab.

## 📝 Key Takeaways

- NotReady comes in two kinds. Ready = False: the kubelet runs and reports a problem. Ready = Unknown: the kubelet is silent.
- On the node, start with `systemctl status kubelet`, then read `journalctl -u kubelet`. The error repeats near the end.
- A stopped kubelet needs `start` and `enable`. A config fix needs `systemctl restart kubelet`, because the kubelet reads its file only at startup.
- Pods on a dead node are evicted only after about 5 minutes. Then their Deployments recreate them on healthy nodes.
- Exit the node and prove the fix with `kubectl get nodes` from your own terminal.

**📖 Official documentation:**

- [Nodes](https://kubernetes.io/docs/concepts/architecture/nodes/) *(search: "node heartbeats")*
- [Node Status](https://kubernetes.io/docs/reference/node/node-status/) *(search: "node conditions")*
- [Kubelet Configuration (v1beta1)](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/) *(search: "kubelet configuration")*
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) *(search: "taint based evictions")*

---

### 🎯 Task: Find a node by role and record its address

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 2% |
| **Time** | 3 min |

**Question:**

Find the node that carries the control-plane role (the label `node-role.kubernetes.io/control-plane`) and write its `InternalIP` address, and nothing else, to `/tmp/cka/control-plane-ip.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl get nodes -l node-role.kubernetes.io/control-plane -o wide shows the INTERNAL-IP column.
- For a single value, use jsonpath: {.items[0].status.addresses[?(@.type=="InternalIP")].address}.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl get nodes -l node-role.kubernetes.io/control-plane -o wide
kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' > /tmp/cka/control-plane-ip.txt
cat /tmp/cka/control-plane-ip.txt; echo
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answer folder if needed.
- `control-plane -o wide` — `-l` with only a label key matches every node that has that label, whatever its value. Only the control plane has it; INTERNAL-IP is the column you want.
- `-o jsonpath='{.items[0]` — Writes only the address: `items[0]` is the first matching node, and `[?(@.type=="InternalIP")]` picks that one entry from its list of addresses. `>` sends it to the file.
- `cat /tmp/cka/control-plane-ip.txt; echo` — Shows the file. jsonpath wrote no line break, so `echo` adds one to keep your prompt off the address.

**Notes:** On the exam, `-o wide` and copying the INTERNAL-IP by hand is fine. Make sure the file holds only the address: no node name and no extra text. `kubectl describe node` shows the same value under Addresses. Role labels are plain labels with an empty value, `node-role.kubernetes.io/control-plane=`. That is why the selector needs no value either.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/control-plane-ip.txt

[ -s "$file" ] && p "file $file exists" || f "file $file exists"
want=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
got=$(tr -d '[:space:]' < "$file" 2>/dev/null)
[ -n "$want" ] && [ "$got" = "$want" ] && p "file holds the control-plane InternalIP ($want)" || f "file holds the control-plane InternalIP (want $want, got '$got')"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Bring a NotReady node back

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

The node `cka-worker2` is reported as NotReady. Investigate on the node and bring it back to Ready. The fix must survive a reboot of the node.

<details>
<summary>💡 Hints</summary>

- describe node cka-worker2: is Ready False (the kubelet reports a problem) or Unknown (the kubelet is silent)?
- On the node: systemctl status kubelet. Then start it, and make sure it is enabled.
- Lab: docker exec -it cka-worker2 bash. Exam: ssh cka-worker2.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get node cka-worker2 -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'; echo
docker exec cka-worker2 systemctl is-active kubelet || true
docker exec cka-worker2 systemctl start kubelet
docker exec cka-worker2 systemctl enable kubelet
kubectl wait --for=condition=Ready node/cka-worker2 --timeout=120s
kubectl get nodes
```

**Explanation:**

- `{.status.conditions[?(@.type=="Ready")]}` — Prints the node's Ready condition as JSON. Status `Unknown` with *Kubelet stopped posting node status* means the kubelet has gone silent, so the problem is on the node itself.
- `systemctl is-active kubelet || true` — `docker exec cka-worker2` runs one command on the lab node; on the exam you would `ssh cka-worker2` and `sudo -i` first. It prints `inactive`, and `|| true` ignores the error code that comes with that answer.
- `systemctl start kubelet` — Starts the kubelet. Within seconds it sends a heartbeat and the node turns Ready.
- `systemctl enable kubelet` — The reboot part of the task: without it the kubelet would stay stopped the next time the node boots.
- `kubectl wait --for=condition=Ready node/cka-worker2` — `wait` works on nodes as on Pods: it returns once the Ready condition is True, or fails after 120 seconds.
- `kubectl get nodes` — Final check from your own terminal: all three nodes Ready.

**Notes:** Ready is `Unknown`, with the message *Kubelet stopped posting node status*: the kubelet is silent. On the node, `systemctl status kubelet` says *inactive (dead)*. `systemctl start kubelet` makes the node Ready within seconds. `systemctl enable kubelet` is the part of the question about reboots, and `systemctl is-enabled kubelet` proves it. If you fixed it within about five minutes, nothing on the node was evicted: the outage was shorter than the 300-second default toleration.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

[ "$(kubectl get node cka-worker2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "cka-worker2 is Ready" || f "cka-worker2 is Ready"
[ "$(docker exec cka-worker2 systemctl is-active kubelet 2>/dev/null)" = "active" ] && p "kubelet is active" || f "kubelet is active"
[ "$(docker exec cka-worker2 systemctl is-enabled kubelet 2>/dev/null)" = "enabled" ] && p "kubelet is enabled" || f "kubelet is enabled"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A kubelet that will not start

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 7% |
| **Time** | 10 min |

**Question:**

The node `cka-worker2` went NotReady after a configuration change on the node. The kubelet's configuration file must stay where it is. Find the problem, fix it and make the node Ready again.

<details>
<summary>💡 Hints</summary>

- On the node: systemctl status kubelet shows activating (auto-restart). The kubelet exits as soon as it starts.
- journalctl -u kubelet -n 30 --no-pager: the last error quotes a file path. Run ls -l on that path.
- Fix the path in /var/lib/kubelet/config.yaml, then run systemctl restart kubelet.

</details>

<details>
<summary>✅ Solution</summary>

```bash
docker exec cka-worker2 systemctl status kubelet --no-pager | head -12 || true
docker exec cka-worker2 journalctl -u kubelet -n 20 --no-pager | grep -i -m3 'ca.crt' || true
docker exec cka-worker2 grep -n clientCAFile /var/lib/kubelet/config.yaml
docker exec cka-worker2 sed -i "s#clientCAFile: /etc/kubernetes/pki/ca.crtt#clientCAFile: /etc/kubernetes/pki/ca.crt#" /var/lib/kubelet/config.yaml
docker exec cka-worker2 systemctl restart kubelet
kubectl wait --for=condition=Ready node/cka-worker2 --timeout=120s
kubectl get nodes
```

**Explanation:**

- `systemctl status kubelet --no-pager | head -12` — The top of the status output, where the Active line reads *activating (auto-restart)*: the kubelet exits right after starting and systemd keeps retrying. `head -12` keeps the first 12 lines.
- `grep -i -m3 'ca.crt'` — Searches the last 20 kubelet lines for `ca.crt`, ignoring case, stopping after 3 hits. You find *unable to load client CA file /etc/kubernetes/pki/ca.crtt*: a path with one letter too many.
- `grep -n clientCAFile` — Shows that setting in the kubelet's configuration file with its line number, confirming the bad path is written there.
- `sed -i` — Replaces the wrong path with the right one in the file itself. `#` separates the parts of `s#old#new#`, so the slashes in the paths need no escaping. On the exam: `vim /var/lib/kubelet/config.yaml` on the node.
- `systemctl restart kubelet` — The kubelet reads its configuration only at startup, so restart it to load the fix. This time it stays running.
- `kubectl wait --for=condition=Ready` — Waits up to 120 seconds for the node to report Ready again.
- `kubectl get nodes` — All three nodes Ready, checked from outside the node: the same view the grader has.

**Notes:** `systemctl status kubelet` shows *activating (auto-restart) (Result: exit-code)*. The journal ends with *unable to load client CA file /etc/kubernetes/pki/ca.crtt: … no such file or directory*. `ls /etc/kubernetes/pki/` shows the real file is `ca.crt`. On the exam: open `/var/lib/kubelet/config.yaml` in vim, fix `clientCAFile`, and run `systemctl restart kubelet`. Then `exit` and run `kubectl get nodes`. Had the problem been in the kubelet's kubeconfig instead, the file would be `/etc/kubernetes/kubelet.conf`. The symptom would then be an active kubelet that cannot connect.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

[ "$(kubectl get node cka-worker2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "cka-worker2 is Ready" || f "cka-worker2 is Ready"
[ "$(docker exec cka-worker2 systemctl is-active kubelet 2>/dev/null)" = "active" ] && p "kubelet is active" || f "kubelet is active"
docker exec cka-worker2 grep -q '^ *clientCAFile: /etc/kubernetes/pki/ca.crt$' /var/lib/kubelet/config.yaml 2>/dev/null && p "clientCAFile points at /etc/kubernetes/pki/ca.crt" || f "clientCAFile points at /etc/kubernetes/pki/ca.crt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
