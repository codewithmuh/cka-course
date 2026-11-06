# PersistentVolumes and PersistentVolumeClaims

> **Module 4** · Lesson 4.2 · 45 minutes

PersistentVolumes and claims: the fields that decide whether a claim binds, access modes, reclaim policies, and how to reuse a Released volume.

## Learning Objectives

- You can write a hostPath PersistentVolume and a matching claim, mount the claim in a Pod and check that they are bound.
- You can read a Pending claim and create exactly the PersistentVolume it needs.
- You can explain Retain and Delete, spot a Released volume and make it usable again without losing its data.


Your database needs a disk that survives restarts, and even the deletion of its Pod. A **PersistentVolume** is that disk, and a **PersistentVolumeClaim** is how a Pod asks for it. This lesson shows both, and the few fields that must match between them.

The exam asks about them in three ways, and the three tasks at the end practice each one:

- Create a PV, a claim and a Pod that uses the claim.
- Make a waiting (`Pending`) claim bind.
- Reuse a volume after its claim was deleted.

## PV, PVC and StorageClass: three names, three jobs

These three names look alike and are easy to mix up:

| Name | What it is | Who makes it | Example |
| --- | --- | --- | --- |
| **PersistentVolume** (PV) | A piece of real storage: a disk or a folder. Cluster-wide, no namespace. | An admin by hand, or a StorageClass automatically | `st-data-pv`: 1Gi in `/opt/st-data` |
| **PersistentVolumeClaim** (PVC) | A request for storage: a size and an access mode. Lives in a namespace. | The app team, next to the app | `data-claim`: "I need 1Gi I can write to" |
| **StorageClass** | A recipe that creates PVs when claims ask for them | An admin, once | `standard` on the lab ([next lesson](/cka/storage/storage-classes-dynamic-provisioning)) |

**How a Pod gets persistent storage**

*The Pod names the claim, and the claim is bound to one PV. The Pod never names the PV.*

`Pod` — mounts the claim by name (`claimName: data-claim`) → `PersistentVolumeClaim` — the request: 1Gi, read-write (`data-claim`) → `PersistentVolume` — the real storage (`st-data-pv`)

## The PersistentVolume

A **PersistentVolume** (PV) describes one piece of storage: its size, how it may be used, and where it lives. An admin can create PVs by hand, which is called *static provisioning*. Or a StorageClass creates them on demand, which is *dynamic provisioning* (next lesson).

**A static PersistentVolume backed by a folder on the node**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: st-data-pv
  labels:
    tier: data                  # lets a claim select this PV by label
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: st-manual
  hostPath:
    path: /opt/st-data
    type: DirectoryOrCreate
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: PersistentVolume` — A PV describes one piece of storage. It is cluster-scoped, so `metadata` has no namespace: a claim in any namespace can bind to it.
- `storage: 1Gi` — The PV's size. A claim binds only to a PV at least as big as its request.
- `volumeMode: Filesystem` — The default: the Pod gets a normal folder. You can leave this line out, and a claim's default matches it.
- `- ReadWriteOnce` — The access modes this PV offers. `ReadWriteOnce` (RWO) means read-write from one node at a time; a claim can only ask for modes listed here.
- `persistentVolumeReclaimPolicy: Retain` — What happens when the claim is deleted: `Retain` keeps the PV and its data for an administrator to deal with. In a StorageClass the same setting is called just `reclaimPolicy`.
- `storageClassName: st-manual` — On a static PV this is only a matching label: no StorageClass object called `st-manual` has to exist. The claim must name exactly the same string.
- `hostPath:` — Where the data really lives: a directory on whichever node the Pod lands on. Nothing pins the Pod to one node, which is the weakness of hostPath PVs on a multi-node cluster.

</details>

The fields to know:

- `capacity.storage`: the size. Claims are compared against it.
- `storageClassName`: on a PV you make by hand, this is just a name to match. No StorageClass with that name has to exist, but the claim must use the same string.
- The source, here `hostPath`: where the data really is. Other sources are `local`, `nfs` and `csi`.

A `local` PV is the stricter cousin of hostPath. It names the one node that has the disk, in `nodeAffinity`. So every Pod that uses it runs on that node.

## The PersistentVolumeClaim

A **PersistentVolumeClaim** (PVC) is a request for storage: a size and an access mode. The app team writes it in the app's namespace. Kubernetes then binds the claim to one PV.

Why the extra step? The Pod names the claim, never the PV. So the same Pod YAML works with a folder on a lab node or a disk in a cloud. Only the PV changes.

**A claim that picks the PV above by its label**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
  namespace: st-pv
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  storageClassName: st-manual
  resources:
    requests:
      storage: 1Gi
  selector:
    matchLabels:
      tier: data
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: PersistentVolumeClaim` — A claim is a request for storage, and unlike a PV it lives in a namespace. Kubernetes binds it to one PV that passes every check below.
- `- ReadWriteOnce` — The modes the claim needs. Every mode listed here must also appear in the PV's `accessModes`.
- `storageClassName: st-manual` — Must be the same string as on the PV. Leave this line out and the lab fills in its default class, `standard`, so the claim no longer matches your PV.
- `storage: 1Gi` — The smallest size the claim accepts. A bigger PV also fits, and the claim then reports the PV's full size.
- `selector:` — Narrows the choice to PVs whose labels match, here `tier=data`, which `st-data-pv` above carries. A claim with a selector is never given a dynamically provisioned volume.

</details>

**A Pod that mounts the claim**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: st-pv
spec:
  containers:
    - name: web
      image: nginx:1.27
      volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-claim
```

<details>
<summary>Line-by-line explanation</summary>

- `mountPath: /usr/share/nginx/html` — Whatever is stored on the PV appears as nginx's web pages. The container only knows a path; it never sees which PV is behind it.
- `persistentVolumeClaim:` — The Pod names the **claim**, never the PV. The claim must be in the Pod's namespace, and the Pod stays Pending until the claim is Bound.

</details>

## Access modes

An access mode says how many nodes may mount the volume at once, and whether they may write to it.

| Mode | Short | Meaning |
| --- | --- | --- |
| ReadWriteOnce | RWO | Read-write from one node. Several Pods on that same node may share it. |
| ReadOnlyMany | ROX | Read-only from many nodes. |
| ReadWriteMany | RWX | Read-write from many nodes. Needs shared storage, such as NFS or a cloud file share. |
| ReadWriteOncePod | RWOP | Read-write from exactly one Pod in the whole cluster. Only for CSI volumes, and never mixed with another mode. |

- A PV lists every mode it supports. A claim lists the modes it needs, and each one must be on the PV.
- Modes are a matching rule, not a lock. A hostPath PV may say `ReadWriteMany`, yet nothing makes two nodes see the same folder.
- On the exam, translate the words: "one node" means `ReadWriteOnce`, and "many nodes" means `ReadWriteMany`.

## Reclaim policies

The reclaim policy, `persistentVolumeReclaimPolicy`, decides what happens to a PV when its claim is deleted:

| Policy | What happens when the claim is deleted | Use it when |
| --- | --- | --- |
| **Retain** | The PV and its data stay. The PV becomes `Released`, and an admin decides what to do with it. | The data matters |
| **Delete** | The PV is deleted, and the storage behind it too. | The data can be thrown away |

- A PV you create by hand gets `Retain` if you leave the field out. A PV made by a StorageClass gets the class's policy, as the [next lesson](/cka/storage/storage-classes-dynamic-provisioning) shows.
- You can change the policy on a live PV. To keep the data if the claim is deleted: `kubectl patch pv  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`.

## How a claim finds its PV

Kubernetes binds a claim to a PV only when every check below passes. If one fails, the claim stays `Pending`.

- **Size:** the PV's `capacity.storage` is at least the claim's `requests.storage`. Kubernetes picks the smallest PV that fits. So a 1Gi claim may get a 5Gi PV, and then it shows 5Gi.
- **Access modes:** every mode the claim asks for is on the PV.
- **Class:** `storageClassName` is the same string on both. A claim that leaves it out gets the default class filled in. On this lab that is `standard`, which makes a brand-new volume instead of using yours. A claim with `storageClassName: ""` binds only to PVs that have no class.
- **Selector:** if the claim has one, the PV's labels must match it. A claim with a selector never gets a new volume from a StorageClass.
- **Free:** the PV is `Available`, not bound to another claim. A claim can also ask for one PV by name, with `spec.volumeName`.

Once bound, the pair stays bound until the claim is deleted. When a claim stays `Pending`, run `kubectl describe pvc `. Its events say why. The fix is almost always a PV with the right class, size and access modes.

> [!TIP] **Delete the Pod before the claim**
> A claim that a Pod still uses cannot be deleted. It waits in `Terminating` until the last Pod using it is gone. The `kubernetes.io/pvc-protection` finalizer does this.

## PV phases and reusing a Released volume

The STATUS column of `kubectl get pv` shows a PV's phase:

| Phase | Meaning | What to do |
| --- | --- | --- |
| Available | Free. No claim is bound to it. | Nothing, or create a matching claim. |
| Bound | Bound to one claim, named in `spec.claimRef`. | Mount the claim from a Pod. |
| Released | The claim was deleted. With Retain, the data and the old `claimRef` are still there. | Clear `claimRef` to reuse it, or delete the PV. |
| Failed | Kubernetes could not delete the storage automatically. | Read the events, then fix or delete it by hand. |

**The life of a Retain PV**

*With `Delete` instead, the PV and its storage are removed when the claim goes, so there is no Released step.*

`Available` — free, waiting for a claim → `Bound` — in use by one claim → `Released` — claim deleted, data kept → `Available again` — after you clear claimRef (`claimRef: null`)

A Released PV still remembers its old claim in `spec.claimRef`, so no new claim can bind to it. Remove that reference and the PV is free again. The data on it is not touched.

**Bring a Released Retain volume back and let a waiting claim bind**

```bash
kubectl get pv st-keep-pv                      # STATUS Released, CLAIM still shows the old claim
kubectl get pv st-keep-pv -o jsonpath='{.spec.claimRef}'

# Drop the reference to the deleted claim. The data on the volume is untouched.
kubectl patch pv st-keep-pv -p '{"spec":{"claimRef":null}}'
# Interactive alternative: kubectl edit pv st-keep-pv and delete the whole claimRef: block.

kubectl get pv st-keep-pv                      # Available
# A Pending claim that matches is picked up on the controller's next pass (within ~15s).
kubectl -n st-pv wait --for=jsonpath='{.status.phase}'=Bound pvc/keep-claim-v2 --timeout=90s
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get pv st-keep-pv` — PVs have no namespace, so there is no `-n`. STATUS `Released` and the old name under CLAIM tell you the volume still remembers its deleted claim.
- `-o jsonpath='{.spec.claimRef}'` — Prints only the `claimRef`: the name, namespace and uid of the claim the PV is still reserved for. While it is there, no other claim can bind.
- `kubectl patch pv st-keep-pv` — Changes one field without opening an editor. Setting `claimRef` to `null` removes it; the single quotes keep the shell away from the JSON. The files on the volume are not touched.
- `kubectl get pv st-keep-pv` — Now `Available` again: free for any claim that matches its class, size and access modes.
- `wait --for=jsonpath=` — Waits until the claim's `status.phase` reads `Bound`, for up to 90 seconds. The controller retries waiting claims about every 15 seconds, so give it a moment.

</details>

> [!IMPORTANT] **What the grader reads**
> `kubectl get pv,pvc -A` shows most of what the grader reads. That is the PV's size, access modes, reclaim policy and class, and the claim's STATUS and VOLUME. It also reads the Pod's `claimName`. A claim that is still `Pending` scores zero, however good your YAML is. Use the exact size the question gives. Spell the class name the same on both sides. If the question says Retain, check the RECLAIM POLICY column.

## 📝 Key Takeaways

- A PV is the storage. A PVC is the request for it. A StorageClass creates PVs automatically (next lesson).
- PVs have no namespace, and claims do. A Pod mounts the claim, never the PV.
- A claim binds only when size, access modes, class name and selector all match. If it stays Pending, read `kubectl describe pvc`.
- Leave out `storageClassName` and the claim gets the default class, not your PV.
- Retain keeps the data when the claim is deleted, and the PV becomes Released. Clear `spec.claimRef` to reuse it.

**📖 Official documentation:**

- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) *(search: "persistent volumes")*
- [Volumes: hostPath and local](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath) *(search: "hostpath volume")*
- [Configure a Pod to Use a PersistentVolume for Storage](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/) *(search: "configure persistent volume storage")*

---

### 🎯 Task: A hostPath PV, a claim and a Pod that mounts it

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 5% |
| **Time** | 8 min |

**Question:**

Create a PersistentVolume named `st-data-pv` with 1Gi of capacity, access mode `ReadWriteOnce`, reclaim policy `Retain` and storage class name `st-manual`, backed by the host directory `/opt/st-data` (create it if it does not exist). In namespace `st-pv` create a PersistentVolumeClaim named `data-claim` that requests 1Gi from that volume, and a Pod named `data-pod` using image `nginx:1.27` that mounts the claim at `/usr/share/nginx/html`. The claim must be `Bound` to `st-data-pv` and the Pod must be running.

<details>
<summary>💡 Hints</summary>

- The docs page "Configure a Pod to Use a PersistentVolume for Storage" has a hostPath PV, a claim and a Pod. Copy them and change the values the question names.
- The claim needs the same `storageClassName` and access mode as the PV, or it stays `Pending`.
- The Pod names the claim, not the PV: `volumes[].persistentVolumeClaim.claimName`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/st-data.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: st-data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: st-manual
  hostPath:
    path: /opt/st-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
  namespace: st-pv
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: st-manual
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: st-pv
spec:
  containers:
    - name: web
      image: nginx:1.27
      volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data-claim
YAML
kubectl apply -f /tmp/cka/st-data.yaml
kubectl -n st-pv wait --for=jsonpath='{.status.phase}'=Bound pvc/data-claim --timeout=60s
kubectl -n st-pv wait --for=condition=Ready pod/data-pod --timeout=120s
kubectl get pv st-data-pv
kubectl -n st-pv get pvc data-claim
```

**Explanation:**

- `cat > /tmp/cka/st-data.yaml` — All three objects go into one file, separated by `---`, so a single apply creates them.
- `kind: PersistentVolume` — The PV, with the four values the question names: 1Gi, ReadWriteOnce, Retain and the class `st-manual`. No namespace, because PVs are cluster-wide.
- `type: DirectoryOrCreate` — Covers "create it if it does not exist". The directory appears on whichever node `data-pod` ends up running on.
- `kind: PersistentVolumeClaim` — The claim lives in `st-pv`. Its access mode, class and size are chosen to match the PV, which is all binding needs.
- `storageClassName: st-manual` — The line people forget. Without it the claim gets the default class `standard` and a brand-new volume, and `st-data-pv` stays Available.
- `claimName: data-claim` — The Pod's volume points at the claim by name; the container mounts that volume at nginx's web root.
- `wait --for=jsonpath='{.status.phase}'=Bound pvc/data-claim` — Waits until the claim is Bound. A matching static PV is already Available, so this takes a second or two.
- `wait --for=condition=Ready pod/data-pod` — Then waits for nginx to be running with the volume mounted.
- `kubectl get pv st-data-pv` — Should show STATUS `Bound` and CLAIM `st-pv/data-claim`.
- `get pvc data-claim` — The claim's view of the same pair: STATUS `Bound` and VOLUME `st-data-pv`.

**Notes:** Three objects, one file, one `kubectl apply`. No kubectl command creates a PV or a PVC, so the YAML comes from the docs or from memory. The claim binds within a second or two, because the PV is static and already `Available`. If it stays `Pending`, `kubectl -n st-pv describe pvc data-claim` says which check failed. Note that `kubectl get pvc` shows the size of the bound PV, not the size you asked for.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-pv
pv="kubectl get pv st-data-pv -o jsonpath"
c="kubectl -n $ns get pvc data-claim -o jsonpath"
g="kubectl -n $ns get pod data-pod -o jsonpath"

kubectl get pv st-data-pv >/dev/null 2>&1 && p "PV st-data-pv exists" || f "PV st-data-pv exists"
[ "$($pv='{.spec.capacity.storage}' 2>/dev/null)" = "1Gi" ] && p "PV capacity 1Gi" || f "PV capacity 1Gi"
$pv='{.spec.accessModes[*]}' 2>/dev/null | grep -qw ReadWriteOnce && p "PV access mode ReadWriteOnce" || f "PV access mode ReadWriteOnce"
[ "$($pv='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "PV reclaim policy Retain" || f "PV reclaim policy Retain"
[ "$($pv='{.spec.storageClassName}' 2>/dev/null)" = "st-manual" ] && p "PV storageClassName st-manual" || f "PV storageClassName st-manual"
[ "$($pv='{.spec.hostPath.path}' 2>/dev/null)" = "/opt/st-data" ] && p "PV hostPath /opt/st-data" || f "PV hostPath /opt/st-data"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PVC data-claim is Bound" || f "PVC data-claim is Bound"
[ "$($c='{.spec.volumeName}' 2>/dev/null)" = "st-data-pv" ] && p "PVC is bound to st-data-pv" || f "PVC is bound to st-data-pv"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod data-pod is Running" || f "pod data-pod is Running"
vol="$($g='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="data-claim")].name}' 2>/dev/null)"
[ -n "$vol" ] && p "pod has a volume for data-claim" || f "pod has a volume for data-claim"
[ -n "$vol" ] && [ "$($g="{.spec.containers[0].volumeMounts[?(@.name==\"$vol\")].mountPath}" 2>/dev/null)" = "/usr/share/nginx/html" ] && p "claim mounted at /usr/share/nginx/html" || f "claim mounted at /usr/share/nginx/html"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Make a Pending claim bind

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

The PersistentVolumeClaim `logs-claim` in namespace `st-pv` has been `Pending` since it was created. Create a PersistentVolume named `st-logs-pv` that satisfies it, backed by the host directory `/opt/st-logs-pv` and with reclaim policy `Retain`. Do not modify or recreate the claim. When you are done the claim must be `Bound` to `st-logs-pv`.

<details>
<summary>💡 Hints</summary>

- Read the claim first: `kubectl -n st-pv get pvc logs-claim -o yaml`. Match its size, access mode, class and selector.
- A selector on the claim means the PV needs the matching label.
- After you create the PV, give it a few seconds. Watch with `kubectl get pvc -n st-pv -w`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n st-pv get pvc logs-claim -o yaml
mkdir -p /tmp/cka
cat > /tmp/cka/st-logs-pv.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: st-logs-pv
  labels:
    tier: logs
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: st-logs
  hostPath:
    path: /opt/st-logs-pv
    type: DirectoryOrCreate
YAML
kubectl apply -f /tmp/cka/st-logs-pv.yaml
kubectl -n st-pv wait --for=jsonpath='{.status.phase}'=Bound pvc/logs-claim --timeout=90s
kubectl -n st-pv get pvc logs-claim
```

**Explanation:**

- `get pvc logs-claim -o yaml` — Step one is always reading the claim. Its `spec` lists everything the PV must match: size, access modes, class and the label selector.
- `tier: logs` — The claim has a selector for `tier=logs`, so the PV must carry that label or it is never considered.
- `storage: 2Gi` — At least the 2Gi the claim requests. More would also bind; less never does.
- `- ReadWriteMany` — The claim asks for ReadWriteMany, so the PV must offer it. A hostPath PV can declare any mode, because Kubernetes uses modes only for matching.
- `persistentVolumeReclaimPolicy: Retain` — Retain, as the question asks. It plays no part in binding; it only decides what happens after the claim is deleted.
- `storageClassName: st-logs` — The claim's class, spelled the same. No StorageClass by that name exists, which is fine for a static PV.
- `wait --for=jsonpath` — Gives the controller up to 90 seconds. A claim that was already waiting is re-checked on a timer, about every 15 seconds, so binding is not instant.
- `get pvc logs-claim` — Confirms STATUS `Bound` and VOLUME `st-logs-pv`, without having changed the claim.

**Notes:** Everything you need is in the claim: 2Gi, `ReadWriteMany`, class `st-logs` and selector `tier=logs`. Miss one and the claim stays `Pending`, and only `kubectl describe pvc` tells you why. A bigger PV (say 5Gi) also binds; a smaller one never does. A claim with a selector never gets a volume from a StorageClass, so a static PV is the only way. Binding can take up to 15 seconds, because Kubernetes re-checks waiting claims on a timer.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-pv
pv="kubectl get pv st-logs-pv -o jsonpath"
c="kubectl -n $ns get pvc logs-claim -o jsonpath"

kubectl get pv st-logs-pv >/dev/null 2>&1 && p "PV st-logs-pv exists" || f "PV st-logs-pv exists"
[ "$($pv='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "PV reclaim policy Retain" || f "PV reclaim policy Retain"
[ "$($pv='{.spec.hostPath.path}' 2>/dev/null)" = "/opt/st-logs-pv" ] && p "PV hostPath /opt/st-logs-pv" || f "PV hostPath /opt/st-logs-pv"
[ "$($pv='{.spec.storageClassName}' 2>/dev/null)" = "st-logs" ] && p "PV storageClassName st-logs" || f "PV storageClassName st-logs"
$pv='{.spec.accessModes[*]}' 2>/dev/null | grep -qw ReadWriteMany && p "PV offers ReadWriteMany" || f "PV offers ReadWriteMany"
[ "$($pv='{.metadata.labels.tier}' 2>/dev/null)" = "logs" ] && p "PV labeled tier=logs" || f "PV labeled tier=logs"
[ "$($pv='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PV is Bound" || f "PV is Bound"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PVC logs-claim is Bound" || f "PVC logs-claim is Bound"
[ "$($c='{.spec.volumeName}' 2>/dev/null)" = "st-logs-pv" ] && p "PVC bound to st-logs-pv" || f "PVC bound to st-logs-pv"
[ "$($c='{.spec.resources.requests.storage}' 2>/dev/null)" = "2Gi" ] && [ "$($c='{.spec.selector.matchLabels.tier}' 2>/dev/null)" = "logs" ] && p "claim left unchanged" || f "claim left unchanged"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Reuse a Released Retain volume

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

The PersistentVolume `st-keep-pv` belonged to a claim that has since been deleted. It still holds data that must be kept, and it is now in phase `Released`. A new claim `keep-claim-v2` in namespace `st-pv` is waiting for it. Make `st-keep-pv` bindable again so that `keep-claim-v2` binds to it. Do not delete or recreate the PersistentVolume, and keep its reclaim policy.

<details>
<summary>💡 Hints</summary>

- `kubectl get pv st-keep-pv -o yaml` shows that `spec.claimRef` still points at the deleted claim. That is what blocks binding.
- Remove the whole `claimRef` with `kubectl edit`, or with `kubectl patch pv st-keep-pv -p '{"spec":{"claimRef":null}}'`.
- Then watch `kubectl get pvc -n st-pv -w` until `keep-claim-v2` shows Bound.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get pv st-keep-pv
kubectl patch pv st-keep-pv -p '{"spec":{"claimRef":null}}'
kubectl -n st-pv wait --for=jsonpath='{.status.phase}'=Bound pvc/keep-claim-v2 --timeout=90s
kubectl get pv st-keep-pv
kubectl -n st-pv get pvc keep-claim-v2
```

**Explanation:**

- `kubectl get pv st-keep-pv` — Confirms the starting point: STATUS `Released`, with the deleted claim still shown under CLAIM.
- `kubectl patch pv` — Removes the stale `claimRef`, the only thing keeping the PV from binding. The reclaim policy and the data stay as they are.
- `wait --for=jsonpath` — Waits for the new claim to bind on the controller's next pass.
- `kubectl get pv st-keep-pv` — Now `Bound`, with `st-pv/keep-claim-v2` under CLAIM.
- `get pvc keep-claim-v2` — The claim's side of the same binding: Bound, with VOLUME `st-keep-pv`.

**Notes:** `Released` means the claim is gone, but `spec.claimRef` still names it. So Kubernetes will not give the volume to any other claim. Clear `claimRef` and the PV becomes `Available`. The waiting claim binds on the next check, usually within 15 seconds. The data in `/opt/st-keep` is untouched. Deleting and recreating the PV would also seem to work, but the question forbids it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-pv
pv="kubectl get pv st-keep-pv -o jsonpath"
c="kubectl -n $ns get pvc keep-claim-v2 -o jsonpath"

kubectl get pv st-keep-pv >/dev/null 2>&1 && p "PV st-keep-pv exists" || f "PV st-keep-pv exists"
pvts="$($pv='{.metadata.creationTimestamp}' 2>/dev/null)"
pvcts="$($c='{.metadata.creationTimestamp}' 2>/dev/null)"
[ -n "$pvts" ] && [ -n "$pvcts" ] && [[ "$pvts" < "$pvcts" ]] && p "PV was not recreated" || f "PV was not recreated"
[ "$($pv='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "reclaim policy still Retain" || f "reclaim policy still Retain"
[ "$($pv='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PV is Bound" || f "PV is Bound"
[ "$($pv='{.spec.claimRef.name}' 2>/dev/null)" = "keep-claim-v2" ] && p "PV claimRef names keep-claim-v2" || f "PV claimRef names keep-claim-v2"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PVC keep-claim-v2 is Bound" || f "PVC keep-claim-v2 is Bound"
[ "$($c='{.spec.volumeName}' 2>/dev/null)" = "st-keep-pv" ] && p "PVC bound to st-keep-pv" || f "PVC bound to st-keep-pv"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 4: Storage*
