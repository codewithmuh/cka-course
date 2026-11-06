# Build your lab cluster

> **Module 0** · Lesson 0.2 · 45 minutes

Install Docker, kind, kubectl and Helm, build the three-node lab every task in this course runs on, and learn to check, reset and delete it.

## Learning Objectives

- You can build the cka lab cluster with one command and say what each extra is for.
- You can open a shell on a lab node and say how that differs from ssh on the exam.
- You can fix the common lab problems (Docker not running, a port in use, slow downloads) without rereading this page.


Every task in this course ends with a check script, and that script needs a cluster to look at. So you will build a small cluster on your own computer: the **lab**. It uses [kind](https://kind.sigs.k8s.io) (short for Kubernetes in Docker), a tool that runs each Kubernetes node as a Docker container. It is free, and it builds or resets in a few minutes.

**What the lab looks like**

*kind builds the cluster out of Docker containers. kubectl on your computer reaches it through the context `kind-cka`.*

`Your computer` — you type kubectl here → `Docker` — runs each node as a container → `Cluster cka` — three nodes
  - `cka-control-plane` — makes the decisions
  - `cka-worker` — runs your Pods
  - `cka-worker2` — runs your Pods

Inside each container, kind sets the node up with kubeadm, the same setup tool the exam clusters use. So the parts and the file paths match the exam. Only the kubeadm work itself (installing, upgrading, joining nodes) needs real machines; see the end of this page.

## Install the tools

| Tool | What it does |
| --- | --- |
| **Docker** | Runs containers. kind needs it. |
| **kind** | Builds a Kubernetes cluster out of Docker containers. You use it only for the lab. |
| **kubectl** | The command you use to talk to any cluster, in the lab and on the exam. |
| **Helm** | Installs packaged apps, called charts. The Helm lesson uses it. |

**macOS: Docker Desktop or Colima, then kind, kubectl and helm**

```bash
# Option A: Docker Desktop (give it at least 4 GB memory and 2 CPUs under Settings > Resources)
brew install --cask docker
open -a Docker

# Option B: Colima, a lighter Docker runtime for macOS
brew install colima docker
colima start --cpu 4 --memory 6

# The cluster tools
brew install kind kubectl helm

docker info >/dev/null && echo "docker ok"
kind version && kubectl version --client && helm version --short
```

<details>
<summary>Line-by-line explanation</summary>

- `brew install --cask docker` — Installs Docker Desktop with Homebrew, the macOS package manager. `--cask` is how Homebrew installs desktop apps rather than command-line tools.
- `open -a Docker` — Starts the Docker Desktop app. Wait until it says Docker is running before you go on: kind needs Docker.
- `brew install colima docker` — The lighter alternative: Colima runs Docker inside a small Linux VM, and `docker` here is only the command-line client. Pick option A or B, not both.
- `colima start --cpu 4 --memory 6` — Starts that VM with 4 CPUs and 6 GB of memory. Three Kubernetes nodes need the room; with less, Pods get stuck or evicted.
- `brew install kind kubectl helm` — **kind** builds Kubernetes clusters out of Docker containers, **kubectl** is the tool you talk to every cluster with, and **helm** installs packaged apps called charts.
- `docker info >/dev/null` — Checks that Docker answers. `>/dev/null` hides the long output, and `&&` runs the `echo` only if the check worked, so seeing "docker ok" means Docker is ready.
- `kind version &&` — Prints each tool's version. If one of them says "command not found", that install did not work.

</details>

**Ubuntu 24.04 (and Windows inside a WSL2 Ubuntu shell)**

```bash
# Docker Engine from Docker's apt repository
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker "$USER" && newgrp docker

# kind: a single release binary (pick amd64 or arm64)
arch=amd64; [ "$(uname -m)" = aarch64 ] && arch=arm64
curl -Lo kind "https://kind.sigs.k8s.io/dl/v0.32.0/kind-linux-$arch"
chmod +x kind && sudo mv kind /usr/local/bin/kind

# kubectl: the current stable release
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$arch/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm: the release tarball
curl -fsSL "https://get.helm.sh/helm-v4.2.3-linux-$arch.tar.gz" | tar -xz
sudo mv "linux-$arch/helm" /usr/local/bin/helm && rm -rf "linux-$arch"

# kind needs more inotify headroom than Ubuntu ships with
sudo sysctl fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo apt-get update && sudo apt-get install -y ca-certificates curl` — Refreshes Ubuntu's package list, then installs certificates for HTTPS downloads and `curl` for fetching files. `-y` answers yes to the prompt.
- `sudo install -m 0755 -d /etc/apt/keyrings` — Creates the folder where apt keeps the signing keys of extra package repositories.
- `sudo curl -fsSL https://download.docker.com` — Downloads Docker's signing key. apt uses it to check that packages really come from Docker.
- `echo "deb [arch=` — Adds Docker's package repository for your Ubuntu version and CPU type. The `$(...)` parts fill in those two values for you.
- `sudo apt-get install -y docker-ce` — Installs Docker Engine: the background service, its command-line client and containerd, the runtime that actually runs containers.
- `sudo usermod -aG docker` — Adds you to the `docker` group so you can run Docker without `sudo`. `newgrp docker` applies it to this shell; other terminals need a fresh login.
- `arch=amd64;` — Picks the right download for your CPU: `amd64` for Intel and AMD, `arm64` when `uname -m` reports an ARM machine.
- `curl -Lo kind` — Downloads the kind program. `-L` follows redirects and `-o kind` saves it under that name.
- `chmod +x kind && sudo mv kind` — Makes the file executable and moves it to `/usr/local/bin`, a folder on your PATH, so `kind` works from any directory.
- `curl -LO "https://dl.k8s.io/release/` — Downloads kubectl. The inner `curl` first asks which version is the current stable release, so you always get the latest.
- `sudo install -o root -g root -m 0755 kubectl` — Copies kubectl to `/usr/local/bin`, owned by root and runnable by everyone: chmod and mv in one command.
- `curl -fsSL "https://get.helm.sh/` — Downloads the Helm release archive and unpacks it straight from the pipe. `tar -xz` means extract a gzip-compressed archive.
- `sudo mv "linux-$arch/helm"` — Moves the helm program onto your PATH and deletes the leftover folder.
- `sudo sysctl fs.inotify` — Raises two Linux limits on file watchers. Every kind node runs many processes that watch files, and Ubuntu's defaults are too low for three nodes.

</details>

- **Windows:** install Docker Desktop with the WSL 2 backend, then Ubuntu from the Microsoft Store. In Docker Desktop, turn on Settings > Resources > WSL integration for Ubuntu. Then do everything from the Ubuntu shell with the Ubuntu block above, minus its Docker Engine part: Docker Desktop already gives Ubuntu the `docker` command.
- **kubectl version:** kubectl works with an API server at most one minor version older or newer. Once the lab is up, run `kubectl version` and compare the Client and Server versions. If they are further apart, install the matching kubectl from the [install page](https://kubernetes.io/docs/tasks/tools/). The exam runs v1.37, so kubectl v1.37 on a v1.36 or v1.37 lab is ideal.
- **Memory and CPU:** give Docker at least 4 GB of memory and 2 CPUs for the three nodes and the extras. 6 GB is comfortable.

## Build the lab

**One command, three to six minutes on first run**

```bash
curl -fsSL https://codewithmuh.com/labs/cka/lab-up.sh | bash

# Prefer to read it first? Same thing, two steps:
curl -fsSLO https://codewithmuh.com/labs/cka/lab-up.sh && less lab-up.sh && bash lab-up.sh

# When it finishes you should see three Ready nodes and the summary block:
kubectl get nodes -o wide
kubectl config current-context      # kind-cka
```

<details>
<summary>Line-by-line explanation</summary>

- `https://codewithmuh.com/labs/cka/lab-up.sh | bash` — Downloads the lab script and runs it straight away. `-fsSL` means fail on HTTP errors, stay quiet, still show errors, and follow redirects. The `|` hands the script to `bash`.
- `curl -fsSLO` — The careful version: `-O` saves the script as a file, `less` lets you read it (press `q` to quit), and only then `bash` runs it.
- `kubectl get nodes -o wide` — Lists the cluster's machines. You want three, all **Ready**. `-o wide` adds columns such as each node's IP and Kubernetes version.
- `kubectl config current-context` — Shows which cluster kubectl is talking to. It should print `kind-cka`; every task in this course assumes that context.

</details>

The script builds the cluster, then adds the extras the exam topics need:

| Part | What it is for |
| --- | --- |
| The cluster `cka` | Built from `kind-config.yaml`: one control plane node, `cka-control-plane`, and two workers, `cka-worker` and `cka-worker2`. Its kubectl context is `kind-cka`. |
| Calico | The pod network. The script turns off kind's own network plugin and installs Calico instead. Calico enforces NetworkPolicies, which the exam's NetworkPolicy tasks need. |
| metrics-server | Makes `kubectl top nodes` and `kubectl top pods` show numbers. It needs about a minute after install before it has data. It runs with `--kubelet-insecure-tls`, because kind's kubelet certificates are self-signed. |
| ingress-nginx | The Ingress controller, with IngressClass `nginx`. It runs on the control plane node. That node's ports 80 and 443 reach your computer as `localhost:8080` and `localhost:8443`. |
| Gateway API CRDs | Let you create Gateway and HTTPRoute objects. There is no Gateway controller, so routes do not carry traffic. The exam checks the objects, so that is enough to practice. |
| NodePort 30080 | Port 30080 on the control plane node reaches your computer as `localhost:30080`. Other NodePorts work only from inside the cluster or from a node shell. |
| The folder `/tmp/cka` | Where every task writes its answer files. The exam uses paths like `/opt/course/3/answer.txt`: same idea, different folder. |

## A shell on a node

Some tasks need a shell on a node, for example to read a file under `/etc/kubernetes`. kind nodes are containers, so in the lab you open that shell with `docker exec`. On the exam, nodes are real machines, so you use `ssh`. Every node task in this course shows both.

**One node shell, two ways in**

`In the lab` — you are root at once (`docker exec -it cka-control-plane bash`)   `On the exam` — then sudo -i to become root (`ssh <node>`)

- Use `cka-worker` or `cka-worker2` instead of `cka-control-plane` to reach the other nodes.
- Inside, `systemctl`, `journalctl`, `crictl` and `/etc/kubernetes` are where you would find them on an exam node.
- One difference: here the kubelet runs inside a container. Restarting it is quick, and you cannot reboot a kind node.

## Check, reset, delete

Three more scripts look after the lab. Run the check whenever something looks wrong. Reset before each mock exam, so leftovers from one attempt do not spoil the next.

**Check, reset, tear down**

```bash
# Health check: one PASS line per component, RESULT: PASS at the end. Run it when anything looks off.
curl -fsSL https://codewithmuh.com/labs/cka/lab-check.sh | bash

# Reset: deletes the cluster and runs lab-up again (two to four minutes). Use it between mock exams
# so leftover namespaces, taints and cordoned nodes from one attempt do not pollute the next.
curl -fsSL https://codewithmuh.com/labs/cka/lab-reset.sh | bash

# Tear down: deletes the cluster. Nothing else on your machine is touched; lab-up rebuilds it.
curl -fsSL https://codewithmuh.com/labs/cka/lab-down.sh | bash

# lab-up is idempotent: re-running it on an existing cluster just re-applies the add-ons.
```

<details>
<summary>Line-by-line explanation</summary>

- `lab-check.sh | bash` — Runs the health check. It prints PASS or FAIL for each part of the lab and changes nothing, so it is always safe to run.
- `lab-reset.sh | bash` — Deletes the cluster and builds a fresh one. Everything you created is gone, which is exactly what you want before a mock exam.
- `lab-down.sh | bash` — Deletes the cluster to free memory when you stop studying. Docker and your files stay; run lab-up again next time.

</details>

## When the lab misbehaves

| What you see | Why | Fix |
| --- | --- | --- |
| lab-up says "Docker is not running", or `docker info` hangs | Docker is not running | Start Docker: open Docker Desktop, run `colima start`, or on Linux run `sudo systemctl start docker`. |
| "port is already allocated" for 8080, 8443 or 30080 | Another program already uses that port | Find it with `lsof -i :8080` (or `ss -ltnp`) and stop it. Or download `kind-config.yaml`, change its `hostPort` values, and run lab-up.sh in the same folder: it uses that local file. |
| calico-node or ingress-nginx Pods stay in ContainerCreating for minutes | Images are still downloading, which is slow the first time | Wait, and watch with `kubectl -n kube-system get pods -w`. Then run lab-up again: it carries on where it stopped. |
| Nodes stay NotReady for more than two minutes | The pod network is not up yet, or the Linux inotify limits are too low | Look at `kubectl -n kube-system get pods`, then raise the inotify limits (the last line of the Ubuntu block), then run lab-up again. |
| `kubectl top` says metrics are not available | metrics-server has no data yet | Wait 60 seconds and try again. |
| After a reboot the cluster exists, but the context is gone | The kubeconfig entry was removed, or Docker restarted the containers | Run `kind export kubeconfig --name cka`, then lab-check. |
| Everything acts strangely and you do not know why | Leftovers from earlier tasks | Run lab-reset.sh. |

> [!IMPORTANT] **What carries over to the exam, and what does not**
> Almost everything works the same on kind as on the exam's kubeadm clusters: kubectl, RBAC, scheduling, probes, Services, Ingress, NetworkPolicies, storage, DNS, logs, metrics, `kubectl debug`, static Pods and the kubelet. The check scripts look at the same fields a grader would. What you cannot practice here is `kubeadm init`, `join` and `upgrade` on real machines. The architecture module still teaches them, and marks their tasks as needing a kubeadm cluster.

## Optional: a kubeadm lab on virtual machines

The kind lab cannot upgrade a cluster with kubeadm or join a new node. To do those once with your own hands, build a small lab of virtual machines (VMs) the week before a mock. You need it for two lessons only; the kind lab covers everything else.

- **Size:** two or three Ubuntu 24.04 VMs, each with 2 CPUs and 2 to 4 GB of memory.
- **Tool:** [Multipass](https://canonical.com/multipass) (`multipass launch 24.04 --name cp --cpus 2 --memory 4G --disk 20G`, the same for `w1` and `w2`, then `multipass shell cp`), or Vagrant with a `bento/ubuntu-24.04` box per node on a private network.
- **Steps:** follow [Installing a cluster with kubeadm](/cka/architecture/kubeadm-install), then [Upgrading clusters and draining nodes](/cka/architecture/cluster-upgrades). Go slowly.

## 📝 Key Takeaways

- The lab is a kind cluster: three Kubernetes nodes running as Docker containers on your computer. Its kubectl context is `kind-cka`.
- `lab-up.sh` builds it, `lab-check.sh` checks it, `lab-reset.sh` gives you a fresh one, and `lab-down.sh` deletes it.
- A node shell is `docker exec -it cka-control-plane bash` in the lab, and `ssh ` then `sudo -i` on the exam.
- Answer files go in `/tmp/cka`. On the exam, the question gives the path.
- Everything except installing, joining and upgrading with kubeadm works the same as on the exam.

**📖 Official documentation:**

- [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/) *(search: "kind quick start")*
- [Install and set up kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) *(search: "install kubectl")*
- [Installing Helm](https://helm.sh/docs/intro/install/) *(search: "installing helm")*
- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) *(search: "installing kubeadm")*

---

### 🎯 Task: Prove the lab is healthy

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 2% |
| **Time** | 3 min |

**Question:**

Bring the lab up and make every line of the lab check pass: context `kind-cka` exists, three nodes are Ready, Calico is installed, `kubectl top nodes` returns data, ingress-nginx and the Gateway API CRDs are installed, `docker exec cka-control-plane true` works, and `/tmp/cka` exists.

<details>
<summary>💡 Hints</summary>

- Run `curl -fsSL https://codewithmuh.com/labs/cka/lab-up.sh | bash`, then the lab-check script.
- `kubectl top` needs about a minute after metrics-server starts. If only that line fails, wait and run the check again.

</details>

<details>
<summary>✅ Solution</summary>

```bash
curl -fsSL https://codewithmuh.com/labs/cka/lab-up.sh | bash
curl -fsSL https://codewithmuh.com/labs/cka/lab-check.sh | bash
```

**Explanation:**

- `lab-up.sh | bash` — Builds the lab cluster, or re-applies its add-ons if the cluster already exists, so running it twice is safe.
- `lab-check.sh | bash` — Confirms the result. The task passes when this ends with RESULT: PASS.

**Notes:** This task's check script is the lab-check script itself. When it passes, the course page marks your lab as ready. Every later task expects the lab in exactly this state.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

kubectl config get-contexts kind-cka >/dev/null 2>&1 && p "context kind-cka exists" || f "context kind-cka exists"
[ "$(kubectl --context kind-cka get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "3" ] && p "3 nodes" || f "3 nodes"
[ -z "$(kubectl --context kind-cka get nodes --no-headers 2>/dev/null | grep -v ' Ready ')" ] && p "all nodes Ready" || f "all nodes Ready"
kubectl --context kind-cka -n kube-system get ds calico-node >/dev/null 2>&1 && p "Calico installed" || f "Calico installed"
kubectl --context kind-cka top nodes >/dev/null 2>&1 && p "metrics-server serving (kubectl top)" || f "metrics-server serving (kubectl top)"
kubectl --context kind-cka -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1 && p "ingress-nginx installed" || f "ingress-nginx installed"
kubectl --context kind-cka get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 && p "Gateway API CRDs installed" || f "Gateway API CRDs installed"
docker exec cka-control-plane true >/dev/null 2>&1 && p "node shell works (docker exec cka-control-plane)" || f "node shell works (docker exec cka-control-plane)"
mkdir -p /tmp/cka 2>/dev/null && p "/tmp/cka answers dir" || f "/tmp/cka answers dir"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: First Pod on the lab

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 2% |
| **Time** | 3 min |

**Question:**

Create a namespace named `fd-hello`. In it, create a Pod named `hello` running the image `nginx:1.27`. The Pod must be in the `Running` state when you are done.

<details>
<summary>💡 Hints</summary>

- Use `kubectl create namespace`, then `kubectl run` with `--image`. No YAML needed.
- `kubectl get pod -n fd-hello -w` shows the Pod move from ContainerCreating to Running.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl create namespace fd-hello
kubectl -n fd-hello run hello --image=nginx:1.27
kubectl -n fd-hello wait --for=condition=Ready pod/hello --timeout=120s
kubectl -n fd-hello get pod hello -o wide
```

**Explanation:**

- `kubectl create namespace fd-hello` — Creates a **namespace**: a named area inside the cluster that keeps this task's objects apart from everything else.
- `run hello` — Starts a single Pod called `hello` running the nginx 1.27 image. `-n fd-hello` puts it in that namespace; without `-n` it would land in `default`.
- `wait --for=condition=Ready` — Pauses until the Pod is Ready (its container started and passed its checks), or gives up after 120 seconds. Better than running `get` again and again.
- `get pod hello -o wide` — Shows the Pod's status, its IP and the node it runs on.

**Notes:** `kubectl run` always creates a single Pod, never a Deployment. Check the two things the grader sees. First the namespace: put `-n` on every command, or make it the default with `kubectl config set-context --current --namespace=fd-hello`. Second the exact image tag: `kubectl get pod hello -n fd-hello -o jsonpath='{.spec.containers[0].image}'` shows it in a second.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=fd-hello

kubectl get ns $ns >/dev/null 2>&1 && p "namespace $ns exists" || f "namespace $ns exists"
kubectl -n $ns get pod hello >/dev/null 2>&1 && p "pod hello exists" || f "pod hello exists"
[ "$(kubectl -n $ns get pod hello -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$(kubectl -n $ns get pod hello -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 0: Start here*
