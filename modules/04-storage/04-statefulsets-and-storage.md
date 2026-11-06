# StatefulSets and volumeClaimTemplates

> **Module 4** · Lesson 4.4 · 30 minutes

How a StatefulSet gives each Pod its own name, DNS name and claim, and what happens to the claims on scale-down or delete.

## Learning Objectives

- You can write a StatefulSet with a headless Service and a volumeClaimTemplate, and predict the names of its Pods and claims.
- You can scale a StatefulSet and say which claims are created, kept or deleted under each retention policy.
- You can choose between a Deployment and a StatefulSet for an app and say why.


Some apps run several copies, and each copy needs its own data. A database with three replicas is the classic example. If `db-1` restarts, it must get `db-1`'s disk back, not `db-0`'s. A **StatefulSet** does this. Each Pod gets a fixed name, its own DNS name and its own claim, and keeps all three when it restarts.

This lesson ties the module together. Each Pod's claim comes from a **volumeClaimTemplate**, and a StorageClass provisions it. The exam asks you to create a StatefulSet with storage, or to scale one and check its volumes. The grader checks names, so learn the naming rules.

**One StatefulSet, one claim per Pod**

*Delete `blog-1` and it comes back with the same name and the same claim, so it finds its data again. Its full DNS name is `blog-1.blog.st-sts.svc.cluster.local`.*

`StatefulSet: blog` — 2 replicas, claim template: content
  ↓
`Pods` — each with its own name, DNS name and claim
  - `blog-0` — DNS: blog-0.blog (`claim: content-blog-0`)
  - `blog-1` — DNS: blog-1.blog (`claim: content-blog-1`)
  ↓
`PersistentVolumes` — one per claim, made by the standard class

## StatefulSet or Deployment?

|  | Deployment | StatefulSet |
| --- | --- | --- |
| Pod names | Random suffix: `web-7d9c8-x4k2p` | Numbered and fixed: `web-0`, `web-1` |
| Network identity | Only through a Service | Each Pod has its own DNS name, through a headless Service |
| Storage | All replicas share the volumes in the Pod template | Each replica gets its own claim, and gets it back after a restart |
| Start and stop order | All at once | In order from 0 up; removed from the highest number down |
| Use it for | Stateless apps, such as a web front end | Databases, queues, anything where "which copy am I" matters |

## Stable names: the headless Service

A StatefulSet names a Service in `spec.serviceName`. That Service is *headless* (`clusterIP: None`): it has no virtual IP, and DNS answers with the Pod IPs directly. Each Pod then gets its own DNS name, `...svc.cluster.local`. Example: `blog-0.blog.st-sts.svc.cluster.local`.

- Like any Service, its selector must match the Pod labels.
- A client that needs one exact copy, such as the primary database, uses that Pod's name: `blog-0.blog`.
- A client that wants any copy uses the Service name, `blog`.

**The headless Service**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: blog
  namespace: st-sts
spec:
  clusterIP: None
  selector:
    app: blog
  ports:
    - name: http
      port: 80
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: Service` — A Service gives a stable name to a group of Pods. This one exists so that each StatefulSet Pod gets a DNS name of its own.
- `clusterIP: None` — Makes the Service **headless**: no virtual IP and no load balancing. DNS answers with the Pod IPs directly and adds a name per Pod, such as `blog-0.blog.st-sts.svc.cluster.local`.
- `selector:` — Picks Pods by label. It must match the labels in the StatefulSet's Pod template, `app: blog`.

</details>

**A StatefulSet with two replicas and a claim per Pod**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: blog
  namespace: st-sts
spec:
  serviceName: blog
  replicas: 2
  selector:
    matchLabels:
      app: blog
  template:
    metadata:
      labels:
        app: blog
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports:
            - containerPort: 80
              name: http
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: content
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: standard
        resources:
          requests:
            storage: 100Mi
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: apps/v1` — StatefulSets, like Deployments, belong to the `apps` API group.
- `serviceName: blog` — Names the headless Service above. Each Pod's DNS name is built from it: `.blog.st-sts.svc.cluster.local`.
- `replicas: 2` — Two Pods with fixed names, `blog-0` and `blog-1`, created in that order.
- `matchLabels:` — How the StatefulSet finds its Pods. It must equal the template's labels a few lines down; if it does not, the API rejects the object.
- `template:` — The blueprint for every Pod, the same as in a Deployment. Its `labels` are what the selector and the Service match.
- `- name: content` — Mounts the volume called `content`. This Pod template has no `volumes:` list: the name refers to the volumeClaimTemplate below, and each Pod gets its own claim for it.
- `volumeClaimTemplates:` — Sits under the StatefulSet's `spec`, beside `template`, not inside it. For each Pod the controller creates a claim named `--`: `content-blog-0`, `content-blog-1`.
- `storageClassName: standard` — Each claim is provisioned dynamically from the lab's `standard` class. That class waits for the first consumer, so each claim binds when its own Pod is scheduled.
- `storage: 100Mi` — Every replica gets a separate 100Mi volume; the replicas never share data.

</details>

## Pods start in order

By default (`podManagementPolicy: OrderedReady`) the Pods start one at a time. `blog-0` must be Running and Ready before `blog-1` starts. Scaling down removes the highest number first. A database that elects a leader needs this order. With `Parallel`, all Pods start and stop at once instead.

Either way, a deleted Pod comes back with the same name, the same claim and the same DNS name. That is the whole promise of a StatefulSet.

## volumeClaimTemplates and claim names

Each entry in `volumeClaimTemplates` is a claim spec. For every Pod, the StatefulSet creates one claim from it, named `--`. Example: template `content` on StatefulSet `blog` gives `content-blog-0` and `content-blog-1`.

- The container's `volumeMounts` uses the template name, `content`, as if it were a volume. There is no `volumes:` entry for it.
- The claims are ordinary PVCs. The StorageClass provisions them, and `kubectl get pvc` lists them.
- Each claim stays tied to the Pod with the same number.
- You cannot change `volumeClaimTemplates` on an existing StatefulSet. To change it, delete the StatefulSet and create it again.

**Create, inspect and scale**

```bash
kubectl apply -f blog.yaml
kubectl -n st-sts rollout status sts/blog --timeout=180s
kubectl -n st-sts get pods -l app=blog -o wide          # blog-0, blog-1
kubectl -n st-sts get pvc                                # content-blog-0, content-blog-1, both Bound
kubectl -n st-sts scale sts blog --replicas=3           # creates content-blog-2 then blog-2
kubectl -n st-sts get sts blog -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy}'
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl apply -f blog.yaml` — Creates the Service and the StatefulSet. Save both blocks above in one file, `blog.yaml`, with a `---` line between them.
- `rollout status sts/blog` — Waits until every replica is ready, or 180 seconds pass. `sts` is short for statefulset. The Pods start one by one, so this takes longer than for a Deployment.
- `get pods -l app=blog -o wide` — Lists the replicas by label. The names end in `-0` and `-1` rather than random letters, and `-o wide` shows which node each one landed on.
- `get pvc ` — One claim per replica, named after the template, the StatefulSet and the ordinal.
- `scale sts blog --replicas=3` — Adds `blog-2`. The controller creates its claim `content-blog-2` first, then the Pod that mounts it.
- `persistentVolumeClaimRetentionPolicy}'` — Shows what happens to the claims on scale-down and on delete. Unless someone changed it, both `whenScaled` and `whenDeleted` read `Retain`.

</details>

## What happens to the claims when you scale down or delete

By default, nothing: the claims stay. Scale from 3 to 2, and `content-blog-2` stays Bound with its data. Scale back to 3, and `blog-2` gets its old disk back. Delete the StatefulSet, and every claim survives too. That is why old claims pile up after test runs.

**Scaling down from 3 to 2**

`Scale to 2` (`--replicas=2`) → `blog-2 is removed` — the highest number goes first → `Claim content-blog-2` — kept, unless whenScaled is Delete

`spec.persistentVolumeClaimRetentionPolicy` changes this. It has two settings, and each one is `Retain` (the default) or `Delete`:

| Setting | Applies when | With Delete |
| --- | --- | --- |
| `whenScaled` | You scale down | The claim of each removed Pod is deleted once that Pod is gone |
| `whenDeleted` | You delete the StatefulSet | All its claims are deleted with it |

What happens to the data after a claim is deleted is still up to the PV's reclaim policy, which the StorageClass set. You can add the field to a running StatefulSet with a patch:

**Set a retention policy on a running StatefulSet**

```bash
kubectl -n st-sts patch sts blog -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'
kubectl -n st-sts scale sts blog --replicas=2
kubectl -n st-sts get pvc                                # content-blog-2 is gone after blog-2 terminates
# Cleaning up by hand when the policy is Retain:
kubectl -n st-sts delete sts blog
kubectl -n st-sts delete pvc -l app=blog                 # claims inherit the selector labels
```

<details>
<summary>Line-by-line explanation</summary>

- `patch sts blog` — Sets the policy on the live object: delete a replica's claim when the StatefulSet scales down, keep every claim when it is deleted. No recreate is needed, because this field is mutable.
- `scale sts blog --replicas=2` — Removes the highest ordinal, `blog-2`. Under the new policy its claim is deleted once the Pod has terminated.
- `get pvc ` — Only `content-blog-0` and `content-blog-1` remain. Whether the PV and its data go too is decided by the PV's reclaim policy, which is Delete for `standard`.
- `delete sts blog` — Deletes the StatefulSet and its Pods. With `whenDeleted: Retain` the claims stay behind.
- `delete pvc -l app=blog` — Removes the leftover claims in one command. This works because the controller copies the StatefulSet's selector labels onto every claim it creates.

</details>

Updates never touch the claims either. When you change the image, the StatefulSet replaces its Pods one at a time, from the highest number down. Each Pod comes back with its own claim and its data. The docs explain the details under [Rolling Updates](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#rolling-updates).

> [!IMPORTANT] **What the grader reads**
> Mostly names. Pods `-0` to `-N` Running. Claims `--` Bound. `spec.serviceName` matching a Service with `clusterIP: None`. `spec.replicas` equal to `status.readyReplicas`. Two common mistakes. First, a `selector` that does not match the template labels: the API rejects it, so read the error. Second, a template that asks for a class that does not exist: claims and Pods stay `Pending`. Finish with `kubectl get sts,pods,pvc -n ` and count.

## 📝 Key Takeaways

- A StatefulSet gives each Pod a fixed name (`blog-0`, `blog-1`), its own DNS name and its own claim.
- It needs a headless Service (`clusterIP: None`), named in `spec.serviceName`.
- Claims are named `--`, such as `content-blog-0`. Mount the template name, and add no `volumes:` entry for it.
- Pods start in order from 0. A restarted Pod gets its own claim back.
- Scaling down or deleting keeps the claims by default. `persistentVolumeClaimRetentionPolicy` can delete them instead.

**📖 Official documentation:**

- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) *(search: "statefulset")*
- [StatefulSet Basics](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/) *(search: "statefulset basics")*
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) *(search: "storage classes")*

---

### 🎯 Task: A StatefulSet with per-replica storage

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 6% |
| **Time** | 9 min |

**Question:**

In namespace `st-sts` create a headless Service named `blog` on port 80 with selector `app=blog`, and a StatefulSet named `blog` with 2 replicas of image `nginx:1.27` that uses that Service for its network identity. Every replica must get its own 100Mi `ReadWriteOnce` volume from the StorageClass `standard` through a volumeClaimTemplate named `content`, mounted at `/usr/share/nginx/html`. Both Pods must be Running and both claims Bound.

<details>
<summary>💡 Hints</summary>

- There is no `kubectl create statefulset`. Start from a Deployment: `kubectl create deployment blog --image=nginx:1.27 --dry-run=client -o yaml`. Change the kind, add `serviceName` and `volumeClaimTemplates`, and remove `strategy`.
- The `volumeMounts` name must equal the volumeClaimTemplate name. Do not add a `volumes:` entry for it.
- `kubectl create service clusterip blog --clusterip=None --tcp=80:80` makes the Service. Check its selector: it is `app=blog` only because the Service is named blog.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/blog.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: blog
  namespace: st-sts
spec:
  clusterIP: None
  selector:
    app: blog
  ports:
    - name: http
      port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: blog
  namespace: st-sts
spec:
  serviceName: blog
  replicas: 2
  selector:
    matchLabels:
      app: blog
  template:
    metadata:
      labels:
        app: blog
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports:
            - containerPort: 80
              name: http
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: content
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: standard
        resources:
          requests:
            storage: 100Mi
YAML
kubectl apply -f /tmp/cka/blog.yaml
kubectl -n st-sts rollout status sts/blog --timeout=180s
kubectl -n st-sts get pods,pvc
```

**Explanation:**

- `cat > /tmp/cka/blog.yaml` — There is no `kubectl create statefulset`, so the Service and the StatefulSet are written together in one file.
- `clusterIP: None` — Headless, as the question asks. Without this line you get a normal Service, and the grader checks this field.
- `serviceName: blog` — Ties the StatefulSet to that headless Service for its network identity.
- `labels:` — `app: blog` here must match both the StatefulSet's `selector` and the Service's `selector`.
- `- name: content` — Equal to the volumeClaimTemplate's name. No `volumes:` entry is needed: the controller adds each Pod's own claim as that volume.
- `volumeClaimTemplates:` — The per-replica storage. Each Pod gets a claim, `content-blog-0` and `content-blog-1`, which are the names the grader looks for.
- `storageClassName: standard` — The class the question names. The 100Mi size and ReadWriteOnce mode below come from the question too.
- `rollout status sts/blog` — Waits for both replicas. With the default ordered policy, `blog-1` starts only after `blog-0` is Ready.
- `get pods,pvc` — Two resource types in one command, separated by a comma. You should see two Running Pods and two Bound claims.

**Notes:** The Pods come up one at a time: `blog-0` and `content-blog-0` first, then `blog-1`. If `blog-0` never becomes Ready, nothing else happens, so look there first. A `selector` that does not match the template labels is rejected when you apply. The claims use the `standard` class, so each is provisioned as soon as its Pod is scheduled. Their names are `content-blog-`, and that is what the grader counts.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-sts
s="kubectl -n $ns get sts blog -o jsonpath"
svc="kubectl -n $ns get svc blog -o jsonpath"

kubectl -n $ns get svc blog >/dev/null 2>&1 && p "service blog exists" || f "service blog exists"
[ "$($svc='{.spec.clusterIP}' 2>/dev/null)" = "None" ] && p "service is headless" || f "service is headless"
[ "$($svc='{.spec.selector.app}' 2>/dev/null)" = "blog" ] && p "service selects app=blog" || f "service selects app=blog"
[ "$($svc='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "service port 80" || f "service port 80"
kubectl -n $ns get sts blog >/dev/null 2>&1 && p "statefulset blog exists" || f "statefulset blog exists"
[ "$($s='{.spec.serviceName}' 2>/dev/null)" = "blog" ] && p "serviceName blog" || f "serviceName blog"
[ "$($s='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "replicas = 2" || f "replicas = 2"
[ "$($s='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($s='{.spec.volumeClaimTemplates[0].metadata.name}' 2>/dev/null)" = "content" ] && p "volumeClaimTemplate content" || f "volumeClaimTemplate content"
[ "$($s='{.spec.volumeClaimTemplates[0].spec.storageClassName}' 2>/dev/null)" = "standard" ] && p "template uses class standard" || f "template uses class standard"
[ "$($s='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}' 2>/dev/null)" = "100Mi" ] && p "template requests 100Mi" || f "template requests 100Mi"
$s='{.spec.volumeClaimTemplates[0].spec.accessModes[*]}' 2>/dev/null | grep -qw ReadWriteOnce && p "template access mode ReadWriteOnce" || f "template access mode ReadWriteOnce"
[ "$($s='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="content")].mountPath}' 2>/dev/null)" = "/usr/share/nginx/html" ] && p "content mounted at /usr/share/nginx/html" || f "content mounted at /usr/share/nginx/html"
[ "$($s='{.status.readyReplicas}' 2>/dev/null)" = "2" ] && p "2 replicas ready" || f "2 replicas ready"
for i in 0 1; do
  [ "$(kubectl -n $ns get pod blog-$i -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod blog-$i Running" || f "pod blog-$i Running"
  [ "$(kubectl -n $ns get pvc content-blog-$i -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "pvc content-blog-$i Bound" || f "pvc content-blog-$i Bound"
done

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Scale a StatefulSet and control what happens to its claims

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

The StatefulSet `blog` in namespace `st-sts` runs 2 replicas, each with its own volume. Scale it to 3 replicas and make sure the new replica gets its own claim. Also configure the StatefulSet so that from now on the claim of a replica is deleted when the StatefulSet is scaled down, but all claims are kept if the StatefulSet itself is deleted. All 3 Pods must be Running when you finish.

<details>
<summary>💡 Hints</summary>

- `kubectl scale sts blog --replicas=3 -n st-sts`. The third claim is named after the template, the StatefulSet and the number.
- The policy is `spec.persistentVolumeClaimRetentionPolicy`, with `whenScaled` and `whenDeleted`. You can patch it on a live StatefulSet.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n st-sts patch sts blog -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'
kubectl -n st-sts scale sts blog --replicas=3
kubectl -n st-sts rollout status sts/blog --timeout=180s
kubectl -n st-sts wait --for=jsonpath='{.status.phase}'=Bound pvc/content-blog-2 --timeout=60s
kubectl -n st-sts get pods,pvc
```

**Explanation:**

- `patch sts blog` — Adds the policy the question describes: `whenScaled: Delete` removes a replica's claim on scale-down, and `whenDeleted: Retain` keeps every claim if the StatefulSet is deleted.
- `scale sts blog --replicas=3` — Creates `blog-2` and, from the template, its own claim `content-blog-2`.
- `rollout status sts/blog` — Waits until all three replicas are ready.
- `pvc/content-blog-2` — Confirms the new claim is Bound. With the `standard` class that happens once `blog-2` has been scheduled.
- `get pods,pvc` — Final check: three Running Pods and three Bound claims.

**Notes:** The order does not matter to the grader. Patch first, and the policy is already in place for any later scale-down. The interactive way is `kubectl edit sts blog -n st-sts`: add the `persistentVolumeClaimRetentionPolicy` block beside `replicas`. The third claim, `content-blog-2`, is created before `blog-2` is scheduled. It binds as soon as the Pod lands on a node. To see the policy work, scale back to 2 and watch `content-blog-2` disappear.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-sts
s="kubectl -n $ns get sts blog -o jsonpath"

kubectl -n $ns get sts blog >/dev/null 2>&1 && p "statefulset blog exists" || f "statefulset blog exists"
[ "$($s='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "replicas = 3" || f "replicas = 3"
[ "$($s='{.status.readyReplicas}' 2>/dev/null)" = "3" ] && p "3 replicas ready" || f "3 replicas ready"
[ "$($s='{.spec.persistentVolumeClaimRetentionPolicy.whenScaled}' 2>/dev/null)" = "Delete" ] && p "whenScaled Delete" || f "whenScaled Delete"
[ "$($s='{.spec.persistentVolumeClaimRetentionPolicy.whenDeleted}' 2>/dev/null)" = "Retain" ] && p "whenDeleted Retain" || f "whenDeleted Retain"
for i in 0 1 2; do
  [ "$(kubectl -n $ns get pod blog-$i -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod blog-$i Running" || f "pod blog-$i Running"
  [ "$(kubectl -n $ns get pvc content-blog-$i -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "pvc content-blog-$i Bound" || f "pvc content-blog-$i Bound"
done

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 4: Storage*
