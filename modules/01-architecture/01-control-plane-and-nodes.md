# Control plane and node components

> **Module 1** · Lesson 1.1 · 35 minutes

What each part of a Kubernetes cluster does, in plain words, how it is started, and where to read its settings.

## Learning Objectives

- You can say in one sentence what each part of a cluster does, and tell kubeadm, kubectl and kubelet apart.
- You can read a part's live settings from its static Pod file, its mirror Pod or the kubelet's config file.
- You can create and remove a static Pod on any node.


A Kubernetes cluster is a group of machines that work together to run your apps. A few parts make the decisions; together they are called the **control plane**. The other machines, the **worker nodes**, do the actual work of running your apps. This lesson shows what each part does, how it is started, and where to read its settings. That last part matters most: the exam never asks you to draw the diagram below, it asks you to find things, such as which setting the API server runs with.

**The parts of a cluster**

*kubectl talks only to the API server. The kubelet on each worker node also talks to the API server, to learn which Pods it should run.*

`Control plane` — makes the decisions
  - `API server` — the front door
  - `etcd` — the database
  - `Scheduler` — picks a node
  - `Controller manager` — keeps things as asked ⟷ `Worker node` — runs your apps
  - `kubelet` — starts the Pods
  - `Container runtime` — runs the containers
  - `kube-proxy` — routes Service traffic
  - `Your Pods` — your apps

## kubeadm, kubectl and kubelet: three names, three jobs

These three names look alike and confuse almost everyone at first, but they are completely different things:

| Name | What it is | When you use it | Example |
| --- | --- | --- | --- |
| **kubeadm** | A setup tool | Once per machine, to build or upgrade the cluster | `kubeadm init`, `kubeadm join` |
| **kubectl** | A command-line tool | All day, from your terminal, to work with the cluster | `kubectl get pods` |
| **kubelet** | An agent: a program running in the background | Never directly. It runs on every node all the time and starts the Pods | `systemctl status kubelet` |

> [!TIP] **A way to remember them**
> **adm** is admin: it builds the cluster. **ctl** is control: you control the cluster with it. **let** means small, like a booklet is a small book: the kubelet is the small helper that lives on every node.

## What each part does

Here is every part with its job in plain words. kind, the tool behind this course's lab, builds its clusters with kubeadm, so these are the same parts and the same file paths you will meet on exam day.

| Part | Its job, in plain words | Where it runs |
| --- | --- | --- |
| kube-apiserver | The front door. Every request goes through it. It checks who is asking and whether they are allowed, then saves the change in etcd. | Control plane, as a static Pod |
| etcd | The database. It stores every object in the cluster: every Pod, Deployment and Secret. | Control plane, as a static Pod |
| kube-scheduler | Picks a node for each new Pod. | Control plane, as a static Pod |
| kube-controller-manager | Keeps things the way you asked. You ask for 3 copies of an app and one dies, so it starts a new one. | Control plane, as a static Pod |
| kubelet | Starts the Pods assigned to its node, restarts them if they crash, and reports their status. | Every node, as a normal Linux service |
| Container runtime (containerd) | Actually runs the containers. The kubelet tells it what to start. | Every node, as a normal Linux service |
| kube-proxy | Makes Service addresses work by passing their traffic to the right Pods. | Every node, as a Pod (one per node) |

What breaks when each part stops is a topic of its own. You will meet it in [Control plane failures](/cka/troubleshooting/control-plane-failures) and [Worker node failures](/cka/troubleshooting/worker-node-failures).

## Three ways the parts are started

Each part is started in one of three ways. Knowing which group a part is in tells you which tool to use when it breaks.

- **As a normal Linux service:** the kubelet and the container runtime. They start when the machine boots, and you check them with `systemctl status kubelet`.
- **As static Pods:** the API server, etcd, the scheduler and the controller manager. The kubelet starts them from files on the control plane node, as the next section shows.
- **As ordinary Pods:** kube-proxy and the network plugin (Calico in this lab), in the `kube-system` namespace. You check them with `kubectl -n kube-system get pods`.

## Static Pods

Normally you create a Pod through the API server: kubectl sends it, the API server saves it, the scheduler picks a node, and that node's kubelet starts it. But the API server is itself a Pod. Who starts it, when there is no API server yet? The kubelet does, from a file.

A **static Pod** is a Pod defined by a YAML file in a folder on the node: `/etc/kubernetes/manifests` on kubeadm clusters. The kubelet runs every file in that folder and restarts the Pod if it stops. No API server and no scheduler are involved.

**How a static Pod starts**

`A YAML file` (`/etc/kubernetes/manifests`) → `kubelet` — runs every file in that folder → `Pod running` — on this node → `Mirror Pod` — a read-only copy you see in kubectl

So that you can still see these Pods with kubectl, the kubelet also puts a read-only copy in the API, called a **mirror Pod**. Its name is the Pod's name plus the node's name, for example `kube-apiserver-cka-control-plane`. Deleting the mirror Pod changes nothing. To change or stop a static Pod, edit or delete its file.

**Find the static Pod path and recognize a mirror Pod**

```bash
# exam: ssh <node>    lab: docker exec -it cka-control-plane bash
grep staticPodPath /var/lib/kubelet/config.yaml
ls /etc/kubernetes/manifests
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

# From your workstation: a mirror Pod is owned by a Node and sourced from a file
kubectl -n kube-system get pod kube-apiserver-cka-control-plane \
  -o jsonpath='{.metadata.ownerReferences[0].kind}{" "}{.metadata.annotations.kubernetes\.io/config\.source}{"\n"}'
# Node file
```

<details>
<summary>Line-by-line explanation</summary>

- `lab: docker exec -it cka-control-plane bash` — Get a shell on the node first. On the exam that is `ssh `, then `sudo -i` for root; on the lab each node is a Docker container, so `docker exec -it` opens an interactive bash inside it.
- `grep staticPodPath` — Searches the kubelet's config file for the folder it loads static Pods from. On kubeadm clusters it prints `staticPodPath: /etc/kubernetes/manifests`.
- `ls /etc/kubernetes/manifests` — Lists that folder. Each file is one control plane component the kubelet keeps running; the comment below shows the four a kubeadm control plane has.
- `get pod kube-apiserver-cka-control-plane` — Reads the API server's mirror Pod. Mirror Pods are named `-`, hence `kube-apiserver-cka-control-plane`. The `\` at the end continues the command on the next line.
- `ownerReferences[0].kind` — Prints the kind of the Pod's owner and its `kubernetes.io/config.source` annotation. The dots inside the annotation name are escaped with `\` so jsonpath does not treat them as path separators.
- `# Node file` — The expected output: owned by a **Node**, sourced from a **file**. That pair is how you recognize a static Pod through the API.

</details>

> [!WARNING] **Never keep a backup inside the manifests folder**
> The kubelet runs *every* file in that folder, whatever its name. A `kube-apiserver.yaml.bak` next to the real file becomes a second API server, and the two fight over the same port. Before you edit a control plane file, copy it somewhere else first: `cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/`.

## Reading a part's settings

Exam questions often ask for a setting, such as the range of IP addresses that Services get. There are three places to read it; use whichever is quickest.

**Three places to read a setting**

```bash
# 1. What the kubelet was told to run: the static Pod's file on the node
docker exec cka-control-plane grep -- --service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml

# 2. The same through the API, no node shell needed
kubectl -n kube-system get pod -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep service-cluster

# 3. The kubelet keeps its own settings in a config file on each node
docker exec cka-control-plane grep -E 'staticPodPath|containerRuntimeEndpoint|cgroupDriver' /var/lib/kubelet/config.yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `grep -- --service-cluster-ip-range` — Runs `grep` inside the node to print the flag from the API server manifest. The first `--` tells grep that what follows is the text to find, even though it starts with dashes.
- `get pod -l component=kube-apiserver` — Finds the API server's mirror Pod by its label instead of its name, so the command works whatever the node is called.
- `containers[0].command}'` — Prints the container's command as one JSON list. `tr` turns each comma into a line break, giving one argument per line for `grep`.
- `grep -E 'staticPodPath|containerRuntimeEndpoint|cgroupDriver'` — The kubelet's main config file. `-E` lets `|` mean *or*, so one command prints the static Pod path, the CRI socket and the cgroup driver.

</details>

Always read the value from the cluster in front of you, never from memory. For example, kubeadm's default Service range is `10.96.0.0/12`, but this lab uses `10.96.0.0/16`.

> [!IMPORTANT] **Answer files are compared with the live value**
> When a task says to write a value to a file, the grader reads that file and compares it with the cluster. Write only the value (`10.96.0.0/16`, not `--service-cluster-ip-range=10.96.0.0/16`), to the exact path given, on the machine the question names.

## 📝 Key Takeaways

- The control plane makes the decisions: API server, etcd, scheduler and controller manager. Worker nodes run your apps: kubelet, container runtime and kube-proxy.
- kubeadm builds the cluster, kubectl talks to it, and the kubelet runs the Pods on every node.
- The control plane parts are static Pods: files in `/etc/kubernetes/manifests` that the kubelet starts. To change one, edit its file.
- Read settings from the cluster itself: the static Pod file, the mirror Pod, or the kubelet's `config.yaml`.

**📖 Official documentation:**

- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/) *(search: "kubernetes components")*
- [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) *(search: "static pod")*
- [Set Kubelet Parameters Via A Configuration File](https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/) *(search: "kubelet config file")*
- [kube-apiserver](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/) *(search: "kube-apiserver")*

---

### 🎯 Task: Read control plane settings from the node

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 3% |
| **Time** | 5 min |

**Question:**

Answer three questions about this cluster by reading it. Write each answer as a single bare value. (1) The IP range the API server assigns Service ClusterIPs from, to `/tmp/cka/ar-svc-cidr.txt`. (2) The directory the kubelet on `cka-control-plane` loads static Pod manifests from, to `/tmp/cka/ar-static-path.txt`. (3) The CRI endpoint that same kubelet uses to reach its container runtime, to `/tmp/cka/ar-cri-endpoint.txt`.

<details>
<summary>💡 Hints</summary>

- The Service range is a kube-apiserver flag, and the API server is a static Pod: its manifest is a file on the control plane node.
- Both kubelet answers are in /var/lib/kubelet/config.yaml on the node. Reach it with docker exec cka-control-plane … (ssh on the exam).

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
docker exec cka-control-plane grep -- '--service-cluster-ip-range=' /etc/kubernetes/manifests/kube-apiserver.yaml | cut -d= -f2 | tr -d ' ' > /tmp/cka/ar-svc-cidr.txt
docker exec cka-control-plane awk '/^staticPodPath:/ {print $2}' /var/lib/kubelet/config.yaml > /tmp/cka/ar-static-path.txt
docker exec cka-control-plane awk '/^containerRuntimeEndpoint:/ {print $2}' /var/lib/kubelet/config.yaml > /tmp/cka/ar-cri-endpoint.txt
cat /tmp/cka/ar-svc-cidr.txt /tmp/cka/ar-static-path.txt /tmp/cka/ar-cri-endpoint.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Makes sure the answers folder exists. `-p` means no error if it is already there.
- `--service-cluster-ip-range=` — Only `grep` runs on the node; the pipes run on your workstation. `cut -d= -f2` keeps the part after the `=`, `tr -d ' '` strips spaces, and `>` writes the bare value to the answer file.
- `awk '/^staticPodPath:/` — `awk` finds the line that starts with `staticPodPath:` and prints its second word, which is the path itself.
- `awk '/^containerRuntimeEndpoint:/` — The same trick for the CRI endpoint: the socket the kubelet uses to reach containerd, such as `unix:///run/containerd/containerd.sock`.
- `cat /tmp/cka/ar-svc-cidr.txt` — Prints all three files so you can check that each holds one bare value and nothing else.

**Notes:** On the exam: `ssh` to the control plane, `sudo -i`, then `grep` the manifest and the kubelet config, and write the files with `echo 10.96.0.0/16 > /path`. If `/var/lib/kubelet/config.yaml` does not exist on some node, look at the kubelet's command line (`ps -o args= -C kubelet`) for `--config` or `--pod-manifest-path`. Without a node shell, the API server's flags are also visible through its mirror Pod: `kubectl -n kube-system get pod kube-apiserver- -o yaml`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
val() { tr -d '[:space:]' 2>/dev/null < "$1"; }

want_svc=$(kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null | tr ',' '\n' | grep -o 'service-cluster-ip-range=[^"]*' | cut -d= -f2)
want_path=$(docker exec cka-control-plane awk '/^staticPodPath:/ {print $2}' /var/lib/kubelet/config.yaml 2>/dev/null)
want_cri=$(docker exec cka-control-plane awk '/^containerRuntimeEndpoint:/ {print $2}' /var/lib/kubelet/config.yaml 2>/dev/null)
got_path=$(val /tmp/cka/ar-static-path.txt | sed 's#/$##')
got_cri=$(val /tmp/cka/ar-cri-endpoint.txt)

[ -n "$want_svc" ] && [ "$(val /tmp/cka/ar-svc-cidr.txt)" = "$want_svc" ] && p "Service CIDR is $want_svc" || f "Service CIDR in /tmp/cka/ar-svc-cidr.txt"
[ -n "$want_path" ] && [ "$got_path" = "$want_path" ] && p "static Pod path is $want_path" || f "static Pod path in /tmp/cka/ar-static-path.txt"
[ -n "$want_cri" ] && { [ "$got_cri" = "$want_cri" ] || [ "unix://$got_cri" = "$want_cri" ]; } && p "CRI endpoint is $want_cri" || f "CRI endpoint in /tmp/cka/ar-cri-endpoint.txt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Run a static Pod on a worker

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Run a static Pod named `ar-static-web` in namespace `ar-cp` on node `cka-worker`. It uses image `nginx:1.27`, has the label `app=ar-static-web` and declares container port 80. It must be started by the kubelet on `cka-worker` from a manifest file, so that deleting it through the API does not get rid of it.

<details>
<summary>💡 Hints</summary>

- Generate the YAML with kubectl run … --dry-run=client -o yaml, then place the file in the kubelet's staticPodPath on cka-worker.
- Read the path from /var/lib/kubelet/config.yaml on that node. In a real cluster it is not guaranteed to be the same on every node.
- The mirror Pod shows up in the API as ar-static-web-cka-worker.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl run ar-static-web -n ar-cp --image=nginx:1.27 --labels=app=ar-static-web --port=80 --dry-run=client -o yaml > /tmp/cka/ar-static-web.yaml
docker exec cka-worker awk '/^staticPodPath:/ {print $2}' /var/lib/kubelet/config.yaml
docker exec -i cka-worker sh -c 'cat > /etc/kubernetes/manifests/ar-static-web.yaml' < /tmp/cka/ar-static-web.yaml
for i in $(seq 1 30); do kubectl -n ar-cp get pod ar-static-web-cka-worker >/dev/null 2>&1 && break; sleep 3; done
kubectl -n ar-cp wait --for=condition=Ready pod/ar-static-web-cka-worker --timeout=90s
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the working folder if needed.
- `kubectl run ar-static-web` — Generates a Pod manifest with the name, namespace, image, label and port the task asks for. `--dry-run=client -o yaml` only prints it and `>` saves it; nothing is created in the cluster.
- `docker exec cka-worker awk` — Checks the static Pod folder on **this** node before writing to it. It is normally `/etc/kubernetes/manifests`, but every kubelet has its own config.
- `docker exec -i cka-worker sh -c` — Copies the file onto the worker. `-i` feeds your local file in through `` inside the node writes it into the manifests folder, where the kubelet finds it within about 20 seconds.
- `for i in $(seq 1 30)` — A wait loop: up to 30 times, look for the mirror Pod `ar-static-web-cka-worker`, `break` out as soon as it exists, otherwise sleep 3 seconds. `>/dev/null 2>&1` hides output and errors.
- `kubectl -n ar-cp wait` — Waits for the Pod to be Ready. `kubectl wait` fails at once on a Pod that does not exist yet, which is why the loop comes first.

**Notes:** Exam flow: generate the manifest on the base host, `ssh` to the node, `sudo -i`, check `staticPodPath` in `/var/lib/kubelet/config.yaml`, and write the file there with vim or a heredoc. Then wait 20 seconds and look for `ar-static-web-` with `kubectl get pods -n ar-cp -o wide`. The namespace in the manifest must already exist, or the kubelet runs the container but cannot create the mirror Pod, and the grader sees nothing. To remove a static Pod, delete its file; `kubectl delete pod` only removes the mirror until the kubelet recreates it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ar-cp
pod=ar-static-web-cka-worker
g() { kubectl -n $ns get pod $pod -o jsonpath="$1" 2>/dev/null; }

kubectl -n $ns get pod $pod >/dev/null 2>&1 && p "mirror Pod $pod exists" || f "mirror Pod $pod exists"
[ "$(g '{.spec.nodeName}')" = "cka-worker" ] && p "runs on cka-worker" || f "runs on cka-worker"
[ "$(g '{.metadata.ownerReferences[0].kind}')" = "Node" ] && p "owned by the Node, so it is a static Pod" || f "owned by the Node, so it is a static Pod"
[ "$(g '{.spec.containers[0].image}')" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$(g '{.metadata.labels.app}')" = "ar-static-web" ] && p "label app=ar-static-web" || f "label app=ar-static-web"
[ "$(g '{.spec.containers[0].ports[0].containerPort}')" = "80" ] && p "container port 80" || f "container port 80"
[ "$(g '{.status.phase}')" = "Running" ] && p "Pod is Running" || f "Pod is Running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
