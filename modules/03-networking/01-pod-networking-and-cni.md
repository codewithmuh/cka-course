# Pod networking and CNI

> **Module 3** · Lesson 3.1 · 35 minutes

How Pods get IP addresses and reach each other, the two address ranges of a cluster, and how to test a connection.

## Learning Objectives

- You can state the three rules of the Kubernetes network model, and say which part makes each one work.
- You can read the Pod and Service ranges from the control plane, and tell them apart from a node's podCIDR.
- You can find any Pod's IP and node, then test Pod-to-Pod traffic from a temporary client Pod.


Every Pod in a cluster gets its own IP address, and any Pod can reach any other Pod at that address. This lesson shows who hands out those addresses, how traffic travels between nodes, and how to test it. The exam calls this **Understand connectivity between Pods**. It is rarely a task on its own, but every Service, NetworkPolicy and troubleshooting question builds on it.

## The network model in three rules

Kubernetes sets three rules for the network. Every cluster must follow them.

- **Every Pod gets its own IP address.** All containers in one Pod share it, and they reach each other on `localhost`. So two containers in one Pod cannot both use port 8080.
- **Any Pod can reach any other Pod at its real IP.** A Pod on `cka-worker` calls a Pod on `cka-worker2` directly. No address is rewritten on the way (no NAT), so the receiver sees the caller's real IP.
- **Programs on a node can reach every Pod on that node.** That is how the kubelet runs liveness and readiness probes.

## CNI plugin and kube-proxy: two parts, two jobs

Kubernetes only writes these rules down. Two other parts make them work, and their jobs are easy to mix up:

| Part | Its job | Example |
| --- | --- | --- |
| **CNI plugin**: the cluster's network add-on (Calico in this lab) | Gives each Pod an IP address and carries traffic from Pod to Pod | Pod A calls Pod B at `10.244.157.130` |
| **kube-proxy**: a helper on every node | Makes Service addresses work, on top of the Pod network | Pod A calls Service `api` and lands on one of its Pods |

So Pod-to-Pod is the CNI plugin, and Pod-to-Service is kube-proxy. Other CNI plugins you may meet are Cilium and Flannel. This lesson covers the CNI side; [Services](/cka/networking/services) covers kube-proxy.

## Two address ranges: Pod CIDR and Service CIDR

Every cluster has two separate ranges of IP addresses. Pods get their addresses from one, Services from the other. A range is written as a **CIDR**: `10.244.0.0/16` means every address that starts with `10.244.`.

**Two address ranges**

*The two ranges never overlap. Pod addresses are real; a Service address is virtual and sits on no network interface.*

`Pod CIDR` — Pod IPs, handed out by the CNI plugin (`10.244.0.0/16`)   `Service CIDR` — Service IPs, handed out by the API server (`10.96.0.0/16`)

| Range | What uses it | Where it is set | This lab |
| --- | --- | --- | --- |
| Pod CIDR (also called the cluster CIDR) | Pod IPs. The CNI plugin hands them out. | `--cluster-cidr` on kube-controller-manager (`networking.podSubnet` in kubeadm). The CNI plugin's own pool must match it. | 10.244.0.0/16 |
| Node podCIDR | One node's slice of the Pod CIDR | `spec.podCIDR` on each Node. The controller manager fills it in when `--allocate-node-cidrs=true`. | 10.244.0.0/24, 10.244.1.0/24, … |
| Service CIDR | Service ClusterIPs. No network interface ever has these addresses. | `--service-cluster-ip-range` on kube-apiserver (`networking.serviceSubnet` in kubeadm) | 10.96.0.0/16 |

**Read both ranges from the control plane**

```bash
# Node shell. Lab: docker exec. Exam: ssh <control-plane-node>, then sudo -i if needed.
docker exec cka-control-plane grep -- --cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml
docker exec cka-control-plane grep -- --service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml

# Each node's own slice of the Pod range (not the cluster's Pod CIDR)
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
```

<details>
<summary>Line-by-line explanation</summary>

- `grep -- --cluster-cidr` — Runs `grep` inside the control-plane node container and prints the line of the kube-controller-manager manifest that sets `--cluster-cidr`, the Pod range. The lone `--` tells grep that what follows is the text to find, not one of its own options.
- `grep -- --service-cluster-ip-range` — The same search in the kube-apiserver manifest, for the Service range. Files in `/etc/kubernetes/manifests` are static Pod manifests: kubelet runs whatever it finds there.
- `PODCIDR:.spec.podCIDR` — Each node's own slice of the Pod range. Good to know, but not the answer when a task asks for the cluster's Pod CIDR, as the box below explains.

</details>

No node shell? The same flags are visible through the API too, as [Control plane and node components](/cka/architecture/control-plane-and-nodes) shows.

> [!WARNING] **A trap: a node's podCIDR is not the Pod CIDR**
> Each node shows a podCIDR, such as `10.244.1.0/24`. But Calico ignores it. It cuts its own pool (`10.244.0.0/16`) into blocks of 64 addresses and gives them to nodes as needed. So a Pod on `cka-worker` often has an IP outside that node's podCIDR. When a question asks for the cluster's Pod CIDR, give the whole range from `--cluster-cidr`.

## How the CNI plugin connects a Pod

When a new Pod starts on a node, the container runtime calls the CNI plugin. The plugin does three jobs:

1. **It plugs the Pod in.** It creates a **veth pair**: a virtual network cable with two ends. One end becomes `eth0` inside the Pod. The other end stays on the node; with Calico its name starts with `cali`.
2. **It picks an address.** Its **IPAM** part (IP address management) takes a free IP from the pool. The plugin gives the Pod that IP, and adds a route on the node that points to the veth.
3. **It connects the nodes.** It adds routes to the other nodes' Pod blocks. Calico here uses an IP-in-IP tunnel; many other setups use VXLAN. Both wrap the Pod's packet inside a packet between the two nodes.

**A packet from Pod A to Pod B**

*The CNI plugin builds every step: the veth pair into each Pod, and the routes between the nodes.*

`Pod A` — on cka-worker (`10.244.89.67`) → `Node cka-worker` — the veth carries the packet out; a route sends it to the other node → `Node cka-worker2` — a route hands it to Pod B's veth → `Pod B` — sees Pod A's real IP (`10.244.157.130`)

When the Pod is deleted, the plugin frees its IP again. [CNI, CSI and CRI](/cka/architecture/extension-interfaces) shows where the plugin's files live on the node, and why a node without them stays `NotReady`.

**See it on a node**

```bash
docker exec -it cka-worker bash          # exam: ssh <node>
ip -br link | grep cali                  # host ends of the veth pairs, one per local Pod
ip route                                 # one /32 per local Pod, one route per remote node's block
#   10.244.89.67 dev caliad73dda8ffa scope link        (a local Pod)
#   10.244.157.128/26 via 172.19.0.3 dev tunl0 onlink  (another node's block, IP-in-IP)
```

<details>
<summary>Line-by-line explanation</summary>

- `docker exec -it cka-worker bash` — Opens a shell on the worker node. `-it` gives you an interactive terminal, so the next commands run on the node itself. Type `exit` to come back.
- `ip -br link | grep cali` — `ip -br link` lists the node's network interfaces, one per line (`-br` means brief). The `cali…` ones are the host ends of the local Pods' veth pairs.
- `ip route` — The node's routing table. Each local Pod gets a /32 route (exactly one address) to its `cali` interface; another node's Pod block goes through `tunl0`, Calico's IP-in-IP tunnel, as the two sample lines show.

</details>

## Find a Pod, then reach it

Most networking tasks start with three facts about a Pod: its name, its IP and its node. These commands print them.

```bash
kubectl get pods -o wide                                     # IP and NODE columns
kubectl get pod web-0 -o jsonpath='{.status.podIP}{"\n"}'
kubectl get pod web-0 -o jsonpath='{.spec.nodeName}{"\n"}'
kubectl get pods -l tier=cache -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName

# A Pod IP is not stable. Delete the Pod and its replacement gets a new one,
# which is the whole reason Services exist.
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get pods -o wide` — The quickest look: the IP and NODE columns give each Pod's address and where it runs.
- `{.status.podIP}` — Just the Pod's IP. `{"\n"}` adds a line break so your prompt does not end up on the same line.
- `{.spec.nodeName}` — Just the node the Pod was scheduled to.
- `-l tier=cache -o custom-columns` — A label filter plus your own columns: the name, IP and node of every Pod labeled `tier=cache`. Those three facts start most networking tasks.

</details>

To test a connection, start a small client Pod and call the other Pod's IP from inside it. `busybox:1.36` makes a good client: it is tiny, and it has `wget` and `nslookup`.

**Test connectivity from a client Pod**

```bash
# Interactive: the one-liner you will type on the exam.
# --rm deletes the Pod afterwards; -T 3 stops wget waiting forever on a blocked port.
kubectl run tmp --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- -T 3 http://10.244.89.67:8080/hostname

# Non-interactive (scripts, repeated checks): a long-lived client, then exec
kubectl run client --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/client --timeout=60s
kubectl exec client -- wget -qO- -T 3 http://10.244.89.67:8080/hostname
kubectl delete pod client --now
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl run tmp --image=busybox:1.36 --rm -it` — Starts a throwaway busybox Pod, runs `wget` in it and shows the result. `-it` attaches your terminal, `--restart=Never` makes a plain Pod, and `-qO-` means quiet, with the page printed to the screen.
- `-- sleep 3600` — A client that only sleeps for an hour, so it stays up while you run commands in it.
- `wait --for=condition=Ready pod/client` — Waits until the Pod is Ready. An `exec` into a Pod that is still starting fails.
- `kubectl exec client -- wget` — Runs `wget` inside the client Pod. Everything after `--` is the command to run in the container.
- `delete pod client --now` — `--now` deletes with a 1-second grace period instead of the usual 30: quick, but gentler than `--force --grace-period=0`.

</details>

> [!IMPORTANT] **What the grader reads**
> For a "write X to a file" task, the grader compares your file with the live cluster. So write only the value, such as `10.244.0.0/16`: no sentence and no flag name. Read it from the control plane in front of you, never from memory, because exam clusters use different ranges. For the Pod CIDR, use `--cluster-cidr`, not a node's `spec.podCIDR`.

## 📝 Key Takeaways

- Every Pod has its own IP, and any Pod can reach any other Pod at that IP, with no address rewriting.
- The CNI plugin (Calico here) gives Pods their IPs and routes. kube-proxy makes Service addresses work.
- There are two ranges: the Pod CIDR (`--cluster-cidr` on the controller manager) and the Service CIDR (`--service-cluster-ip-range` on the API server).
- A node's podCIDR is only one slice, and Calico ignores it. Never give it as the cluster's Pod CIDR.
- To test a connection, run a busybox client Pod and `wget -qO- -T 3` the other Pod's IP.

**📖 Official documentation:**

- [Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/) *(search: "cluster networking")*
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) *(search: "network plugins cni")*
- [Virtual IPs and Service Proxies](https://kubernetes.io/docs/reference/networking/virtual-ips/) *(search: "kube-proxy mode")*
- [Services, Load Balancing, and Networking](https://kubernetes.io/docs/concepts/services-networking/) *(search: "kubernetes network model")*

---

### 🎯 Task: Record the Pod and Service address ranges

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Find the address range this cluster allocates Pod IPs from, as configured on the control plane, and write it to `/tmp/cka/pod-cidr.txt`. Find the range Service ClusterIPs are allocated from and write it to `/tmp/cka/service-cidr.txt`. Each file must contain only the CIDR.

<details>
<summary>💡 Hints</summary>

- The Pod range is a flag of kube-controller-manager. The Service range is a flag of kube-apiserver.
- Both are in the static Pod files under /etc/kubernetes/manifests on the control plane node.

</details>

<details>
<summary>✅ Solution</summary>

```bash
pod_cidr=$(docker exec cka-control-plane grep -h -- '--cluster-cidr=' /etc/kubernetes/manifests/kube-controller-manager.yaml | sed 's/.*--cluster-cidr=//' | tr -d '[:space:]')
svc_cidr=$(docker exec cka-control-plane grep -h -- '--service-cluster-ip-range=' /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/.*--service-cluster-ip-range=//' | tr -d '[:space:]')
echo "$pod_cidr" > /tmp/cka/pod-cidr.txt
echo "$svc_cidr" > /tmp/cka/service-cidr.txt
cat /tmp/cka/pod-cidr.txt /tmp/cka/service-cidr.txt
```

**Explanation:**

- `pod_cidr=$(` — Reads the `--cluster-cidr` line and keeps only the value: `sed` deletes everything up to `--cluster-cidr=`, and `tr -d '[:space:]'` strips spaces and line breaks. `$( … )` stores the output in the variable `pod_cidr`.
- `svc_cidr=$(` — The same three steps for `--service-cluster-ip-range` in the API server manifest.
- `echo "$pod_cidr"` — Writes each value to its own file, and nothing else. `>` replaces whatever the file held before.
- `cat /tmp/cka/pod-cidr.txt` — Prints both files so you can see exactly one CIDR in each.

**Notes:** On the exam, `ssh` to the control plane node. Then run `grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml` and `grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml`. No node shell? `kubectl -n kube-system get pod -l component=kube-controller-manager -o yaml | grep cluster-cidr` shows the same flag. Do not use a node's `spec.podCIDR`. It is one node's slice, and with Calico it does not even match the Pod IPs.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
flag() { kubectl -n kube-system get pod -l component=$1 -o jsonpath='{range .items[0].spec.containers[0].command[*]}{@}{"\n"}{end}' 2>/dev/null | grep -- "^--$2=" | head -1 | cut -d= -f2; }
live_pod=$(flag kube-controller-manager cluster-cidr)
live_svc=$(flag kube-apiserver service-cluster-ip-range)

[ -n "$live_pod" ] && [ -n "$live_svc" ] && p "read live flags ($live_pod, $live_svc)" || f "read live flags from the control plane"
[ -f /tmp/cka/pod-cidr.txt ] && p "/tmp/cka/pod-cidr.txt exists" || f "/tmp/cka/pod-cidr.txt exists"
[ -f /tmp/cka/service-cidr.txt ] && p "/tmp/cka/service-cidr.txt exists" || f "/tmp/cka/service-cidr.txt exists"
[ -n "$live_pod" ] && [ "$(tr -d '[:space:]' < /tmp/cka/pod-cidr.txt 2>/dev/null)" = "$live_pod" ] && p "pod CIDR matches --cluster-cidr" || f "pod CIDR matches --cluster-cidr"
[ -n "$live_svc" ] && [ "$(tr -d '[:space:]' < /tmp/cka/service-cidr.txt 2>/dev/null)" = "$live_svc" ] && p "service CIDR matches --service-cluster-ip-range" || f "service CIDR matches --service-cluster-ip-range"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Locate a Pod and reach it by IP

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Several Pods run in namespace `nw-cni`. For the Pod labeled `tier=cache`: write its Pod IP to `/tmp/cka/cache-ip.txt` and the name of the node it runs on to `/tmp/cka/cache-node.txt`. Then, from a temporary Pod using image `busybox:1.36` in the same namespace, request `http://:8080/hostname` and save the response body to `/tmp/cka/cache-hostname.txt`. Remove the temporary Pod afterwards.

<details>
<summary>💡 Hints</summary>

- kubectl get pods -l tier=cache -o wide shows the IP and the node on one line.
- In busybox, wget -qO- -T 3 http://IP:8080/hostname prints the page to the screen.

</details>

<details>
<summary>✅ Solution</summary>

```bash
ns=nw-cni
pod=$(kubectl -n $ns get pod -l tier=cache -o jsonpath='{.items[0].metadata.name}')
ip=$(kubectl -n $ns get pod "$pod" -o jsonpath='{.status.podIP}')
echo "$ip" > /tmp/cka/cache-ip.txt
kubectl -n $ns get pod "$pod" -o jsonpath='{.spec.nodeName}' > /tmp/cka/cache-node.txt
kubectl -n $ns run tmp --image=busybox:1.36 --restart=Never -- sleep 300
kubectl -n $ns wait --for=condition=Ready pod/tmp --timeout=90s
kubectl -n $ns exec tmp -- wget -qO- -T 5 "http://$ip:8080/hostname" > /tmp/cka/cache-hostname.txt
kubectl -n $ns delete pod tmp --now
cat /tmp/cka/cache-ip.txt /tmp/cka/cache-node.txt; echo; cat /tmp/cka/cache-hostname.txt; echo
```

**Explanation:**

- `ns=nw-cni` — Keeps the namespace in a variable, so each command below can say `-n $ns`.
- `pod=$(` — Finds the Pod by its label instead of guessing its name. `.items[0]` is the first match, here the only one.
- `ip=$(` — Reads that Pod's IP into the variable `ip`.
- `cache-ip.txt` — Saves the IP to the first answer file.
- `cache-node.txt` — Writes the node name straight into the second file.
- `run tmp --image=busybox:1.36` — The temporary client: busybox in the same namespace, sleeping for five minutes so you can exec into it.
- `wait --for=condition=Ready pod/tmp` — Waits until the client is Ready.
- `exec tmp -- wget` — Calls the cache Pod directly at its IP, across the Pod network with no Service in between, and saves the reply to the third file. `-T 5` gives up after 5 seconds instead of hanging.
- `delete pod tmp --now` — Removes the temporary Pod, as the task asks.
- `cat /tmp/cka/cache-ip.txt` — Shows all three files. The extra `echo`s only add line breaks, because two of the files do not end with one.

**Notes:** By hand: run `kubectl get pods -n nw-cni -l tier=cache -o wide`, and copy the IP and node into the files with `echo`. Then run `kubectl run tmp -n nw-cni --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- -T 3 http://:8080/hostname > /tmp/cka/cache-hostname.txt`. With `-it`, kubectl can mix its own messages into the file, so check it with `cat`. The reply is the Pod's name: the request went straight to the Pod IP.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-cni
pod=$(kubectl -n $ns get pod -l tier=cache -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ip=$(kubectl -n $ns get pod "$pod" -o jsonpath='{.status.podIP}' 2>/dev/null)
node=$(kubectl -n $ns get pod "$pod" -o jsonpath='{.spec.nodeName}' 2>/dev/null)

[ -n "$ip" ] && p "tier=cache pod $pod is running at $ip" || f "tier=cache pod exists"
[ -n "$ip" ] && [ "$(tr -d '[:space:]' < /tmp/cka/cache-ip.txt 2>/dev/null)" = "$ip" ] && p "cache-ip.txt matches the pod IP" || f "cache-ip.txt matches the pod IP"
[ -n "$node" ] && [ "$(tr -d '[:space:]' < /tmp/cka/cache-node.txt 2>/dev/null)" = "$node" ] && p "cache-node.txt matches the node" || f "cache-node.txt matches the node"
[ -n "$pod" ] && [ "$(tr -d '[:space:]' < /tmp/cka/cache-hostname.txt 2>/dev/null)" = "$pod" ] && p "cache-hostname.txt holds the /hostname response" || f "cache-hostname.txt holds the /hostname response"
[ "$(kubectl -n $ns get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "3" ] && p "temporary pod removed" || f "temporary pod removed"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
