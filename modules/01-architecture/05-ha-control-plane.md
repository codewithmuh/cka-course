# Highly available control planes

> **Module 1** · Lesson 1.5 · 35 minutes

Stacked or external etcd, quorum math, a load balancer in front of the API servers, and the kubeadm flags that add more control plane nodes.

## Learning Objectives

- You can explain stacked and external etcd, and say how many failures three or five etcd members survive.
- You can start a cluster with a load-balanced controlPlaneEndpoint and join more control plane nodes with --control-plane and --certificate-key.
- You can read how an existing cluster's control plane is laid out, from the kubeadm-config ConfigMap and the API server's flags.


A **highly available (HA)** control plane keeps working when one control plane machine dies. You get it by running the control plane on three machines instead of one. Example: your cluster has one control plane node and its disk fails. Running apps keep going, but nobody can deploy, scale or fix anything until it is back. With three control plane nodes, the other two carry on.

This lesson covers the exam topic **Implement and configure a highly-available control plane**. The exam will not make you build a load balancer. It can ask you to join another control plane node, or to say how many etcd members may fail. It can also ask how a cluster is laid out.

**An HA control plane with stacked etcd**

*Everyone uses one address, the load balancer. It passes each request to any healthy API server.*

`Clients` — kubectl, kubelets and joining nodes → `Load balancer` — the controlPlaneEndpoint (`k8s-api.lab.internal:6443`) → `Three control plane nodes`
  - `cp1` — API server, etcd, scheduler, controller manager
  - `cp2` — the same
  - `cp3` — the same

## What has to be redundant

In an HA cluster, each control plane part runs on several machines. But the copies work together in different ways:

| Part | Holds data? | How the copies work together |
| --- | --- | --- |
| API server | No | All copies serve requests at the same time. A load balancer in front spreads requests across them. |
| Scheduler, controller manager | No | Only one copy works at a time, the leader. The others wait, ready to take over. |
| etcd | Yes, all cluster data | Every write needs a majority of the members to agree. This is the hard part. |

## Quorum: why three members, not two or four

**Quorum** means a majority of the etcd members. etcd saves a write only once a quorum has it. The formula is `floor(n/2) + 1`: half the members, rounded down, plus one. Example: with 3 members, quorum is 2, so 1 member can fail.

| etcd members | Quorum (majority) | Failures tolerated |
| --- | --- | --- |
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |

- **Even numbers add nothing.** 4 members survive 1 failure, the same as 3, with one more machine that can break. 2 members are worse than 1.
- **Run 3, or 5** if you must survive 2 failures. More members make every write wait for more machines.
- **When quorum is lost, nothing can change.** The API server cannot save anything. Running Pods keep running, but you cannot create, change or delete objects.

*[Interactive visual: etcd-quorum]*

## Stacked or external etcd

There are two ways to place etcd. **Stacked**: each control plane node also runs an etcd member, so 3 machines give you 3 API servers and 3 etcd members. This is what kubeadm builds by default. **External**: etcd runs on its own machines, so the same takes 6 machines.

|  | Stacked etcd | External etcd |
| --- | --- | --- |
| Where etcd runs | A static Pod on every control plane node. kubeadm creates it. | On its own machines, usually as a Linux service, set up before `kubeadm init` |
| The API server talks to | Its own local member: `--etcd-servers=https://127.0.0.1:2379` | Every member: `--etcd-servers=https://10.0.0.21:2379,https://10.0.0.22:2379,…` |
| Machines for three of each | 3 | 6 |
| When one machine fails | You lose an API server and an etcd member together | The control plane and etcd fail separately |
| In kubeadm-config | `etcd.local` | `etcd.external`, with the members' addresses and client certificate paths |
| `etcd.yaml` in the manifests folder | Yes | No |

## Building it with kubeadm

You build an HA cluster with the same `kubeadm init` and `kubeadm join` as a normal one, plus four flags:

| Flag | Used with | What it does |
| --- | --- | --- |
| `--control-plane-endpoint` | `kubeadm init` | The one shared address of all API servers: the load balancer. |
| `--upload-certs` | `kubeadm init` | Stores the shared certificates in the cluster, encrypted, for two hours, so new control plane nodes can download them. |
| `--control-plane` | `kubeadm join` | Makes the new node a control plane node, not a worker. |
| `--certificate-key` | `kubeadm join` | The key that unlocks the uploaded certificates. |

**First control plane, then the others**

```bash
# First control plane. The endpoint is the load balancer's DNS name (or VIP) and port.
sudo kubeadm init \
  --control-plane-endpoint "k8s-api.lab.internal:6443" \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16

# kubeadm prints two join commands. The control plane one adds two flags:
sudo kubeadm join k8s-api.lab.internal:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key>

# Two hours later the uploaded certificates are gone. On an existing control plane:
sudo kubeadm init phase upload-certs --upload-certs                  # prints a new key
sudo kubeadm token create --print-join-command --certificate-key <new-key>
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo kubeadm init` — Initializes the first control plane node. Each `\` continues the command on the next line.
- `--control-plane-endpoint` — The shared address of all API servers: the load balancer, not this node. kubeconfigs and joining nodes use it, and kubeadm cannot add it later to turn a single control plane into HA, so set it from the start.
- `--upload-certs` — Uploads the shared CA and key files, encrypted, into the `kubeadm-certs` Secret, so new control plane nodes can download them instead of you copying them by hand.
- `sudo kubeadm join k8s-api.lab.internal:6443` — The join targets the load balancer address. The token and hash work exactly as for a worker.
- `--control-plane --certificate-key` — `--control-plane` makes this node a control plane with its own API server and etcd member; `--certificate-key` decrypts the uploaded certificates. Leave both out and it joins as a plain worker.
- `upload-certs --upload-certs` — Uploads the certificates again and prints a new key, which you need once the old Secret has expired after two hours.
- `--print-join-command --certificate-key` — Creates a fresh token and prints a complete control plane join command with the new key in it.

</details>

`controlPlaneEndpoint` is the one address that every kubeconfig, kubelet and joining node uses. Set it on day one, even with a single control plane node: kubeadm cannot turn a cluster built without it into an HA one later. On this kind lab it is `cka-control-plane:6443`.

With external etcd you use a config file instead of flags. Only the `etcd` part differs:

**External etcd in a kubeadm config file (kubeadm init --config … --upload-certs)**

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
controlPlaneEndpoint: "k8s-api.lab.internal:6443"
etcd:
  external:
    endpoints:
      - https://10.0.0.21:2379
      - https://10.0.0.22:2379
      - https://10.0.0.23:2379
    # plus caFile, certFile and keyFile: the client certificate the API server uses for etcd
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: kubeadm.k8s.io/v1beta4` — kubeadm's own configuration format, read by `kubeadm init --config`. It is not a cluster object, so you never apply it with kubectl.
- `kind: ClusterConfiguration` — The cluster-wide settings. kubeadm saves this part in the `kubeadm-config` ConfigMap, which is where you read it back later.
- `controlPlaneEndpoint:` — The config-file form of `--control-plane-endpoint`: the load balancer address every component and joining node uses.
- `external:` — `external` tells kubeadm that etcd already runs on other hosts, so it creates no etcd static Pod. A stacked cluster has `local` here instead.
- `endpoints:` — Every etcd member's client URL. The API server gets them all in its `--etcd-servers` flag.

</details>

## Reading an existing cluster's layout

Exam questions about HA are mostly about reading. kubeadm saved its choices in the `kubeadm-config` ConfigMap, and the API server's flags show which etcd members it uses:

**Reading the layout of a running cluster**

```bash
# What kubeadm decided at init time
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep '^controlPlaneEndpoint:'
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -A3 '^etcd:'

# Which etcd members the API server uses (one argument per line, so commas stay intact)
kubectl -n kube-system get pod -l component=kube-apiserver \
  -o jsonpath='{range .items[0].spec.containers[0].command[*]}{@}{"\n"}{end}' | grep -- --etcd-servers

# Control plane nodes and their Pods
kubectl get nodes -l node-role.kubernetes.io/control-plane
kubectl -n kube-system get pods -l tier=control-plane -o wide
```

<details>
<summary>Line-by-line explanation</summary>

- `grep '^controlPlaneEndpoint:'` — The `kubeadm-config` ConfigMap holds the ClusterConfiguration as one block of YAML text. This prints only its `controlPlaneEndpoint` line; `^` means at the start of a line.
- `grep -A3 '^etcd:'` — Prints the `etcd:` line and the 3 lines after it (`-A3`). `local:` under it means stacked etcd; `external:` with a list of endpoints means external.
- `command[*]}{@}` — Loops over the API server's arguments and prints each on its own line; `{@}` is the current item. Unlike splitting on commas, this keeps a comma-separated `--etcd-servers` list in one piece.
- `kubectl get nodes -l node-role.kubernetes.io/control-plane` — Lists only nodes that carry the control-plane role label, which tells you how many control plane nodes there are.
- `get pods -l tier=control-plane -o wide` — kubeadm labels its static Pods `tier=control-plane`. `-o wide` shows the node of each; with stacked etcd, every control plane node has its own etcd Pod.

</details>

> [!IMPORTANT] **HA on the exam is reading and joining**
> A join question is graded on the new node: `Ready`, with the `control-plane` role, and its own etcd and API server Pods running. The trap when joining is the pair `--control-plane --certificate-key`. Leave them out and the node quietly joins as a worker. Use an expired key and the join fails while downloading certificates. Then run `kubeadm init phase upload-certs --upload-certs` on an existing control plane and make a fresh join command.

## 📝 Key Takeaways

- HA means several control plane nodes behind one address, the `controlPlaneEndpoint` (a load balancer). Set it at `kubeadm init`; it cannot be added later.
- Quorum is a majority: `floor(n/2) + 1`. 3 etcd members survive 1 failure, 5 survive 2. Even numbers add nothing.
- Stacked etcd runs on the control plane nodes (`etcd.local`). External etcd runs on its own machines (`etcd.external`).
- A control plane join needs `--control-plane --certificate-key`. The uploaded certificates expire after two hours.

**📖 Official documentation:**

- [Options for Highly Available Topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/) *(search: "ha topology")*
- [Creating Highly Available Clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/) *(search: "highly available kubeadm")*
- [Set up a High Availability etcd Cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/) *(search: "high availability etcd kubeadm")*

---

### 🎯 Task: Describe this cluster's control plane layout

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Find out how this cluster's control plane is wired, without changing anything, and write each answer as a bare value. (1) The control plane endpoint kubeadm configured, as `host:port`, to `/tmp/cka/ar-cp-endpoint.txt`. (2) The etcd topology, as the single word `stacked` or `external`, to `/tmp/cka/ar-etcd-topology.txt`. (3) The full value of kube-apiserver's `--etcd-servers` flag to `/tmp/cka/ar-etcd-servers.txt`. (4) If this cluster were grown to five control plane nodes with the same etcd topology, how many etcd members could fail at once without losing quorum? Write the number to `/tmp/cka/ar-etcd-tolerance.txt`.

<details>
<summary>💡 Hints</summary>

- kubeadm saves its ClusterConfiguration in a ConfigMap in kube-system.
- With stacked etcd there is one member per control plane node. Quorum is floor(n/2)+1.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
CC=$(kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')
echo "$CC" | awk '/^controlPlaneEndpoint:/ {print $2}' > /tmp/cka/ar-cp-endpoint.txt
if echo "$CC" | grep -q '^  local:'; then echo stacked; else echo external; fi > /tmp/cka/ar-etcd-topology.txt
docker exec cka-control-plane grep -- '--etcd-servers=' /etc/kubernetes/manifests/kube-apiserver.yaml | cut -d= -f2- | tr -d ' ' > /tmp/cka/ar-etcd-servers.txt
echo 2 > /tmp/cka/ar-etcd-tolerance.txt
cat /tmp/cka/ar-cp-endpoint.txt /tmp/cka/ar-etcd-topology.txt /tmp/cka/ar-etcd-servers.txt /tmp/cka/ar-etcd-tolerance.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answers folder if needed.
- `CC=$(kubectl` — Saves the ClusterConfiguration text in the variable `CC`, so the next two lines read it without asking the API again.
- `awk '/^controlPlaneEndpoint:/` — Prints the value after `controlPlaneEndpoint:`, which is `cka-control-plane:6443` on this lab. The quotes in `"$CC"` keep its line breaks, so awk sees one setting per line.
- `grep -q '^  local:'` — A `local:` key indented under `etcd:` means stacked; otherwise the answer is external. `-q` keeps grep silent, so it only tells `if` whether it found a match.
- `cut -d= -f2-` — Reads the flag from the API server manifest. `cut -d= -f2-` keeps everything after the first `=` (field 2 to the end), and `tr -d ' '` removes stray spaces.
- `echo 2 >` — Five members have a quorum of three, floor(5/2) + 1, so two can fail.
- `cat /tmp/cka/ar-cp-endpoint.txt` — Review all four answers before you move on.

**Notes:** The quickest exam route is `kubectl -n kube-system get cm kubeadm-config -o yaml`. `controlPlaneEndpoint` is a top-level field. Under `etcd`, `local` means stacked and `external` means external. You can also look in the control plane's manifests folder: an `etcd.yaml` there means stacked. For the flag, `cut -d= -f2-` keeps everything after the first `=`, so the whole value survives even if it contains another `=` (a comma-separated list of members does not need it, but it costs nothing). Five members have a quorum of three, so two can fail.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
val() { tr -d '[:space:]' 2>/dev/null < "$1"; }

cc=$(kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null)
want_ep=$(echo "$cc" | awk '/^controlPlaneEndpoint:/ {print $2}')
if echo "$cc" | grep -q '^  external:'; then want_topo=external; else want_topo=stacked; fi
want_es=$(kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{range .items[0].spec.containers[0].command[*]}{@}{"\n"}{end}' 2>/dev/null | grep '^--etcd-servers=' | cut -d= -f2-)

[ -n "$want_ep" ] && [ "$(val /tmp/cka/ar-cp-endpoint.txt)" = "$want_ep" ] && p "control plane endpoint is $want_ep" || f "control plane endpoint in /tmp/cka/ar-cp-endpoint.txt"
[ -n "$cc" ] && [ "$(val /tmp/cka/ar-etcd-topology.txt | tr 'A-Z' 'a-z')" = "$want_topo" ] && p "etcd topology is $want_topo" || f "etcd topology in /tmp/cka/ar-etcd-topology.txt"
[ -n "$want_es" ] && [ "$(val /tmp/cka/ar-etcd-servers.txt)" = "$want_es" ] && p "--etcd-servers is $want_es" || f "--etcd-servers value in /tmp/cka/ar-etcd-servers.txt"
[ "$(val /tmp/cka/ar-etcd-tolerance.txt)" = "2" ] && p "five members tolerate 2 failures" || f "failure tolerance in /tmp/cka/ar-etcd-tolerance.txt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Join a third control plane node

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 12 min |

**Question:**

Clients reach this cluster's API through a load balancer at `k8s-api.lab.internal:6443`. Control plane nodes `cp1` and `cp2` run stacked etcd. Node `cp3` is prepared with containerd and v1.37 packages and is already in the load balancer's backend pool. Join `cp3` as a third control plane node. The cluster was initialized days ago, so neither its bootstrap token nor its certificate key is valid anymore. You work on `cp1`; `ssh cp3` reaches the new node.

<details>
<summary>💡 Hints</summary>

- Upload the control plane certificates again first. The command prints a new certificate key.
- kubeadm token create --print-join-command accepts --certificate-key, and then prints a control plane join command.

</details>

<details>
<summary>✅ Solution</summary>

```bash
# On cp1
KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -1)
JOIN=$(sudo kubeadm token create --print-join-command --certificate-key "$KEY")
echo "$JOIN"
ssh cp3 "sudo $JOIN" </dev/null
kubectl wait --for=condition=Ready node/cp3 --timeout=300s
kubectl -n kube-system get pods -l tier=control-plane -o wide
```

**Explanation:**

- `KEY=$(sudo kubeadm init phase upload-certs` — Re-uploads the shared control plane certificates and keeps the new certificate key, which kubeadm prints as the last line of its output (`tail -1`).
- `JOIN=$(sudo kubeadm token create` — Creates a fresh token and builds a join command. Passing `--certificate-key` makes it the control plane version, ending in `--control-plane --certificate-key`.
- `echo "$JOIN"` — Check that both control plane flags are there before it runs.
- `ssh cp3` — Runs the join on `cp3` with sudo. Your shell fills in `$JOIN` before ssh sends it.
- `node/cp3 --timeout=300s` — A control plane join pulls more images and starts more Pods than a worker join, so allow up to 300 seconds.
- `get pods -l tier=control-plane -o wide` — `cp3` should now run its own etcd, API server, controller manager and scheduler; `-o wide` shows the node of each Pod.

**Notes:** The printed command ends in `--control-plane --certificate-key `. Check that both are there before you run it on `cp3`. After the join, `cp3` runs its own etcd member, API server, controller manager and scheduler as static Pods. etcd now has three members, so it survives one failure. If the join fails half way, run `sudo kubeadm reset -f` on `cp3`. If its etcd member had already joined, it may also need removing with `etcdctl member remove` before you try again.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

[ "$(kubectl get node cp3 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "cp3 is Ready" || f "cp3 is Ready"
kubectl get node cp3 --show-labels --no-headers 2>/dev/null | grep -q 'node-role.kubernetes.io/control-plane' && p "cp3 has the control-plane role" || f "cp3 has the control-plane role"
for c in etcd kube-apiserver kube-controller-manager kube-scheduler; do
  [ "$(kubectl -n kube-system get pod $c-cp3 -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "$c-cp3 is Running" || f "$c-cp3 is Running"
done
[ "$(kubectl -n kube-system get pods -l component=etcd --no-headers 2>/dev/null | grep -c Running)" = "3" ] && p "three etcd members are running" || f "three etcd members are running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
