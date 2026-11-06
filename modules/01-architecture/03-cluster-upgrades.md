# Upgrading clusters and draining nodes

> **Module 1** · Lesson 1.3 · 40 minutes

Upgrade a kubeadm cluster one minor version at a time: first the control plane with kubeadm upgrade apply, then every other node, drained, upgraded and put back to work.

## Learning Objectives

- You can say which versions may run side by side (the version skew rules) and why they decide the upgrade order.
- You can upgrade the first control plane with kubeadm upgrade plan and apply, then its kubelet and kubectl.
- You can drain, upgrade and uncordon nodes one at a time, and say what each drain flag is for.


An upgrade moves the cluster to a newer Kubernetes version, for example from 1.36 to 1.37. With kubeadm it is a fixed list of about fifteen commands. The exam punishes small slips in that list: a package not pinned to a version, a kubelet never restarted, a node left cordoned.

This lesson gives you the list and the reason for each step. Then you practice the part kind can do for real: draining a node and putting it back. It belongs to the exam topic **Manage the lifecycle of Kubernetes clusters**.

**The upgrade order**

*Nothing may be newer than the API server, so the control plane always goes first. Then one node at a time.*

`First control plane` — upgrades the control plane (`kubeadm upgrade apply`) → `Other control planes` — only if you have more than one (`kubeadm upgrade node`) → `Each worker, one at a time` — drain, upgrade, uncordon (`kubeadm upgrade node`)

## Version skew decides the order

During an upgrade, parts of the cluster run different versions for a while. This is called **version skew**. The rules say how far apart the versions may be, measured against the API server:

| Component | Allowed version, compared with kube-apiserver |
| --- | --- |
| kube-apiserver (if you run several) | Within one minor version of each other. That is why you can upgrade control plane nodes one at a time. |
| kube-controller-manager, kube-scheduler, cloud-controller-manager | Never newer. At most one minor version older. |
| kubelet | Never newer. Up to three minor versions older. |
| kube-proxy | Never newer. Up to three minor versions older. |
| kubectl | One minor version older or newer. |

Example: the API server runs 1.37. A kubelet on 1.34 is allowed. A kubelet on 1.38 is not. Two rules follow from the table:

- **The control plane goes first**, because nothing may be newer than the API server.
- **One minor version per upgrade.** 1.36 to 1.37 works. 1.35 straight to 1.37 is refused. Skipping patch releases is fine, for example 1.36.2 straight to 1.37.1.

One more thing: the VERSION column of `kubectl get nodes` shows each node's *kubelet* version. It changes only after you upgrade and restart the kubelet on that node. `kubeadm upgrade apply` alone never changes it.

## Upgrade the first control plane

Run these on the first control plane node, as root. The example moves from v1.36 to v1.37.1. The same steps repeat on every node, so learn their shape once:

**The steps on each node**

`1. Switch the repository` — point apt at v1.37 → `2. New kubeadm` — unhold, install the exact version, hold → `3. kubeadm upgrade` — apply on the first control plane, node everywhere else → `4. New kubelet` — drain, install kubelet and kubectl, restart, uncordon

**First control plane node, as root**

```bash
# exam: ssh <control-plane>; sudo -i
# root may need: export KUBECONFIG=/etc/kubernetes/admin.conf

# 1. Point apt at the new minor version and find the exact package
sed -i 's#/v1.36/#/v1.37/#' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm | head -3          # e.g. 1.37.1-1.1

# 2. kubeadm first
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.37.1-1.1
apt-mark hold kubeadm
kubeadm version -o short                     # v1.37.1

# 3. Plan, then apply exactly the version you installed
kubeadm upgrade plan
kubeadm upgrade apply v1.37.1                # -y skips the confirmation prompt

# 4. kubelet and kubectl, with the node drained
kubectl drain <control-plane> --ignore-daemonsets
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.37.1-1.1 kubectl=1.37.1-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
kubectl uncordon <control-plane>
kubectl get nodes
```

<details>
<summary>Line-by-line explanation</summary>

- `sudo -i` — `sudo -i` opens a root shell, which is why none of the commands below start with `sudo`.
- `export KUBECONFIG=/etc/kubernetes/admin.conf` — root often has no kubeconfig of its own. Pointing `KUBECONFIG` at kubeadm's admin file lets `kubectl drain` and `uncordon` work from this shell.
- `sed -i 's#/v1.36/#/v1.37/#'` — Switches the repository URL from v1.36 to v1.37, since each repository serves one minor version. `#` is the `sed` separator here, so the slashes in the pattern need no escaping.
- `apt-get update` — Reloads the package list from the v1.37 repository.
- `apt-cache madison kubeadm` — Lists the v1.37 kubeadm packages so you can copy the exact version string, such as `1.37.1-1.1`.
- `apt-mark unhold kubeadm` — Releases the hold set at install time; apt refuses to change a held package.
- `apt-get install -y kubeadm=1.37.1-1.1` — Installs exactly that kubeadm. kubeadm always goes first, because it is the tool that upgrades everything else.
- `apt-mark hold kubeadm` — Holds it again at the new version.
- `kubeadm version -o short` — Confirms the kubeadm you are about to run is the new one.
- `kubeadm upgrade plan` — Checks that the cluster is healthy and lists the versions you can move to, with the exact `upgrade apply` command. It changes nothing.
- `kubeadm upgrade apply v1.37.1` — Upgrades the control plane on this node: new images, rewritten static Pod manifests, renewed certificates, new CoreDNS and kube-proxy. It asks for confirmation unless you add `-y`, and leaves the kubelet alone.
- `kubectl drain <control-plane>` — Moves workloads off this node before its kubelet restarts. Put the node's name in place of ``; `--ignore-daemonsets` lets the drain go ahead while DaemonSet Pods stay.
- `apt-mark unhold kubelet kubectl` — Unhold, install the exact version, hold again: the same three steps as for kubeadm, now for the kubelet and kubectl.
- `systemctl daemon-reload` — Makes systemd reread its unit files, in case the new kubelet package changed them.
- `systemctl restart kubelet` — Starts the new kubelet binary. Until you do this, the node keeps reporting the old version.
- `kubectl uncordon <control-plane>` — Makes the node schedulable again; drain left it cordoned.
- `kubectl get nodes` — The VERSION column shows each node's kubelet version. This node should now say `v1.37.1`.

</details>

`kubeadm upgrade apply` upgrades the control plane Pods, renews their certificates, and upgrades CoreDNS and kube-proxy. It does **not** touch the kubelet. That is step 4 in the block above.

## Other control planes and the workers

Every other node gets the same package steps. The one difference: run `kubeadm upgrade node` instead of `upgrade apply`.

**Every other node, one at a time**

```bash
# Additional control plane nodes: the same package steps, but instead of "upgrade apply":
kubeadm upgrade node

# Each worker. On the worker (ssh <worker>; sudo -i):
sed -i 's#/v1.36/#/v1.37/#' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-mark unhold kubeadm && apt-get install -y kubeadm=1.37.1-1.1 && apt-mark hold kubeadm
kubeadm upgrade node

# Wherever kubectl has admin credentials:
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data

# Back on the worker:
apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.37.1-1.1 kubectl=1.37.1-1.1 && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet

# And from the admin side again:
kubectl uncordon <worker>
kubectl get nodes
```

<details>
<summary>Line-by-line explanation</summary>

- `kubeadm upgrade node` — On every other control plane node this replaces `upgrade apply`. It reads the target version from the cluster and upgrades this node's static Pods to match, so it takes no version argument.
- `sed -i 's#/v1.36/#/v1.37/#'` — Every node has its own copy of the repository file, so each worker needs the switch to v1.37 too.
- `apt-mark unhold kubeadm &&` — Unhold, install, hold again, on one line. `&&` runs the next command only if the one before it succeeded.
- `kubeadm upgrade node` — On a worker there is no control plane to upgrade; this refreshes the kubelet's configuration for the new version.
- `kubectl drain <worker>` — Evicts the worker's Pods. `--delete-emptydir-data` allows evicting Pods with `emptyDir` volumes, whose scratch data is lost. Run it from a machine with an admin kubeconfig; workers usually have none.
- `apt-mark unhold kubelet kubectl &&` — The kubelet and kubectl packages, at the same version as kubeadm.
- `systemctl daemon-reload && systemctl restart kubelet` — Reloads the unit files and restarts the kubelet, so the worker now runs, and reports, the new version.
- `kubectl uncordon <worker>` — Returns the worker to service. Only then move on to the next node.
- `kubectl get nodes` — Every node should show the new version, and none `SchedulingDisabled`.

</details>

`kubeadm upgrade node` reads the target version from the cluster, so it takes no version number. Never run `upgrade apply` a second time on the other control planes. Upgrade the nodes one at a time, so the rest of the cluster keeps your apps running.

## cordon, drain, uncordon

Before you restart a node's kubelet, move its Pods somewhere else. Example: `cka-worker2` runs three `web` Pods. `kubectl drain cka-worker2` evicts them, and their Deployment starts new copies on the other workers. After the upgrade, `kubectl uncordon cka-worker2` opens the node again.

| Command or flag | What it does |
| --- | --- |
| `kubectl cordon ` | Marks the node unschedulable (`spec.unschedulable: true`), so no new Pods land on it. Pods already running there stay. |
| `kubectl drain ` | Cordons the node, then evicts every Pod on it and waits until they are gone. Eviction respects PodDisruptionBudgets (see [Probes and disruption budgets](/cka/workloads/probes-and-self-healing)). Static Pods are left alone. |
| `--ignore-daemonsets` | Needed on almost every node, because DaemonSet Pods run everywhere. They stay, because their controller would put them straight back. |
| `--delete-emptydir-data` | Allows evicting Pods that use `emptyDir` volumes. That scratch data is lost. |
| `--force` | Also deletes Pods that no controller manages. Nothing recreates them anywhere. |
| `--timeout`, `--grace-period` | `--timeout` limits how long drain waits in total. `--grace-period` limits how long each Pod gets to shut down. Without a timeout, a blocked drain can retry forever. |
| `kubectl uncordon ` | Makes the node schedulable again. Evicted Pods do not move back on their own. |

> [!IMPORTANT] **What the grader reads after an upgrade**
> The grader reads `kubectl get nodes`: every kubelet at the target version, no node `SchedulingDisabled`. It also checks the control plane images. Three slips cost the most points: forgetting `systemctl restart kubelet`, so the node still shows the old version; forgetting `uncordon`; and installing a package without a version, so it lands on a newer patch than asked. Run drain and uncordon where kubectl has admin rights, not on the worker.

## 📝 Key Takeaways

- Upgrade one minor version at a time, control plane first: nothing may be newer than the API server.
- On each node: new kubeadm package, then `kubeadm upgrade apply` on the first control plane or `kubeadm upgrade node` everywhere else. Then drain, upgrade the kubelet and kubectl, restart the kubelet and uncordon.
- For every package: unhold, install the exact version, hold again.
- `kubectl get nodes` shows the kubelet version. It changes only after `systemctl restart kubelet`.
- drain is cordon plus evict. You almost always need `--ignore-daemonsets`; add `--delete-emptydir-data` and `--force` only when losing that data or those Pods is allowed.

**📖 Official documentation:**

- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) *(search: "kubeadm upgrade")*
- [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/) *(search: "version skew policy")*
- [Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) *(search: "drain node")*
- [Changing The Kubernetes Package Repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/) *(search: "change package repository")*

---

### 🎯 Task: Upgrade a kubeadm cluster by one minor version

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 8% |
| **Time** | 20 min |

**Question:**

The cluster has control plane node `cp1` and worker `w1`, both on Kubernetes v1.36 and installed from pkgs.k8s.io. Upgrade the control plane components, kubelets and kubectl on both nodes to the newest v1.37 patch release available. Upgrade one node at a time, drain each node before upgrading its kubelet, and leave both nodes schedulable. You work from `cp1`; `ssh w1` reaches the worker.

<details>
<summary>💡 Hints</summary>

- Each package repository URL serves one minor version. Change it on both nodes first.
- On cp1: kubeadm package, upgrade plan, upgrade apply, then kubelet and kubectl. On w1: kubeadm package, upgrade node, then kubelet and kubectl.

</details>

<details>
<summary>✅ Solution</summary>

```bash
# ---- cp1 (control plane) ----
sudo sed -i 's#/v1.36/#/v1.37/#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
VER=$(apt-cache madison kubeadm | awk '{print $3}' | grep '^1.37' | sort -V | tail -1)
echo "target package version: $VER"
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm="$VER"
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply -y "v$(echo "$VER" | cut -d- -f1)"
kubectl drain cp1 --ignore-daemonsets --timeout=300s
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet="$VER" kubectl="$VER"
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon cp1

# ---- w1 (worker) ----
ssh w1 "sudo sed -i 's#/v1.36/#/v1.37/#' /etc/apt/sources.list.d/kubernetes.list && sudo apt-get update && sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=$VER && sudo apt-mark hold kubeadm && sudo kubeadm upgrade node" </dev/null
kubectl drain w1 --ignore-daemonsets --delete-emptydir-data --timeout=300s
ssh w1 "sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=$VER kubectl=$VER && sudo apt-mark hold kubelet kubectl && sudo systemctl daemon-reload && sudo systemctl restart kubelet" </dev/null
kubectl uncordon w1
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes
```

**Explanation:**

- `sudo sed -i 's#/v1.36/#/v1.37/#'` — Points cp1's package repository at v1.37; `apt-get update` on the next line reads it.
- `VER=$(apt-cache madison kubeadm` — Finds the newest v1.37 package: `awk` takes the version column, `grep` keeps lines starting with 1.37, `sort -V` sorts them as version numbers and `tail -1` keeps the highest.
- `target package version` — Prints the chosen version, for example `1.37.1-1.1`, so you see what is about to be installed.
- `sudo apt-mark unhold kubeadm` — Unhold, install `$VER`, hold again: kubeadm is upgraded first.
- `sudo kubeadm upgrade plan` — Health check and the list of versions you can upgrade to. Read it before you apply.
- `sudo kubeadm upgrade apply -y` — Upgrades the control plane without a prompt (`-y`). `cut -d- -f1` turns the package version `1.37.1-1.1` into `1.37.1`, and the `v` in front gives kubeadm the form it expects.
- `kubectl drain cp1` — Evicts workloads from cp1 before its kubelet restarts. `--timeout=300s` makes drain give up instead of waiting forever.
- `sudo apt-mark unhold kubelet kubectl` — Unhold, install, hold again for the kubelet and kubectl, at the same `$VER`.
- `sudo systemctl daemon-reload` — Reloads unit files; the next line restarts the kubelet. Without that restart, cp1 keeps reporting v1.36.
- `kubectl uncordon cp1` — Makes cp1 schedulable again; the task wants both nodes schedulable at the end.
- `sudo kubeadm upgrade node` — On `w1`, in one ssh call: switch the repository, upgrade the kubeadm package and run `kubeadm upgrade node`. Your shell on cp1 fills in `$VER` before the command is sent.
- `kubectl drain w1` — Empties the worker, run from cp1 where kubectl has admin credentials. `--delete-emptydir-data` allows evicting Pods that use `emptyDir` volumes.
- `ssh w1 "sudo apt-mark unhold kubelet` — Back on `w1`: the kubelet and kubectl at the same version, then the kubelet restart. `</dev/null` gives ssh empty input, so it cannot swallow lines you paste after it.
- `kubectl uncordon w1` — Returns `w1` to service.
- `kubectl wait --for=condition=Ready nodes --all` — Waits until both nodes are Ready again.
- `kubectl get nodes` — Both nodes should show v1.37 in the VERSION column, and neither `SchedulingDisabled`.

**Notes:** On the exam the question usually names the exact target version. Install that one, not the newest. Read the output of `kubeadm upgrade plan`: it prints the exact `kubeadm upgrade apply` command to run. If `apt-get install` says it cannot change held packages, you skipped `apt-mark unhold`. If a node still shows the old version, its kubelet was not restarted. On the worker this follows the order of the kubeadm upgrade page: kubeadm, `upgrade node`, drain, kubelet, uncordon. Draining first is also fine.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

for n in cp1 w1; do
  case "$(kubectl get node $n -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)" in v1.37.*) p "$n kubelet is v1.37" ;; *) f "$n kubelet is v1.37" ;; esac
  [ "$(kubectl get node $n -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ] && p "$n is Ready" || f "$n is Ready"
  [ "$(kubectl get node $n -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ] && p "$n is schedulable" || f "$n is schedulable"
done
for c in kube-apiserver kube-controller-manager kube-scheduler; do
  case "$(kubectl -n kube-system get pod -l component=$c -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)" in *:v1.37.*) p "$c runs v1.37" ;; *) f "$c runs v1.37" ;; esac
done
case "$(kubectl -n kube-system get ds kube-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)" in *:v1.37.*) p "kube-proxy runs v1.37" ;; *) f "kube-proxy runs v1.37" ;; esac

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Drain a node for maintenance

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Node `cka-worker2` is going down for maintenance. Make sure no new Pods can be scheduled onto it, and empty it of every Pod except those managed by DaemonSets. The Pods of Deployment `web` in namespace `ar-drain` keep scratch data in an `emptyDir` volume; that data may be discarded. Any Pod on the node that no controller manages is a leftover test Pod and may be deleted. Leave the node unschedulable, since the maintenance team will return it to service themselves.

<details>
<summary>💡 Hints</summary>

- kubectl drain cordons the node and evicts its Pods in one step.
- drain stops when it finds DaemonSet Pods, Pods with emptyDir volumes or Pods without a controller. You must tell it how to treat each group. A Pod without a controller cannot be moved, only deleted.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=cka-worker2
kubectl drain cka-worker2 --ignore-daemonsets --delete-emptydir-data --force --timeout=180s
kubectl -n ar-drain rollout status deploy/web --timeout=120s
kubectl -n ar-drain get pods -o wide
```

**Explanation:**

- `--field-selector spec.nodeName=cka-worker2` — Lists every Pod on `cka-worker2` in all namespaces, so you know what the drain will have to deal with.
- `kubectl drain cka-worker2` — Cordons the node, then evicts its Pods. `--ignore-daemonsets` leaves DaemonSet Pods in place, `--delete-emptydir-data` accepts losing the scratch data, and `--force` deletes Pods that no controller manages.
- `rollout status deploy/web` — Waits until the three `web` replicas are running again, now on other nodes.
- `get pods -o wide` — The NODE column confirms none of them is on `cka-worker2`. The node stays cordoned, as the task asks.

**Notes:** Run drain once without flags to see why it stops. It names three groups of Pods. DaemonSet Pods: `--ignore-daemonsets` leaves them in place. Pods with local storage: `--delete-emptydir-data` accepts losing that data. Pods *not managed by a controller*: nothing would recreate them, so only `--force` empties the node, and it deletes them for good. The question allows that here; on a real cluster, ask their owner first. If the node has no such Pods, `--force` changes nothing. This task's cleanup uncordons the node; run it before the next lesson.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ar-drain

[ "$(kubectl get node cka-worker2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" = "true" ] && p "cka-worker2 is cordoned" || f "cka-worker2 is cordoned"
[ -z "$(kubectl -n $ns get pods --field-selector spec.nodeName=cka-worker2 --no-headers 2>/dev/null)" ] && p "no web Pods left on cka-worker2" || f "no web Pods left on cka-worker2"
[ "$(kubectl -n $ns get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "web has 3 available replicas on other nodes" || f "web has 3 available replicas on other nodes"
left=$(kubectl get pods -A --field-selector spec.nodeName=cka-worker2 -o 'custom-columns=OWNER:.metadata.ownerReferences[0].kind' --no-headers 2>/dev/null | grep -v -x -e DaemonSet -e Node | wc -l | tr -d ' ')
[ "$left" = "0" ] && p "only DaemonSet and static Pods remain on cka-worker2" || f "only DaemonSet and static Pods remain on cka-worker2 ($left others)"
kubectl -n kube-system get pods -l k8s-app=calico-node --field-selector spec.nodeName=cka-worker2 --no-headers 2>/dev/null | grep -q Running && p "DaemonSet Pods still run on cka-worker2" || f "DaemonSet Pods still run on cka-worker2"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
