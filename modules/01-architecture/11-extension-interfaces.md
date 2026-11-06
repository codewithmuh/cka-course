# CNI, CSI and CRI

> **Module 1** · Lesson 1.11 · 35 minutes

The three plug-in points for running containers, Pod networking and storage, and where to find each one on a node.

## Learning Objectives

- You can say what CRI, CNI and CSI each plug in, and which part of Kubernetes calls each one.
- You can find a node's container runtime endpoint and the CNI configuration it loads.
- You can use crictl on a node to list Pod sandboxes and containers and print their full IDs.
- You can tell from a symptom which interface to check first.


Kubernetes does not run containers, build Pod networks or attach disks by itself. It hands each job to a plug-in, through a standard interface. Think of a power socket: any device with the right plug works. That is why you can swap containerd for CRI-O, or Calico for another network plug-in, without changing Kubernetes.

- **CRI** (Container Runtime Interface): the kubelet asks a container runtime, such as containerd, to start and stop containers.
- **CNI** (Container Network Interface): the container runtime asks a network plug-in, such as Calico, to give each new Pod an IP address.
- **CSI** (Container Storage Interface): Kubernetes asks a storage driver to create volumes and mount them for Pods.

**Who asks whom**

*Each interface joins a part of Kubernetes to a plug-in. On this lab the plug-ins are containerd and Calico; the lab has no CSI driver.*

`CRI` — runs containers
  - `kubelet` — asks
  - `containerd` — starts the containers   `CNI` — connects Pods to the network
  - `containerd` — asks, for each new Pod
  - `Calico` — gives the Pod an IP   `CSI` — attaches storage
  - `kubelet and helpers` — ask
  - `Storage driver` — creates and mounts volumes

Exam tasks here are short. You find a value on a node and write it to a file. You use `crictl` where `kubectl` cannot reach. Or you say which interface a broken node or Pod points at.

| Interface | On this lab | Where to look |
| --- | --- | --- |
| CRI | containerd | The socket `/run/containerd/containerd.sock` and the config `/etc/containerd/config.toml` on each node. `kubectl get nodes -o wide` shows the runtime and its version. |
| CNI | Calico | Config files in `/etc/cni/net.d` and plug-in programs in `/opt/cni/bin` on each node, plus the `calico-node` DaemonSet |
| CSI | None: the `standard` StorageClass uses a provisioner that is not CSI | `kubectl get csidrivers`, `kubectl get csinode`, and the `provisioner` of each StorageClass |

## CRI: how the kubelet reaches the runtime

The kubelet never starts containers itself. It asks the container runtime, through the CRI, over a socket file on the node. To find that socket, read `containerRuntimeEndpoint` in the kubelet's config file, `/var/lib/kubelet/config.yaml`.

- On this lab and most clusters the runtime is containerd, and the endpoint is `unix:///run/containerd/containerd.sock`.
- Older kubeadm clusters may set it as a flag instead: `--container-runtime-endpoint` in `/var/lib/kubelet/kubeadm-flags.env`.
- How containerd itself is set up, such as its cgroup driver, is part of [Installing a cluster with kubeadm](/cka/architecture/kubeadm-install).

## crictl: look below the API

`crictl` talks to the same socket as the kubelet. It shows what the runtime sees on one node, and it still works when the API server or the kubelet is down. Do not mix it up with kubectl:

| Tool | Talks to | Runs on | Shows |
| --- | --- | --- | --- |
| **kubectl** | The API server | Your workstation | Kubernetes objects in the whole cluster |
| **crictl** | The container runtime | One node, in a node shell | The Pod sandboxes and containers on that node only |

A **Pod sandbox** is the runtime's home for one Pod. It holds the Pod's network, and the Pod's containers run inside it. `crictl pods` lists sandboxes, and `crictl ps` lists containers.

**Runtime facts and crictl, from a node shell**

```bash
docker exec -it cka-worker bash                 # exam: ssh <node>, then sudo -i

grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
cat /var/lib/kubelet/kubeadm-flags.env           # extra kubelet flags kubeadm wrote

crictl pods --namespace kube-system              # pod sandboxes (POD ID)
crictl ps -a --name coredns                      # containers, including exited ones (CONTAINER)
crictl ps --name web --no-trunc -q               # full 64-character IDs only
```

<details>
<summary>Line-by-line explanation</summary>

- `docker exec -it cka-worker bash` — kind nodes are Docker containers, so this opens a root shell on the node. `-it` gives you an interactive terminal; type `exit` to leave.
- `grep containerRuntimeEndpoint` — Finds the socket the kubelet uses to reach the runtime, such as `unix:///run/containerd/containerd.sock`.
- `kubeadm-flags.env` — Flags kubeadm passes to the kubelet on top of its config file. Older clusters set the runtime endpoint here.
- `crictl pods --namespace kube-system` — Lists Pod sandboxes as the runtime sees them, here only kube-system ones. Works even when the API server is down.
- `crictl ps -a --name coredns` — Lists containers whose name matches `coredns`. `-a` includes exited ones, which is where a crash-looping container's earlier runs show up.
- `crictl ps --name web --no-trunc -q` — `-q` prints only IDs and `--no-trunc` prints them in full, ready to paste into a file.

</details>

Reading logs and debugging with crictl is taught in [kubectl debug, ephemeral containers and crictl](/cka/troubleshooting/debug-containers-and-nodes).

## CNI: which network config a node uses

Each time a Pod starts, the container runtime calls the CNI plug-in to set up the Pod's network. [Pod networking and CNI](/cka/networking/pod-networking-and-cni) walks through the whole flow. For this lesson's task, three facts are enough:

- The runtime reads the config files in `/etc/cni/net.d` and uses only the **first one in lexical order**. Lexical means sorted character by character, like a dictionary. Only `.conflist`, `.conf` and `.json` files count.
- Each plug-in in that file has a `type`. The type is the name of a program in `/opt/cni/bin`.
- A leftover file such as `05-old.conf` sorts before `10-calico.conflist`, so it wins. New Pods then get the wrong network.

**The CNI pieces on this lab**

```bash
docker exec cka-worker ls -l /etc/cni/net.d       # 10-calico.conflist and calico-kubeconfig
docker exec cka-worker cat /etc/cni/net.d/10-calico.conflist   # plugins: "calico" (ipam "calico-ipam"), then "portmap"
docker exec cka-worker ls /opt/cni/bin            # calico, calico-ipam, host-local, loopback, portmap, ...
```

<details>
<summary>Line-by-line explanation</summary>

- `ls -l /etc/cni/net.d` — Runs one command on the node without opening a shell. This folder holds the network config, and the runtime uses the first config file in name order.
- `cat /etc/cni/net.d/10-calico.conflist` — A `.conflist` is JSON holding a chain of plugins that run in order for each new Pod. Each `type` names a program in `/opt/cni/bin`.
- `ls /opt/cni/bin` — The plugin programs themselves. A `type` with no matching file here means new Pods cannot get a network.

</details>

## CSI: storage drivers

A CSI driver lets Kubernetes use a storage system, such as cloud disks, without that system's code being part of Kubernetes. A driver usually has two parts:

- A **node plugin**: a DaemonSet with one Pod per node. It registers with the kubelet and mounts volumes into Pods.
- A **controller**: a Deployment whose helper containers create, attach and resize volumes when claims ask for them.

A StorageClass names its driver in `provisioner`, for example `ebs.csi.aws.com`. [StorageClasses and dynamic provisioning](/cka/storage/storage-classes-dynamic-provisioning) covers how claims use it.

**CSI objects, read from the API**

```bash
kubectl get csidrivers
kubectl get csinode
kubectl get csinode cka-worker -o jsonpath='{.spec.drivers[*].name}'
kubectl get volumeattachments
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get csidrivers` — Lists installed CSI drivers and what they support. On this lab it returns nothing, because the `standard` class is not CSI.
- `kubectl get csinode` — One CSINode per node, with the number of CSI drivers registered there. Zero everywhere on this lab.
- `{.spec.drivers[*].name}` — The names of the drivers registered on `cka-worker`. Empty output means none.
- `volumeattachments` — Records of volumes a CSI driver has attached to nodes. Empty when no attachable CSI volumes are in use.

</details>

## From a symptom to an interface

When something breaks, the symptom tells you which interface to look at. The troubleshooting module shows the fixes, starting with [Worker node failures](/cka/troubleshooting/worker-node-failures).

| Symptom | Interface | Look first at |
| --- | --- | --- |
| Node `NotReady`, with the message `cni plugin not initialized` | CNI | `/etc/cni/net.d` on that node, and the network plug-in's Pod there |
| Pod stuck in `ContainerCreating`, event `failed to setup network for sandbox` | CNI | The network plug-in's Pod on that node and its logs |
| Node `NotReady`, and the kubelet log says the runtime socket is missing or refused | CRI | `systemctl status containerd`, then the endpoint in the kubelet config |
| PVC `Pending`, `waiting for a volume to be created` | CSI or another provisioner | The provisioner's Pods and logs, and the StorageClass's `provisioner` |
| Pod in `ContainerCreating` with `FailedMount` or `FailedAttachVolume` | CSI | `kubectl get csinode`, `kubectl get volumeattachments`, and the driver's Pod on that node |

> [!IMPORTANT] **What the grader reads**
> Most questions here end in "write it to a file", and the grader compares the file with the live value. Copy values from the node instead of typing them: one value per file, with no labels. Use `--no-trunc` for IDs, because `crictl ps` cuts them to 13 characters. On the exam, answer files usually belong on the machine you ssh from, so `exit` the node first.

## 📝 Key Takeaways

- CRI: the kubelet talks to the container runtime (containerd). CNI: the runtime asks the network plug-in (Calico) to wire up each Pod. CSI: storage drivers plug in.
- The runtime endpoint is `containerRuntimeEndpoint` in `/var/lib/kubelet/config.yaml`.
- The runtime uses the first CNI config in `/etc/cni/net.d`, in lexical order. Each plug-in's `type` is a program in `/opt/cni/bin`.
- `crictl pods` lists sandboxes and `crictl ps` lists containers. Add `--no-trunc -q` to print only full IDs.

**📖 Official documentation:**

- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) *(search: "network plugins")*
- [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) *(search: "container runtimes")*
- [Debugging Kubernetes nodes with crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) *(search: "crictl")*
- [Volumes: CSI](https://kubernetes.io/docs/concepts/storage/volumes/#csi) *(search: "csi volume")*

---

### 🎯 Task: Record a node's CNI and runtime configuration

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Inspect node `cka-worker` (lab: `docker exec -it cka-worker bash`; exam: `ssh cka-worker`) and write these answers to files on your workstation under `/tmp/cka/ext/`: in `cni-config.txt`, the file name (without its directory) of the CNI network configuration the container runtime loads on that node; in `cni-plugin.txt`, the `type` of the first plugin in that configuration; in `runtime-endpoint.txt`, the container runtime endpoint the kubelet on that node is configured to use.

<details>
<summary>💡 Hints</summary>

- The runtime loads the first config file in lexical order from `/etc/cni/net.d`. Only `.conf`, `.conflist` and `.json` files are network configs.
- The endpoint is `containerRuntimeEndpoint` in the kubelet's config file, `/var/lib/kubelet/config.yaml`. Older clusters set it as a flag in `/var/lib/kubelet/kubeadm-flags.env`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
docker exec cka-worker ls -l /etc/cni/net.d
docker exec cka-worker ls -1 /etc/cni/net.d | grep -E '\.(conflist|conf|json)$' | LC_ALL=C sort | sed -n 1p > /tmp/cka/ext/cni-config.txt
docker exec cka-worker cat "/etc/cni/net.d/$(cat /tmp/cka/ext/cni-config.txt)" | awk -F'"' '/"type"/ && !done {print $4; done=1}' > /tmp/cka/ext/cni-plugin.txt
docker exec cka-worker cat /var/lib/kubelet/config.yaml | awk '/^containerRuntimeEndpoint:/ {print $2}' > /tmp/cka/ext/runtime-endpoint.txt
head /tmp/cka/ext/*.txt
```

**Explanation:**

- `ls -l /etc/cni/net.d` — Look first: the folder holds `10-calico.conflist` and `calico-kubeconfig`, and only the first is a network config.
- `ls -1` — `ls -1` prints one name per line, grep keeps `.conflist`, `.conf` and `.json` files, `LC_ALL=C sort` sorts byte by byte like the runtime, and `sed -n 1p` keeps the first.
- `cni-plugin.txt` — Prints that config, with `$(cat …)` filling in its name. `awk -F'"'` splits lines at double quotes, so on the first line with `"type"` the value is field 4; `done=1` stops after one.
- `runtime-endpoint.txt` — Prints the kubelet config and keeps the second field of the `containerRuntimeEndpoint:` line, the value itself. `^` anchors the match to the start of the line.
- `head /tmp/cka/ext/` — Shows all three files, each under its own name, so you can check them in one go.

**Notes:** On the exam: `ssh cka-worker`, then `ls /etc/cni/net.d`, then `cat` the conflist, then `grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml`. Then `exit` and `echo` each value into its file. `calico-kubeconfig` sits in the same folder, but it is a credentials file for the plug-in, not a network config. `ps aux | grep kubelet` shows only the kubelet's flags; current kubeadm clusters set the endpoint in the config file instead.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
n=cka-worker
d=/tmp/cka/ext
val() { tr -d ' \r\n' < "$1" 2>/dev/null; }

cfg=$(docker exec $n ls -1 /etc/cni/net.d 2>/dev/null | grep -E '\.(conflist|conf|json)$' | LC_ALL=C sort | sed -n 1p)
typ=$(docker exec $n cat "/etc/cni/net.d/$cfg" 2>/dev/null | awk -F'"' '/"type"/ && !done {print $4; done=1}')
ep=$(docker exec $n cat /var/lib/kubelet/config.yaml 2>/dev/null | awk '/^containerRuntimeEndpoint:/ {print $2}')
[ -z "$ep" ] && ep=$(docker exec $n cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null | grep -o -- '--container-runtime-endpoint=[^ "]*' | cut -d= -f2)

[ -n "$cfg" ] && [ "$(val $d/cni-config.txt)" = "$cfg" ] && p "cni-config.txt is $cfg" || f "cni-config.txt names the CNI config file"
[ -n "$typ" ] && [ "$(val $d/cni-plugin.txt)" = "$typ" ] && p "cni-plugin.txt is $typ" || f "cni-plugin.txt names the first plugin type"
got=$(val $d/runtime-endpoint.txt)
[ -n "$ep" ] && { [ "$got" = "$ep" ] || [ "unix://$got" = "$ep" ]; } && p "runtime-endpoint.txt is $ep" || f "runtime-endpoint.txt holds the kubelet's runtime endpoint"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Find a container below the API with crictl

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Pod `storefront` in namespace `arx-ext` runs two containers. On the node where it runs, use `crictl` to find the ID of the Pod's sandbox and write it to `/tmp/cka/ext/storefront-sandbox.txt`, then find the ID of its `log-agent` container and write it to `/tmp/cka/ext/log-agent-id.txt`. Write the full, untruncated IDs.

<details>
<summary>💡 Hints</summary>

- `kubectl get pod -o wide` tells you the node. On that node, `crictl pods` lists sandboxes and `crictl ps` lists containers.
- `crictl ps --pod POD_ID --name log-agent` narrows the list to one container. Add `--no-trunc -q` to print only the full ID.

</details>

<details>
<summary>✅ Solution</summary>

```bash
node=$(kubectl -n arx-ext get pod storefront -o jsonpath='{.spec.nodeName}')
docker exec "$node" crictl pods --name storefront --namespace arx-ext
pod=$(docker exec "$node" crictl pods --name '^storefront$' --namespace '^arx-ext$' --state ready -q --no-trunc)
echo "$pod" > /tmp/cka/ext/storefront-sandbox.txt
docker exec "$node" crictl ps --pod "$pod" --name '^log-agent$' -q --no-trunc > /tmp/cka/ext/log-agent-id.txt
cat /tmp/cka/ext/storefront-sandbox.txt /tmp/cka/ext/log-agent-id.txt
```

**Explanation:**

- `node=$(` — Saves the name of the node the Pod runs on in `$node`. `$(…)` runs the command and captures its output.
- `crictl pods --name storefront` — Shows the sandbox on that node in the normal table, so you can see what you are about to capture.
- `pod=$(` — The same query made exact: `^` and `$` anchor the names (crictl treats them as patterns), `--state ready` skips old sandboxes, and `-q --no-trunc` prints only the full ID.
- `echo "$pod"` — Writes the sandbox ID to its file.
- `crictl ps --pod` — Lists only that sandbox's container named exactly `log-agent` and writes its full ID straight to the file.
- `cat /tmp/cka/ext/` — Prints both IDs. Each should be 64 hexadecimal characters.

**Notes:** Exam route: find the node with `kubectl get pod storefront -n arx-ext -o wide`, then `ssh` there. Run `sudo crictl pods --name storefront`, then `sudo crictl ps --pod  --no-trunc`. Copy the IDs, `exit`, and write the files. The grader checks the container ID against the API, where it has a `containerd://` prefix: `kubectl get pod storefront -n arx-ext -o jsonpath='{.status.containerStatuses[*].containerID}'`. The sandbox ID is only visible from the runtime.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-ext
val() { tr -d ' \r\n' < "$1" 2>/dev/null; }

node=$(kubectl -n $ns get pod storefront -o jsonpath='{.spec.nodeName}' 2>/dev/null)
cid=$(kubectl -n $ns get pod storefront -o jsonpath='{.status.containerStatuses[?(@.name=="log-agent")].containerID}' 2>/dev/null | sed 's#^containerd://##')
sid=""
[ -n "$node" ] && sid=$(docker exec "$node" crictl pods --name '^storefront$' --namespace '^arx-ext$' --state ready -q --no-trunc 2>/dev/null | sed -n 1p)

[ -n "$node" ] && p "pod storefront runs on $node" || f "pod storefront exists"
echo "$sid" | grep -Eq '^[0-9a-f]{64}$' && [ "$(val /tmp/cka/ext/storefront-sandbox.txt)" = "$sid" ] && p "sandbox ID matches crictl pods" || f "storefront-sandbox.txt holds the full sandbox ID"
got=$(val /tmp/cka/ext/log-agent-id.txt | sed 's#^containerd://##')
echo "$cid" | grep -Eq '^[0-9a-f]{64}$' && [ "$got" = "$cid" ] && p "log-agent container ID matches" || f "log-agent-id.txt holds the full log-agent container ID"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
