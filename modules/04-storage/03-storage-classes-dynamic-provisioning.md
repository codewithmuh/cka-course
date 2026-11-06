# StorageClasses and dynamic provisioning

> **Module 4** · Lesson 4.3 · 35 minutes

How a StorageClass creates volumes for claims, what its fields do, how the default class works, and how a claim grows.

## Learning Objectives

- You can write a StorageClass with the right provisioner, reclaim policy and binding mode, and say when its PV will appear.
- You can change which class is the default, and say what happens to a claim that names no class.
- You can follow a dynamically created volume from the claim to the PV to the folder on the node.


In the last lesson you wrote each PV by hand. Now imagine teams that create twenty databases a week: writing twenty PVs is slow. A **StorageClass** does it for them. When a claim names the class, a program called a *provisioner* creates the storage and the PV automatically. This is called *dynamic provisioning*.

On the exam it shows up in three ways:

- Create a StorageClass with the settings the question gives.
- Create a claim and a Pod that use a class.
- Make a class the cluster's default.

Each takes about two minutes once you know a class's few fields and the one annotation that marks the default.

**Dynamic provisioning**

*You write only the claim (and the Pod). The provisioner named in the class creates the PV. On this lab the provisioner is `rancher.io/local-path`, which makes a folder on a node.*

`Claim (PVC)` — names a class (`storageClassName: fast-retain`) → `StorageClass` — the recipe: provisioner and rules (`fast-retain`) → `Provisioner` — creates the storage and a PV (`rancher.io/local-path`) → `New PV` — bound to the claim (`pvc-<uid>`)

## What a StorageClass looks like

**A class that keeps volumes and waits for a Pod before provisioning**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: false
parameters: {}        # provisioner-specific: type: gp3, fsType: ext4, ...
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: storage.k8s.io/v1` — StorageClasses live in the `storage.k8s.io` API group, so the group comes before `v1`. Like PVs, they have no namespace.
- `kind: StorageClass` — Notice there is no `spec:`. A StorageClass keeps its fields at the top level, beside `metadata`; nest them under `spec` and the API rejects the manifest.
- `provisioner: rancher.io/local-path` — The program that creates the real storage when a claim asks for this class. On the lab it is the local-path provisioner, which makes a directory on a node; in a cloud it would be a CSI driver.
- `reclaimPolicy: Retain` — Copied onto every PV this class creates, so deleting a claim leaves its volume and data behind as Released. Left out, it defaults to `Delete`.
- `volumeBindingMode: WaitForFirstConsumer` — Do not create the volume until a Pod that uses the claim is scheduled. The volume then lands on the Pod's node, and until then the claim shows Pending on purpose.
- `allowVolumeExpansion: false` — Claims of this class cannot grow later. Unlike the three lines above, this one can be changed on an existing class.
- `parameters: {}` — Options passed straight to the provisioner, different for every driver. `{}` is an empty map: no options.

</details>

| Field | Default | What it controls |
| --- | --- | --- |
| provisioner | required | The program that creates the volumes. On this lab: `rancher.io/local-path`. In a cloud: a CSI driver such as `ebs.csi.aws.com`. |
| parameters | none | Options for the provisioner, different for each one: disk type, speed, filesystem. |
| reclaimPolicy | Delete | Copied onto every PV the class creates: `Delete` or `Retain`. |
| volumeBindingMode | Immediate | When the volume is created: at once (`Immediate`), or when a Pod needs it (`WaitForFirstConsumer`). |
| allowVolumeExpansion | false | Whether claims of this class may grow later. |

You may also meet the provisioner `kubernetes.io/no-provisioner`. It creates nothing: such a class only groups PVs made by hand. CSI drivers themselves are covered in [CNI, CSI and CRI](/cka/architecture/extension-interfaces).

- There is no `kubectl create storageclass`. Copy the YAML from the docs, or start from `kubectl get sc standard -o yaml`.
- `provisioner`, `parameters`, `reclaimPolicy` and `volumeBindingMode` cannot be changed later. To fix one, delete the class and create it again. Existing PVs keep working, because they only store the class name.
- The default-class annotation and `allowVolumeExpansion` can be changed in place.

## Immediate or WaitForFirstConsumer

`volumeBindingMode` decides *when* the volume is created. That matters for storage tied to one place, such as a disk on one node or in one cloud zone.

- **Immediate** creates the volume as soon as the claim exists. But the scheduler has not picked a node for the Pod yet, so the volume may land where the Pod cannot run. Example: the disk is made in zone A, but the Pod can only run in zone B.
- **WaitForFirstConsumer** waits until a Pod that uses the claim is scheduled. The node is picked first, and the volume is created where the Pod is.

**WaitForFirstConsumer, step by step**

`Claim created` — Pending: no Pod uses it yet → `Pod created` — the scheduler picks a node → `Volume created` — on the Pod's node → `Bound` — claim Bound, Pod Running

The first step confuses many people. Until a Pod uses it, the claim shows `Pending` with the event *waiting for first consumer to be created before binding*. That is correct, not a fault. The lab's `standard` class works this way, like many cloud classes. So a claim alone never binds: create the Pod, and the claim binds too.

## The default class

The default class is the one a claim gets when it names no class. One annotation marks it:

- The annotation is `storageclass.kubernetes.io/is-default-class: "true"`. `kubectl get sc` then shows `(default)` after the class name.
- A claim without `storageClassName` gets the default class filled in when it is created.
- A claim with `storageClassName: ""` opts out. It binds only to PVs that have no class.
- Keep exactly one default. If two classes have the annotation, the newest one wins. So when you switch, also clear the old one.

Switching the default takes two patches, and nothing restarts:

**Switch the default class and confirm**

```bash
kubectl get sc
kubectl patch storageclass standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass st-bulk  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc                                   # exactly one "(default)"
kubectl get sc st-bulk -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get sc` — `sc` is short for `storageclasses`. The default class has `(default)` after its name.
- `kubectl patch storageclass standard` — Sets the default-class annotation on `standard` to `"false"`. Annotation values are always strings, which is why even `false` is in quotes inside the JSON.
- `kubectl patch storageclass st-bulk` — The same annotation set to `"true"` makes `st-bulk` the default. Clearing the old class first means there is never a moment with two defaults.
- `# exactly one` — Check before moving on: only `st-bulk` should show `(default)`. New claims that name no class now go to it.
- `kubectl get sc st-bulk -o jsonpath` — Reads the annotation itself. Its key contains dots, so each one is escaped as `\.`; otherwise jsonpath would read them as steps into nested fields.

</details>

## What happens when a claim is created

1. You create the claim. If it names no class, the default class is filled in.
2. With `WaitForFirstConsumer`, nothing happens until a Pod that uses the claim is scheduled to a node.
3. The provisioner named in the class creates the storage (a disk, a folder, a file share). It also creates a PV named `pvc-`, with the class's reclaim policy.
4. Kubernetes binds the claim to the new PV. Both show `Bound`.
5. The kubelet on the Pod's node mounts the volume and starts the container.
6. Later, when the claim is deleted, a `Delete` PV is removed with its storage. A `Retain` PV becomes `Released` and keeps everything.

You can follow each step on the lab. The claim `cache` below is the one from the second task:

**Trace a volume on the lab, from claim to node directory**

```bash
kubectl -n st-sc get pvc cache                                   # Pending until a Pod uses it
kubectl -n st-sc describe pvc cache | tail -5                      # the WaitForFirstConsumer event
kubectl -n st-sc get pvc cache -o jsonpath='{.spec.volumeName}'    # pvc-<uid> once bound
kubectl get pv $(kubectl -n st-sc get pvc cache -o jsonpath='{.spec.volumeName}') -o yaml | grep -A3 -E 'hostPath:|nodeAffinity:|reclaimPolicy'
# local-path keeps the data on the node the Pod was scheduled to:
docker exec cka-worker ls /var/local-path-provisioner/             # pvc-<uid>_st-sc_cache
# The provisioner itself is an ordinary Deployment:
kubectl -n local-path-storage get pods
```

<details>
<summary>Line-by-line explanation</summary>

- `get pvc cache ` — Shows the claim's STATUS. With a WaitForFirstConsumer class it stays `Pending` until a Pod that uses it is scheduled, and that is normal.
- `describe pvc cache | tail -5` — `describe` ends with the Events list, and `tail -5` keeps only the last five lines, where the *waiting for first consumer* message appears.
- `-o jsonpath='{.spec.volumeName}'` — Prints the name of the PV the claim is bound to: `pvc-` plus the claim's uid. Empty output means it is not bound yet.
- `kubectl get pv $(` — `$(…)` runs the inner command first and pastes its output in place, so you read the bound PV without typing its long name. `grep -E` with `|` matches any of the three words; `-A3` adds three lines after each match.
- `docker exec cka-worker ls` — Lists the provisioner's data folder on the node. The PV's `nodeAffinity` tells you which node holds it; if the Pod went to `cka-worker2`, look there instead.
- `kubectl -n local-path-storage get pods` — The local-path provisioner runs as an ordinary Pod in its own namespace. If claims never get a PV, check that this Pod is running.

</details>

## Growing a claim

If the class has `allowVolumeExpansion: true`, a claim can grow. Raise `spec.resources.requests.storage` on the claim, never on the PV. The driver then grows the storage. Until it finishes, `status.capacity` still shows the old size. A claim can never shrink below its current size.

On this lab no class allows expansion, so the commands below use example names from another cluster. Try it here and the API server refuses. The error says *only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize*.

**Grow a claim where the class allows it (example names, not the lab)**

```bash
# Example for another cluster: class fast, namespace app and claim data do not exist on this lab
kubectl get sc fast -o jsonpath='{.allowVolumeExpansion}'          # must be true
kubectl -n app patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'
kubectl -n app get pvc data -o jsonpath='{.status.capacity.storage}{" "}{.status.conditions[*].type}'
# Interactive: kubectl edit pvc data -n app and change requests.storage
```

<details>
<summary>Line-by-line explanation</summary>

- `allowVolumeExpansion}'` — Checks first that the class allows growth. Empty output means the field is not set, which counts as false.
- `patch pvc data` — Raises the claim's request to 5Gi. You always resize the claim, never the PV; the driver then grows the storage behind it.
- `get pvc data -o jsonpath` — Prints the current size and any condition types, such as `Resizing` or `FileSystemResizePending`. The old size stays here until the resize has finished.

</details>

> [!IMPORTANT] **What the grader reads**
> For a class, the grader reads `provisioner`, `reclaimPolicy`, `volumeBindingMode`, `allowVolumeExpansion` and the default annotation. For a claim, it reads `spec.storageClassName` and checks for `Bound`. With `WaitForFirstConsumer`, Bound needs the Pod too. So when a question asks for a claim and a Pod, create both before you check. A Pending claim there is not a bug: it is a Pod you have not written yet.

## 📝 Key Takeaways

- A StorageClass creates PVs for you. You write only the claim, and the class's provisioner makes the storage and the PV.
- The new PV gets the class's `reclaimPolicy`. If the class does not set one, it is `Delete`.
- With `WaitForFirstConsumer`, a claim stays Pending until a Pod uses it. That is normal.
- One annotation marks the default class: `storageclass.kubernetes.io/is-default-class`. Keep exactly one default.
- Most class fields cannot be changed. To fix one, delete the class and create it again.

**📖 Official documentation:**

- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) *(search: "storage classes")*
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/) *(search: "dynamic volume provisioning")*
- [Change the default StorageClass](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/) *(search: "change default storage class")*

---

### 🎯 Task: Create a StorageClass

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Create a StorageClass named `fast-retain` that uses the provisioner `rancher.io/local-path`, keeps volumes after their claim is deleted, and delays volume binding until a Pod that uses the claim has been scheduled. It must not be the cluster's default class.

<details>
<summary>💡 Hints</summary>

- Beside `provisioner` you need `reclaimPolicy` and `volumeBindingMode`. Leave out the default annotation, or set it to "false".
- `kubectl get sc standard -o yaml` is a template that already has the right provisioner.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/fast-retain.yaml <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
YAML
kubectl apply -f /tmp/cka/fast-retain.yaml
kubectl get sc fast-retain
```

**Explanation:**

- `cat > /tmp/cka/fast-retain.yaml` — There is no `kubectl create storageclass`, so the class is written as YAML in a heredoc.
- `name: fast-retain` — No `annotations` block, so this class is not the default, which is what the question requires.
- `provisioner: rancher.io/local-path` — The provisioner the question names, the same one the lab's `standard` class uses.
- `reclaimPolicy: Retain` — "Keeps volumes after their claim is deleted" in the question means `Retain`.
- `volumeBindingMode: WaitForFirstConsumer` — "Delays binding until a Pod is scheduled" means `WaitForFirstConsumer`.
- `kubectl get sc fast-retain` — One line shows the PROVISIONER, RECLAIMPOLICY and VOLUMEBINDINGMODE columns, and no `(default)` after the name.

**Notes:** Nothing to wait for: a StorageClass is only a record, and `kubectl get sc` shows everything graded at once. If you start from `kubectl get sc standard -o yaml`, remove the default annotation, the `uid`, the `resourceVersion` and the `creationTimestamp`. Then change `reclaimPolicy`. The API refuses changes to `reclaimPolicy` or `volumeBindingMode` on an existing class, so a mistake means delete and create again.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
s="kubectl get sc fast-retain -o jsonpath"

kubectl get sc fast-retain >/dev/null 2>&1 && p "StorageClass fast-retain exists" || f "StorageClass fast-retain exists"
[ "$($s='{.provisioner}' 2>/dev/null)" = "rancher.io/local-path" ] && p "provisioner rancher.io/local-path" || f "provisioner rancher.io/local-path"
[ "$($s='{.reclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "reclaimPolicy Retain" || f "reclaimPolicy Retain"
[ "$($s='{.volumeBindingMode}' 2>/dev/null)" = "WaitForFirstConsumer" ] && p "volumeBindingMode WaitForFirstConsumer" || f "volumeBindingMode WaitForFirstConsumer"
[ "$($s='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" != "true" ] && p "not the default class" || f "not the default class"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Provision a volume dynamically from a class

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

In namespace `st-sc` create a PersistentVolumeClaim named `cache` that requests `500Mi` with access mode `ReadWriteOnce` from the StorageClass `fast-retain`. Then create a Pod named `cache-user` with image `busybox:1.36` and command `sh -c 'echo cached > /cache/marker; while true; do sleep 3600; done'` that mounts the claim at `/cache`. When you are done the claim must be `Bound`, and the PersistentVolume that backs it must have reclaim policy `Retain`.

<details>
<summary>💡 Hints</summary>

- The class is `WaitForFirstConsumer`, so the claim stays Pending until the Pod exists. That is expected.
- You do not create the PV. The provisioner does, and it copies the class's `reclaimPolicy` onto it.
- `kubectl get pv` shows the new `pvc-` volume and its RECLAIM POLICY.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/cache.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cache
  namespace: st-sc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-retain
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: cache-user
  namespace: st-sc
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo cached > /cache/marker; while true; do sleep 3600; done"]
      volumeMounts:
        - name: cache
          mountPath: /cache
  volumes:
    - name: cache
      persistentVolumeClaim:
        claimName: cache
YAML
kubectl apply -f /tmp/cka/cache.yaml
kubectl -n st-sc wait --for=condition=Ready pod/cache-user --timeout=120s
kubectl -n st-sc wait --for=jsonpath='{.status.phase}'=Bound pvc/cache --timeout=60s
kubectl -n st-sc get pvc cache
kubectl get pv $(kubectl -n st-sc get pvc cache -o jsonpath='{.spec.volumeName}')
```

**Explanation:**

- `cat > /tmp/cka/cache.yaml` — The claim and the Pod go in one file. With a WaitForFirstConsumer class, the claim does nothing without the Pod anyway.
- `kind: PersistentVolumeClaim` — Only a claim. You never write the PV for this task: the provisioner creates it once the Pod is scheduled.
- `storageClassName: fast-retain` — Names the class to provision from. Its `reclaimPolicy: Retain` is copied onto the new PV, which is how the PV ends up with the policy the question asks for.
- `storage: 500Mi` — The size the provisioner records on the new PV. local-path makes a plain directory and does not enforce the size, but the claim and PV still report 500Mi.
- `/cache/marker` — Writes a marker through the claim, so the file ends up on the provisioned volume, then keeps the container running.
- `persistentVolumeClaim:` — The Pod's volume `cache` points at the claim `cache`. The two names happen to match; the volume name only has to equal the `volumeMounts` entry above.
- `wait --for=condition=Ready pod/cache-user` — Waits for the Pod first. Scheduling the Pod is what triggers provisioning, so it stays Pending for a few seconds while the volume is created.
- `wait --for=jsonpath='{.status.phase}'=Bound pvc/cache` — By the time the Pod is Ready the claim is already Bound; this makes it explicit.
- `kubectl -n st-sc get pvc cache` — Shows STATUS `Bound` and the generated volume's name in the VOLUME column.
- `kubectl get pv $(` — Looks up that PV by name. Its RECLAIM POLICY column should read `Retain`, inherited from the class.

**Notes:** Apply the claim and the Pod together. For about ten seconds the Pod is `Pending` too, because the scheduler waits for the volume it just asked for. The new PV is named `pvc-`. It has `storageClassName: fast-retain`, the `Retain` policy, and a `nodeAffinity` for the node the Pod landed on. The data sits in `/var/local-path-provisioner/` on that node. Delete the claim later and the PV becomes `Released` instead of disappearing.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-sc
c="kubectl -n $ns get pvc cache -o jsonpath"
g="kubectl -n $ns get pod cache-user -o jsonpath"

kubectl -n $ns get pvc cache >/dev/null 2>&1 && p "PVC cache exists" || f "PVC cache exists"
[ "$($c='{.spec.storageClassName}' 2>/dev/null)" = "fast-retain" ] && p "PVC uses class fast-retain" || f "PVC uses class fast-retain"
[ "$($c='{.spec.resources.requests.storage}' 2>/dev/null)" = "500Mi" ] && p "PVC requests 500Mi" || f "PVC requests 500Mi"
$c='{.spec.accessModes[*]}' 2>/dev/null | grep -qw ReadWriteOnce && p "PVC access mode ReadWriteOnce" || f "PVC access mode ReadWriteOnce"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "PVC is Bound" || f "PVC is Bound"
pvname="$($c='{.spec.volumeName}' 2>/dev/null)"
[ -n "$pvname" ] && [ "$(kubectl get pv "$pvname" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "backing PV reclaim policy Retain" || f "backing PV reclaim policy Retain"
[ -n "$pvname" ] && [ "$(kubectl get pv "$pvname" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)" = "fast-retain" ] && p "backing PV belongs to fast-retain" || f "backing PV belongs to fast-retain"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod cache-user is Running" || f "pod cache-user is Running"
vol="$($g='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="cache")].name}' 2>/dev/null)"
[ -n "$vol" ] && [ "$($g="{.spec.containers[0].volumeMounts[?(@.name==\"$vol\")].mountPath}" 2>/dev/null)" = "/cache" ] && p "claim mounted at /cache" || f "claim mounted at /cache"
[ "$(kubectl -n $ns exec cache-user -- cat /cache/marker 2>/dev/null)" = "cached" ] && p "file written through the volume" || f "file written through the volume"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Change the default StorageClass

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

The cluster's default StorageClass is `standard`. A class named `st-bulk` has been added. Make `st-bulk` the default StorageClass so that claims which do not name a class use it, and make sure `standard` is no longer marked as default. Exactly one class may be marked default when you finish. Do not delete or recreate either class.

<details>
<summary>💡 Hints</summary>

- It is one annotation, `storageclass.kubernetes.io/is-default-class`, set to "true" or "false".
- Run `kubectl patch storageclass  -p '{"metadata":{"annotations":{...}}}'` on each class. `kubectl get sc` shows which one reads (default).

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl patch storageclass standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass st-bulk -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc
```

**Explanation:**

- `kubectl patch storageclass standard` — Takes the default mark off `standard` first. The value `"false"` must be a quoted string, since annotation values always are.
- `kubectl patch storageclass st-bulk` — Then marks `st-bulk` as the default. Neither class is recreated; one annotation changes on each.
- `kubectl get sc` — Exactly one class should read `(default)`: `st-bulk`. Restore `standard` after practicing, because the default applies to every new claim in the cluster.

**Notes:** Change the old class first, so there is never a moment with two defaults. Then mark the new one. `kubectl annotate storageclass st-bulk storageclass.kubernetes.io/is-default-class=true --overwrite` does the same job. For `standard`, the grader accepts `"false"` or no annotation at all. What fails is `"true"` on both. The default is cluster-wide: on the lab, restore `standard` afterwards, or every later claim without a class lands on `st-bulk`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ann() { kubectl get sc "$1" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null; }

kubectl get sc st-bulk >/dev/null 2>&1 && p "StorageClass st-bulk exists" || f "StorageClass st-bulk exists"
kubectl get sc standard >/dev/null 2>&1 && p "StorageClass standard still exists" || f "StorageClass standard still exists"
[ "$(ann st-bulk)" = "true" ] && p "st-bulk is marked default" || f "st-bulk is marked default"
[ "$(ann standard)" != "true" ] && p "standard is no longer default" || f "standard is no longer default"
defaults=0
for sc in $(kubectl get sc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do [ "$(ann $sc)" = "true" ] && defaults=$((defaults+1)); done
[ "$defaults" = "1" ] && p "exactly one default class" || f "exactly one default class (found $defaults)"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 4: Storage*
