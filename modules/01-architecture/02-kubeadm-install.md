# Installing a cluster with kubeadm

> **Module 1** · Lesson 1.2 · 45 minutes

Get Ubuntu machines ready, build a control plane with kubeadm init, add a pod network and join the workers, step by step.

## Learning Objectives

- You can get a Linux machine ready for kubeadm: swap off, kernel modules and settings, containerd with the systemd cgroup driver, and the Kubernetes packages from pkgs.k8s.io held at one version.
- You can run kubeadm init with a pod network range, set up kubectl and install a network plugin (CNI).
- You can print a fresh join command, say what each part of it does and add a worker node.


**kubeadm** is the setup tool that turns a few prepared Linux machines into a Kubernetes cluster. You run `kubeadm init` once, on the first machine, to build the control plane. Then you run `kubeadm join` on every other machine to add it. kubeadm is not kubectl (your everyday command-line tool) and not the kubelet (the agent on every node); [Control plane and node components](/cka/architecture/control-plane-and-nodes) keeps the three apart.

The exam rarely asks you to build a cluster from nothing. More often it gives you a half-prepared node, a worker to join, or a kubeadm error to read. This lesson covers two exam topics: **Prepare underlying infrastructure for installing a Kubernetes cluster** and **Create and manage Kubernetes clusters using kubeadm**.

**Building a cluster in four steps**

*Steps 1 and 2 run on every machine. Step 3 runs once, on the first control plane machine. Step 4 runs on each worker.*

`1. Prepare every machine` — swap off, kernel settings, containerd → `2. Install the packages` — kubeadm, kubelet and kubectl → `3. kubeadm init` — builds the control plane, then add a network plugin → `4. kubeadm join` — adds each worker to the cluster

> [!TIP] **Where to practice**
> kind, the tool behind this course's lab, runs these same steps inside containers for you. To do them by hand, use two Ubuntu 24.04 virtual machines (Multipass, Vagrant or any cloud). Give each at least 2 CPUs and 2 GiB of RAM. Run every command as a user with sudo.

## Step 1: prepare every machine

Run these steps on every machine, control plane and workers alike. They turn swap off and switch on the kernel modules and settings that Pod networking needs. Then they install containerd, the container runtime.

**Swap, kernel modules and sysctls (control plane and workers)**

```bash
# Swap off now and after reboots
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules, loaded now and at boot
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# sysctls, persisted and applied now
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo swapoff -a` — Turns off all swap right now. `sudo` runs a command as root, which almost every node preparation step needs.
- `s/^/#/` — Keeps swap off after a reboot. `sed -i` edits `/etc/fstab`, the list of disks mounted at boot, in place: every line containing ` swap ` gets a `#` in front, which turns it into a comment.
- `sudo tee /etc/modules-load.d/k8s.conf` — Writes the two module names below into a file Linux reads at every boot. `sudo tee` does the writing because a plain `>` would run as you, not as root, and fail.
- `sudo modprobe overlay` — Loads the `overlay` module now, without a reboot. containerd uses it to stack image layers into a container's filesystem.
- `sudo modprobe br_netfilter` — Loads `br_netfilter`, which lets iptables see traffic crossing a Linux bridge. The two `bridge-nf-call` settings below exist only once it is loaded.
- `sudo tee /etc/sysctl.d/k8s.conf` — Writes three kernel settings, called sysctls, to a file that is applied at every boot.
- `net.ipv4.ip_forward = 1` — Lets the node forward packets from one network interface to another, so traffic can reach Pods. kubeadm's preflight check stops if this is off.
- `net.bridge.bridge-nf-call-iptables = 1` — Sends bridged IPv4 traffic through iptables, which kube-proxy and most CNI plugins rely on. The next line does the same for IPv6.
- `sudo sysctl --system` — Applies every sysctl file on the machine now, the new one included, so no reboot is needed.
- `sysctl net.ipv4.ip_forward net.bridge` — Reads the two values back. Both should end in `= 1`.

</details>

**containerd with the systemd cgroup driver**

```bash
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep SystemdCgroup /etc/containerd/config.toml      # SystemdCgroup = true

sudo systemctl restart containerd
sudo systemctl enable containerd
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo apt-get update` — Refreshes Ubuntu's list of available packages, so the install below finds current versions.
- `sudo apt-get install -y containerd` — Installs containerd, the container runtime the kubelet will drive, from Ubuntu's own repository. `-y` answers yes to the confirmation prompt.
- `sudo mkdir -p /etc/containerd` — Creates containerd's config folder. `-p` means no error if it is already there.
- `containerd config default` — Prints containerd's complete default configuration and saves it as `config.toml`, giving you a file to edit. `>/dev/null` hides the copy that `tee` also prints to the screen.
- `s/SystemdCgroup = false/SystemdCgroup = true/` — Switches runc to the systemd cgroup driver, editing the file in place. kubeadm sets the kubelet to systemd, and the two must agree, or control plane Pods restart for no visible reason.
- `grep SystemdCgroup` — Confirms the edit: you want `SystemdCgroup = true`. If you see `false`, or nothing at all, the `sed` did not match and the file needs fixing by hand.
- `sudo systemctl restart containerd` — Restarts containerd so it reads the changed file; a running service does not notice config edits on its own.
- `sudo systemctl enable containerd` — Makes containerd start automatically at every boot.

</details>

Press **Explain** on each block to see what every line is for. Two steps trip people up most:

- **Swap must be off.** By default the kubelet refuses to start on a machine with swap on. You can allow swap with `failSwapOn: false`, but on a kubeadm lab or exam node, just turn it off.
- **containerd and the kubelet must use the same cgroup driver.** A cgroup driver is how Linux limits a container's CPU and memory. kubeadm sets the kubelet to `systemd`, so containerd must use `systemd` too. If they differ, control plane Pods keep restarting for no visible reason.

## Step 2: install kubeadm, kubelet and kubectl

Install all three tools on every machine, at exactly the same version. Each pkgs.k8s.io repository serves only one minor version, such as 1.37. That is why the URL below contains `v1.37`, and why every upgrade starts by changing it (see [Upgrading clusters](/cka/architecture/cluster-upgrades)).

**kubeadm, kubelet and kubectl from pkgs.k8s.io**

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
apt-cache madison kubeadm | head -3        # package versions look like 1.37.1-1.1
VER=1.37.1-1.1                             # pick one from the list
sudo apt-get install -y kubelet=$VER kubeadm=$VER kubectl=$VER
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

<details>
<summary>Line-by-line explanation</summary>

- `apt-transport-https ca-certificates curl gpg` — Installs what apt needs to use an extra HTTPS repository: CA certificates, `curl` to download its key and `gpg` to convert it.
- `sudo mkdir -p -m 755 /etc/apt/keyrings` — Creates the folder for repository signing keys. `-m 755` lets everyone read it and only root write to it.
- `Release.key | sudo gpg --dearmor` — Downloads the Kubernetes repository's signing key and converts it to the binary format apt reads (`--dearmor`). apt uses it to check that packages really come from Kubernetes.
- `echo 'deb [signed-by=` — Adds the repository, tied to that key by `signed-by`. The URL contains `v1.37` because each repository serves one minor version, which is why an upgrade starts by editing this file.
- `sudo apt-get update` — Reloads the package list, now including the Kubernetes repository.
- `apt-cache madison kubeadm` — Lists the kubeadm versions the repository offers; `head -3` shows only the first three lines. Package versions carry a suffix, as in `1.37.1-1.1`.
- `VER=1.37.1-1.1` — Saves the version you picked in a shell variable. From here on `$VER` means `1.37.1-1.1`, so all three packages get exactly the same one.
- `kubelet=$VER kubeadm=$VER kubectl=$VER` — Installs the three tools, each pinned with `name=version`. The kubelet is the agent on every node, kubeadm builds and upgrades the cluster, and kubectl is your client.
- `sudo apt-mark hold` — Freezes the three packages so a routine `apt upgrade` cannot move them. Upgrades happen on purpose, starting with `apt-mark unhold`.
- `sudo systemctl enable --now kubelet` — Enables the kubelet at boot and starts it now (`--now`). It restarts every few seconds until `kubeadm init` or `join` gives it a config; that is expected.

</details>

After this step the kubelet restarts every few seconds. That is normal: it has no settings yet, until `kubeadm init` or `kubeadm join` writes them.

## Step 3: kubeadm init and a network plugin

Run `kubeadm init` on the first machine only. It builds the control plane there: certificates, settings files and the static Pods for the API server, etcd, the scheduler and the controller manager. (`kubeadm init phase --help` lists every step it runs.) It does **not** install a pod network. You add one right after, and until then the node stays NotReady.

**kubeadm init, kubeconfig, CNI (control plane node only)**

```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-advertise-address=10.0.0.10 \
  --kubernetes-version=v1.37.1

# kubectl for your user; kubeadm prints these lines when it finishes
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes                  # NotReady: no pod network yet
kubectl -n kube-system get pods    # coredns Pending for the same reason

# A CNI plugin. Calico's manifest defaults to 192.168.0.0/16.
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
kubectl -n kube-system rollout status ds/calico-node --timeout=300s
kubectl get nodes                  # Ready
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo kubeadm init` — Builds the control plane on this machine: certificates, kubeconfig files, static Pod manifests and the CoreDNS and kube-proxy add-ons. Each `\` at a line end continues the same command.
- `--pod-network-cidr=192.168.0.0/16` — The range Pods get their IPs from. It must not overlap the node or Service networks, and it must match what the CNI plugin will use.
- `--apiserver-advertise-address=10.0.0.10` — The node IP the API server announces to the rest of the cluster. Without it, kubeadm uses the address of the default network interface.
- `--kubernetes-version=v1.37.1` — Pins the control plane to exactly this version, so it matches the packages you installed instead of whatever kubeadm would choose.
- `mkdir -p $HOME/.kube` — Creates the folder kubectl reads its config from, in your home directory.
- `sudo cp -i /etc/kubernetes/admin.conf` — Copies the admin kubeconfig kubeadm wrote to kubectl's default location, `~/.kube/config`. `-i` asks before overwriting a file that is already there.
- `sudo chown` — The copy belongs to root because of `sudo`. This makes you the owner: `$(id -u)` and `$(id -g)` fill in your user and group IDs.
- `# NotReady` — **NotReady** is expected at this point: kubeadm installs no pod network, so the kubelet reports its network as not ready.
- `kubectl -n kube-system get pods` — The control plane Pods run, but CoreDNS stays Pending: it needs the pod network as well.
- `calico.yaml` — Installs Calico, the CNI plugin, from one manifest that creates its DaemonSet, CRDs and RBAC rules. Its default pool is 192.168.0.0/16, matching the CIDR above.
- `rollout status ds/calico-node` — Waits until the `calico-node` Pods run on every node, or gives up after 300 seconds.
- `# Ready` — With the network up, the node turns Ready and CoreDNS starts.

</details>

**Pick a pod network range that does not overlap.** The range in `--pod-network-cidr` must not overlap your machines' network or the Service range. For example, if your VMs have addresses like 192.168.1.20, then 192.168.0.0/16 clashes with them. Use `--pod-network-cidr=10.244.0.0/16` instead, and set `CALICO_IPV4POOL_CIDR` in calico.yaml to the same value before you apply it.

## Step 4: join the workers

A worker joins with one command, `kubeadm join`, run on the worker itself. The control plane prints that command for you. It has three parts:

| Part of the join command | What it is | Example |
| --- | --- | --- |
| The address | Where the worker finds the API server: an IP or name, and port 6443. | `10.0.0.10:6443` |
| `--token` | A **bootstrap token**: a short-lived password that lets a new node join. By default it expires after 24 hours. | `abcdef.0123456789abcdef` |
| `--discovery-token-ca-cert-hash` | A fingerprint of the cluster CA's public key. The worker checks it, so it cannot be tricked into joining a fake cluster. | `sha256:` and 64 hex characters |

**How a worker joins**

`Control plane` (`kubeadm token create --print-join-command`) → `The join command` — address, token and CA hash → `Worker` — runs it and joins the cluster (`sudo kubeadm join …`)

**Join the workers**

```bash
# On the control plane. The token from kubeadm init expires after 24 hours, so mint a fresh command.
sudo kubeadm token create --print-join-command
# kubeadm join 10.0.0.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# On each worker, after the node preparation above
sudo kubeadm join 10.0.0.10:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# The hash pins the cluster CA's public key. You can compute it yourself on the control plane:
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'

# Token housekeeping
sudo kubeadm token list
sudo kubeadm token delete <token-id>

kubectl get nodes -o wide
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo kubeadm token create --print-join-command` — Creates a new bootstrap token, valid 24 hours by default, and prints the complete join command that uses it, ready to paste on the worker.
- `sudo kubeadm join 10.0.0.10:6443` — Runs on the new worker. It contacts the API server at that address, authenticates with the token and configures its kubelet. `` and `` stand for the printed values.
- `--discovery-token-ca-cert-hash sha256:<hash>` — The hash of the cluster CA's public key. The worker checks the cluster it reaches against it, so it cannot be tricked into joining a fake cluster.
- `openssl x509 -pubkey` — Computes that hash yourself: extract the public key from `ca.crt`, convert it to binary DER, take its SHA-256 and let `sed` keep only the hex digits. Put `sha256:` in front when you use it.
- `sudo kubeadm token list` — Shows the existing bootstrap tokens and when each one expires.
- `sudo kubeadm token delete` — Revokes a token so nobody can join with it any more. The token ID is the part before the dot.
- `kubectl get nodes -o wide` — The new worker appears, and turns Ready once its Calico Pod is running.

</details>

> [!IMPORTANT] **What the grader checks, and the usual traps**
> The grader runs `kubectl get nodes`. The new node must be listed, be `Ready` and run the expected kubelet version. Run `kubeadm join` on the *new* node, with sudo, not on the control plane. If an earlier try left files behind, the join fails with *already exists* errors. Run `sudo kubeadm reset -f` on that node, then join again. A node that joins but stays NotReady is covered in [Worker node failures](/cka/troubleshooting/worker-node-failures).

## 📝 Key Takeaways

- kubeadm builds the cluster: `kubeadm init` once on the first control plane machine, then `kubeadm join` on every other machine.
- Prepare every machine first: swap off, the kernel modules and settings, containerd with `SystemdCgroup = true`, and kubeadm, kubelet and kubectl at the same version, held.
- kubeadm installs no pod network. The node stays NotReady until you apply a network plugin such as Calico.
- Lost the join command, or the token expired? `kubeadm token create --print-join-command` prints a fresh one.

**📖 Official documentation:**

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) *(search: "installing kubeadm")*
- [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) *(search: "container runtimes systemd cgroup")*
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) *(search: "create cluster kubeadm")*
- [kubeadm join](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/) *(search: "kubeadm join")*
- [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) *(search: "ports and protocols")*

---

### 🎯 Task: Prepare a node and bootstrap a control plane

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 8% |
| **Time** | 20 min |

**Question:**

Node `cp1` is a fresh Ubuntu 24.04 VM with 2 CPUs and 4 GiB of RAM. Prepare it for Kubernetes: swap off, the kernel modules and sysctls a cluster needs, containerd using the systemd cgroup driver, and kubelet, kubeadm and kubectl v1.37 from pkgs.k8s.io held at that version. Then initialize a control plane with pod network CIDR `192.168.0.0/16`, make kubectl work for the user you are logged in as, and install Calico v3.33.0 so that `cp1` becomes Ready.

<details>
<summary>💡 Hints</summary>

- Prepare the node in this lesson's order: swap and kernel settings, then containerd, then the packages.
- kubeadm init does not install a network plugin (CNI). The node stays NotReady until you apply one.

</details>

<details>
<summary>✅ Solution</summary>

```bash
# Run on cp1 as a user with passwordless sudo
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system >/dev/null

sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

sudo kubeadm init --pod-network-cidr=192.168.0.0/16
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
kubectl -n kube-system rollout status ds/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

**Explanation:**

- `sudo swapoff -a` — Swap off now. The `sed` on the next line comments out the swap entry in `/etc/fstab`, so it stays off after a reboot.
- `sudo tee /etc/modules-load.d/k8s.conf` — Lists `overlay` and `br_netfilter` for loading at every boot. The two `modprobe` lines after it load them right away.
- `sudo tee /etc/sysctl.d/k8s.conf` — The kernel settings Kubernetes networking needs: IP forwarding, and bridged IPv4 and IPv6 traffic passed through iptables.
- `sudo sysctl --system >/dev/null` — Applies those settings now. `>/dev/null` only hides the long list of values it prints.
- `sudo apt-get install -y containerd apt-transport-https` — One install for the container runtime and for the tools needed to add the Kubernetes package repository.
- `containerd config default` — Writes containerd's default config to `config.toml` so it can be edited.
- `s/SystemdCgroup = false/SystemdCgroup = true/` — Switches runc to the systemd cgroup driver to match the kubelet. The restart on the next line makes containerd read it, and `enable` starts it at every boot.
- `sudo gpg --dearmor --yes` — Saves the repository's signing key. `--yes` lets gpg overwrite the file if it already exists, so the solution can be run twice.
- `echo 'deb [signed-by=` — Adds the v1.37 package repository.
- `sudo apt-get install -y kubelet kubeadm kubectl` — Installs the newest v1.37 patch release of all three, since this repository holds nothing else. The task asks for v1.37, not a particular patch, so no pin is needed.
- `sudo apt-mark hold` — Holds the packages at that version, as the task requires.
- `sudo systemctl enable --now kubelet` — Starts the kubelet and enables it at boot. It keeps restarting until `kubeadm init` writes its config.
- `sudo kubeadm init --pod-network-cidr=192.168.0.0/16` — Bootstraps the control plane. kubeadm records the CIDR as `podSubnet` in the `kubeadm-config` ConfigMap, and it matches Calico's default pool.
- `mkdir -p $HOME/.kube` — This line and the next two give your own user a working kubectl: copy `admin.conf` to `~/.kube/config` and make yourself its owner.
- `calico/v3.33.0/manifests/calico.yaml` — Installs Calico v3.33.0 as the pod network. Until it runs, the node stays NotReady.
- `rollout status ds/calico-node` — Waits until the `calico-node` DaemonSet is running, for at most 300 seconds.
- `kubectl wait --for=condition=Ready nodes --all` — Waits until every node, here only `cp1`, reports Ready: the end state the task asks for.

**Notes:** If `kubeadm init` fails, read its preflight errors. They name the exact file or setting, for example `/proc/sys/net/ipv4/ip_forward contents are not set to 1`. Fix that and run init again. If init stopped half way, run `sudo kubeadm reset -f` first. Keep the join command it prints. If you lose it, `kubeadm token create --print-join-command` makes a new one. Everything kubeadm decided is saved in the `kubeadm-config` ConfigMap in `kube-system`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
node=cp1

[ -z "$(swapon --show --noheadings 2>/dev/null)" ] && p "swap is off" || f "swap is off"
[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ] && p "net.ipv4.ip_forward = 1" || f "net.ipv4.ip_forward = 1"
[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" = "1" ] && p "bridge-nf-call-iptables = 1" || f "bridge-nf-call-iptables = 1"
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null && p "containerd uses the systemd cgroup driver" || f "containerd uses the systemd cgroup driver"
for pkg in kubelet kubeadm kubectl; do apt-mark showhold 2>/dev/null | grep -qx "$pkg" && p "$pkg is held" || f "$pkg is held"; done
[ "$(kubectl get node $node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "node $node is Ready" || f "node $node is Ready"
case "$(kubectl get node $node -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)" in v1.37.*) p "kubelet is v1.37" ;; *) f "kubelet is v1.37" ;; esac
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' 2>/dev/null | grep -q 'podSubnet: 192.168.0.0/16' && p "podSubnet 192.168.0.0/16" || f "podSubnet 192.168.0.0/16"
kubectl -n kube-system rollout status ds/calico-node --timeout=20s >/dev/null 2>&1 && p "Calico is running" || f "Calico is running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Join a worker with a fresh token

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 8 min |

**Question:**

Node `w1` has been prepared like `cp1` (containerd, v1.37 packages, kubelet enabled) but is not part of the cluster yet, and the token printed by `kubeadm init` has expired. Join `w1` to the cluster as a worker. You can reach it from `cp1` with `ssh w1`.

<details>
<summary>💡 Hints</summary>

- kubeadm token create has a flag that prints the whole join command.
- Run the join command on w1, with sudo.

</details>

<details>
<summary>✅ Solution</summary>

```bash
# On cp1
JOIN=$(sudo kubeadm token create --print-join-command --ttl 1h)
echo "$JOIN"
ssh w1 "sudo $JOIN" </dev/null
kubectl wait --for=condition=Ready node/w1 --timeout=180s
kubectl get nodes -o wide
```

**Explanation:**

- `JOIN=$(sudo kubeadm token create` — Creates a fresh bootstrap token that expires in one hour (`--ttl 1h`) and stores the printed join command in the variable `JOIN`. `$(...)` captures a command's output.
- `echo "$JOIN"` — Shows the command so you can check it before it runs.
- `ssh w1` — Runs the join on `w1` with sudo. Your shell fills in `$JOIN` before ssh sends the command, and `</dev/null` keeps ssh from reading, and swallowing, any lines you paste after it.
- `kubectl wait --for=condition=Ready node/w1` — Waits up to 180 seconds for the new node to report Ready.
- `kubectl get nodes -o wide` — Final check: `w1` is listed, Ready, and runs the same kubelet minor version as `cp1`.

**Notes:** `--ttl 1h` makes the new token expire after one hour instead of the default 24, so it does not linger. If `w1` was joined before, the join fails with errors about files that already exist. Run `sudo kubeadm reset -f` on `w1`, then join again. If `w1` joins but stays NotReady, check the `calico-node` Pod on it, then the kubelet's log with `journalctl -u kubelet` on the node.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

kubectl get node w1 >/dev/null 2>&1 && p "node w1 is registered" || f "node w1 is registered"
[ "$(kubectl get node w1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "w1 is Ready" || f "w1 is Ready"
cp_v=$(kubectl get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
w_v=$(kubectl get node w1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
[ -n "$w_v" ] && [ "$(echo "$w_v" | cut -d. -f1-2)" = "$(echo "$cp_v" | cut -d. -f1-2)" ] && p "w1 kubelet $w_v matches the control plane minor" || f "w1 kubelet matches the control plane minor"
kubectl get node w1 --show-labels --no-headers 2>/dev/null | grep -q 'node-role.kubernetes.io/control-plane' && f "w1 joined as a worker" || p "w1 joined as a worker"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Work out the join parameters without a new token

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

A new worker will join this cluster with a bootstrap token that the security team hands out separately. Prepare the other two parts of its `kubeadm join` command. Write the API server endpoint the join must target, as `host:port` exactly as the cluster publishes it for joining nodes, to `/tmp/cka/ar-join-endpoint.txt`. Write the value for `--discovery-token-ca-cert-hash`, including its `sha256:` prefix, to `/tmp/cka/ar-join-hash.txt`. Do not create or delete any bootstrap tokens.

<details>
<summary>💡 Hints</summary>

- Joining nodes find the cluster through the cluster-info ConfigMap in the kube-public namespace.
- The hash is the SHA-256 of the cluster CA's public key. The CA certificate is /etc/kubernetes/pki/ca.crt on the control plane node.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n kube-public get cm cluster-info -o jsonpath='{.data.kubeconfig}' | awk '/server:/ {print $2}' | sed 's#^https://##' > /tmp/cka/ar-join-endpoint.txt
docker exec cka-control-plane sh -c "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'" | sed 's/^/sha256:/' > /tmp/cka/ar-join-hash.txt
cat /tmp/cka/ar-join-endpoint.txt /tmp/cka/ar-join-hash.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answers folder if it does not exist yet.
- `get cm cluster-info` — Reads the small kubeconfig that joining nodes fetch from `cluster-info`. `awk` prints the URL after `server:` and `sed` strips `https://`, leaving `host:port`. sed uses `#` as its separator so the slashes need no escaping.
- `openssl x509 -pubkey` — Runs the hash pipeline from the kubeadm docs inside the node, where `ca.crt` lives. The final `sed` runs on your workstation and puts `sha256:` in front, the form the join flag expects.
- `cat /tmp/cka/ar-join-endpoint.txt` — Check both answers: one `host:port`, and `sha256:` followed by 64 hex characters.

**Notes:** `kubeadm token create --print-join-command` would print both values at once, but it also creates a token, and the task forbids that. Anyone can read `cluster-info`, even without credentials. A joining node downloads it and checks its signature with the bootstrap token. Then it checks the CA inside against the hash you gave it. That is what stops a node from joining a fake cluster. The openssl command comes from the kubeadm join reference page: search the docs for *discovery-token-ca-cert-hash*.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

want_ep=$(kubectl -n kube-public get cm cluster-info -o jsonpath='{.data.kubeconfig}' 2>/dev/null | awk '/server:/ {print $2}' | sed 's#^https://##')
want_hash="sha256:$(docker exec cka-control-plane sh -c "openssl x509 -pubkey -noout -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform der | openssl dgst -sha256 -hex" 2>/dev/null | sed 's/^.* //')"
got_ep=$(tr -d '[:space:]' 2>/dev/null < /tmp/cka/ar-join-endpoint.txt | sed 's#^https://##')
got_hash=$(tr -d '[:space:]' 2>/dev/null < /tmp/cka/ar-join-hash.txt)

[ -n "$want_ep" ] && [ "$got_ep" = "$want_ep" ] && p "endpoint is $want_ep" || f "API server endpoint in /tmp/cka/ar-join-endpoint.txt"
[ "$want_hash" != "sha256:" ] && [ "$got_hash" = "$want_hash" ] && p "CA cert hash matches the cluster CA" || f "discovery-token-ca-cert-hash in /tmp/cka/ar-join-hash.txt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
