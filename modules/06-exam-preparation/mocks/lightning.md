# Lightning lab

> ⏱️ 30 minutes · 6 tasks · Pass mark: 66%

Six short tasks, one per domain plus an extra troubleshooting one, in 30 minutes: a fast confidence check before the full mocks.

## Tasks

### Task 1: Deployment with no ready Pods

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 20% |
| **Time** | 4 min |

**Question:**

Switch to the lab cluster with `kubectl config use-context kind-cka`. The Deployment `catalog` in namespace `ll-shop` was created a few minutes ago and none of its Pods have become ready. The team intended to deploy **nginx 1.27**. Find the cause and fix the Deployment so that both replicas are available.

<details>
<summary>💡 Hints</summary>

- kubectl get pods -n ll-shop, then kubectl describe on one of them: the Events section names the problem.
- The container in a Deployment created with kubectl create deployment is named after the image, so kubectl set image deploy/catalog nginx=… works.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ll-shop describe pods -l app=catalog | grep -i -A2 'Failed\|Back-off' || true
kubectl -n ll-shop set image deploy/catalog nginx=nginx:1.27
kubectl -n ll-shop rollout status deploy/catalog --timeout=120s
```

**Explanation:**

- `describe pods -l app=catalog` — Describes every catalog Pod and keeps the failure events plus 2 lines after each. `\|` means OR in grep, `-i` ignores case, and `|| true` keeps a script going if nothing matches.
- `set image deploy/catalog nginx=nginx:1.27` — Puts the tag that exists in place of the broken one. `nginx=` names the container, which `kubectl create deployment` named after the image.
- `rollout status deploy/catalog` — Waits until both new Pods are available. The grader counts ready replicas, so finish here.

**Notes:** `ImagePullBackOff` with *manifest unknown* in the events means the tag does not exist. On the exam `kubectl edit deploy catalog -n ll-shop` and correcting the tag is just as valid; the grader only reads the live image and the ready count. Always finish with `rollout status` so you know the new Pods actually came up.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-shop
d="kubectl -n $ns get deploy catalog -o jsonpath"
kubectl -n $ns get deploy catalog >/dev/null 2>&1 && p "deployment catalog exists" || f "deployment catalog exists"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "2 replicas" || f "2 replicas"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 2: ServiceAccount permissions

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 18% |
| **Time** | 4 min |

**Question:**

In namespace `ll-rbac` create a ServiceAccount named `deployer`, a Role named `deployment-editor` that allows `get`, `list`, `watch`, `create`, `update` and `patch` on Deployments and nothing else, and a RoleBinding named `deployer-binding` that grants the Role to the ServiceAccount. The ServiceAccount must not be able to delete Deployments or read Pods.

<details>
<summary>💡 Hints</summary>

- kubectl create role and kubectl create rolebinding take --verb, --resource, --role and --serviceaccount=namespace:name.
- Check your work with kubectl auth can-i … --as=system:serviceaccount:ll-rbac:deployer -n ll-rbac.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ll-rbac create serviceaccount deployer
kubectl -n ll-rbac create role deployment-editor --verb=get,list,watch,create,update,patch --resource=deployments.apps
kubectl -n ll-rbac create rolebinding deployer-binding --role=deployment-editor --serviceaccount=ll-rbac:deployer
kubectl -n ll-rbac auth can-i create deployments --as=system:serviceaccount:ll-rbac:deployer
kubectl -n ll-rbac auth can-i delete deployments --as=system:serviceaccount:ll-rbac:deployer || true
```

**Explanation:**

- `create serviceaccount deployer` — Creates the identity in namespace `ll-rbac`.
- `create role deployment-editor` — Exactly the six verbs on Deployments and nothing else. `deployments.apps` spells out the API group; plain `deployments` works too.
- `create rolebinding deployer-binding` — Grants the Role to the ServiceAccount, written `namespace:name`.
- `auth can-i create deployments` — Asks as the ServiceAccount, using its full username. Should print yes.
- `auth can-i delete deployments` — Should print no. can-i exits with an error code on no, so `|| true` keeps that from looking like a failure.

**Notes:** Deployments live in the `apps` API group; `--resource=deployments` resolves it for you, `deployments.apps` is explicit. A RoleBinding subject for a ServiceAccount needs the namespace, hence `--serviceaccount=ll-rbac:deployer`. The grader checks effective permissions, so the `auth can-i` lines are the fastest self-check you have.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-rbac
sa=system:serviceaccount:ll-rbac:deployer
kubectl -n $ns get sa deployer >/dev/null 2>&1 && p "serviceaccount deployer exists" || f "serviceaccount deployer exists"
kubectl -n $ns get role deployment-editor >/dev/null 2>&1 && p "role deployment-editor exists" || f "role deployment-editor exists"
[ "$(kubectl -n $ns get rolebinding deployer-binding -o jsonpath='{.roleRef.name}' 2>/dev/null)" = "deployment-editor" ] && p "rolebinding references the role" || f "rolebinding references the role"
[ "$(kubectl -n $ns get rolebinding deployer-binding -o jsonpath='{.subjects[?(@.kind=="ServiceAccount")].name}' 2>/dev/null)" = "deployer" ] && p "rolebinding subject is the serviceaccount" || f "rolebinding subject is the serviceaccount"
for v in get list watch create update patch; do
  [ "$(kubectl -n $ns auth can-i $v deployments --as=$sa 2>/dev/null)" = "yes" ] && p "can $v deployments" || f "can $v deployments"
done
[ "$(kubectl -n $ns auth can-i delete deployments --as=$sa 2>/dev/null)" = "no" ] && p "cannot delete deployments" || f "cannot delete deployments"
[ "$(kubectl -n $ns auth can-i get pods --as=$sa 2>/dev/null)" = "no" ] && p "cannot get pods" || f "cannot get pods"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 3: Expose a Deployment inside the cluster

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 18% |
| **Time** | 4 min |

**Question:**

The Deployment `front` in namespace `ll-svc` serves HTTP on container port `8080`. Create a Service named `front` of type `ClusterIP` in the same namespace that exposes those Pods on port `80`. When you are done the Service must have one endpoint per Pod, and `wget -qO- http://front/hostname` run from Pod `client` in the namespace must return a Pod name.

<details>
<summary>💡 Hints</summary>

- kubectl expose deployment front --port=80 --target-port=8080 -n ll-svc does it in one line.
- kubectl get endpointslices -n ll-svc shows whether the selector matched anything.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ll-svc expose deployment front --name=front --port=80 --target-port=8080
sleep 3
kubectl -n ll-svc exec client -- wget -qO- -T 5 http://front/hostname
```

**Explanation:**

- `expose deployment front` — Creates ClusterIP Service `front` with the Deployment's selector. Clients use port 80; traffic goes to the container's 8080.
- `sleep 3` — Gives the endpoints a moment to appear.
- `exec client -- wget` — Runs wget inside Pod `client`. The short name `front` resolves because both are in one namespace; `-T 5` is a 5-second timeout. agnhost answers `/hostname` with its Pod name.

**Notes:** `kubectl expose` copies the Deployment's selector, so the endpoints appear as soon as the Pods are Ready. If the question gives a port the container does not listen on, that mismatch between `port` and `targetPort` is the thing to get right; the DNS name `front` resolves because the client Pod is in the same namespace.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-svc
s="kubectl -n $ns get svc front -o jsonpath"
kubectl -n $ns get svc front >/dev/null 2>&1 && p "service front exists" || f "service front exists"
[ "$($s='{.spec.type}' 2>/dev/null)" = "ClusterIP" ] && p "type ClusterIP" || f "type ClusterIP"
[ "$($s='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "port 80" || f "port 80"
[ "$($s='{.spec.ports[0].targetPort}' 2>/dev/null)" = "8080" ] && p "targetPort 8080" || f "targetPort 8080"
eps=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=front -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null | wc -w | tr -d ' ')
[ "$eps" = "2" ] && p "2 endpoints" || f "2 endpoints (got $eps)"
ok=0
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec client -- wget -qO- -T 3 http://front/hostname 2>/dev/null)
  case "$out" in front-*) ok=1; break;; esac
  sleep 2
done
[ $ok = 1 ] && p "http://front/hostname answers from a pod" || f "http://front/hostname answers from a pod"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 4: Update an image and scale

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 16% |
| **Time** | 3 min |

**Question:**

The Deployment `portal` in namespace `ll-web` runs `nginx:1.26` with a single replica. Update it to `nginx:1.27` and scale it to **3** replicas. All three Pods must be available when you finish.

<details>
<summary>💡 Hints</summary>

- kubectl set image and kubectl scale; then kubectl rollout status to be sure.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n ll-web set image deploy/portal nginx=nginx:1.27
kubectl -n ll-web scale deploy/portal --replicas=3
kubectl -n ll-web rollout status deploy/portal --timeout=120s
```

**Explanation:**

- `set image deploy/portal` — Starts a rollout to nginx 1.27, a new revision.
- `scale deploy/portal --replicas=3` — Raises the replica count to 3. Scaling does not create a revision.
- `rollout status deploy/portal` — Waits until all three Pods run the new image and are available.

**Notes:** Two imperative commands and a wait. The image change creates a new ReplicaSet (a revision); the scale does not. The grader reads `spec.replicas`, the template image and `status.availableReplicas`, so do not move on while `rollout status` is still waiting.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-web
d="kubectl -n $ns get deploy portal -o jsonpath"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "replicas = 3" || f "replicas = 3"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 5: Static volume for a Pod

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 12% |
| **Time** | 3 min |

**Question:**

Create a PersistentVolume named `ll-pv` with `200Mi` capacity, access mode `ReadWriteOnce`, `storageClassName: manual`, reclaim policy `Retain`, backed by `hostPath` `/data/ll-pv`. In namespace `ll-store` create a PersistentVolumeClaim named `ll-pvc` that requests `100Mi` with the same storage class and access mode so that it binds to `ll-pv`, and a Pod named `ll-writer` (image `busybox:1.36`, command `sleep 3600`) that mounts the claim at `/data`.

<details>
<summary>💡 Hints</summary>

- Three objects, one YAML file: PV, PVC, Pod. The PVC binds only if class, access mode and size fit the PV.
- kubectl get pv,pvc -n ll-store should show both as Bound before you create the Pod.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ll-pv
spec:
  capacity:
    storage: 200Mi
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /data/ll-pv
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ll-pvc
  namespace: ll-store
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: ll-writer
  namespace: ll-store
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ll-pvc
EOF
kubectl -n ll-store wait --for=condition=Ready pod/ll-writer --timeout=120s
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `kind: PersistentVolume` — The volume itself, cluster-wide: 200Mi from a folder on the node, kept after its claim goes away (Retain).
- `storageClassName: manual` — A claim binds only to a PV with the same class name.
- `kind: PersistentVolumeClaim` — The claim, in the Pod's namespace.
- `storageClassName: manual` — The same class as the PV. Leave it out and the default class `standard` provisions a new volume instead.
- `storage: 100Mi` — Asks for 100Mi; the 200Mi PV is big enough, so they can bind.
- `mountPath: /data` — Mounts the volume named `data` at `/data` in the container.
- `claimName: ll-pvc` — That volume is the claim `ll-pvc`. A Pod never names the PV directly.
- `wait --for=condition=Ready pod/ll-writer` — Waits for the Pod to run, which also proves the claim bound and mounted.

**Notes:** There is no imperative command for PVs or PVCs; copy the examples from the *Persistent Volumes* docs page. The trap is `storageClassName`: leave it out of the PVC and the default class `standard` provisions a brand-new volume instead of binding to `ll-pv`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-store
v="kubectl get pv ll-pv -o jsonpath"
c="kubectl -n $ns get pvc ll-pvc -o jsonpath"
o="kubectl -n $ns get pod ll-writer -o jsonpath"
kubectl get pv ll-pv >/dev/null 2>&1 && p "pv ll-pv exists" || f "pv ll-pv exists"
[ "$($v='{.spec.capacity.storage}' 2>/dev/null)" = "200Mi" ] && p "pv capacity 200Mi" || f "pv capacity 200Mi"
[ "$($v='{.spec.accessModes[0]}' 2>/dev/null)" = "ReadWriteOnce" ] && p "pv ReadWriteOnce" || f "pv ReadWriteOnce"
[ "$($v='{.spec.storageClassName}' 2>/dev/null)" = "manual" ] && p "pv storageClassName manual" || f "pv storageClassName manual"
[ "$($v='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null)" = "Retain" ] && p "pv reclaim Retain" || f "pv reclaim Retain"
[ "$($v='{.spec.hostPath.path}' 2>/dev/null)" = "/data/ll-pv" ] && p "pv hostPath /data/ll-pv" || f "pv hostPath /data/ll-pv"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "pvc Bound" || f "pvc Bound"
[ "$($c='{.spec.volumeName}' 2>/dev/null)" = "ll-pv" ] && p "pvc bound to ll-pv" || f "pvc bound to ll-pv"
[ "$($o='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod ll-writer Running" || f "pod ll-writer Running"
[ -n "$($o='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="ll-pvc")].name}' 2>/dev/null)" ] && p "pod uses claim ll-pvc" || f "pod uses claim ll-pvc"
[ -n "$($o='{.spec.containers[0].volumeMounts[?(@.mountPath=="/data")].name}' 2>/dev/null)" ] && p "mounted at /data" || f "mounted at /data"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 6: Find the Pod that logs an error

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 16% |
| **Time** | 2 min |

**Question:**

One of the Pods in namespace `ll-logs` logs a database connection error. Write the name of that Pod to `/tmp/cka/ll-06-pod.txt` and copy the complete log line that contains `ERR_DB_CONN`, and nothing else, to `/tmp/cka/ll-06-line.txt`. (On the exam answer files live under paths like `/opt/course/…`.)

<details>
<summary>💡 Hints</summary>

- kubectl logs with a label-free loop: for p in $(kubectl get pods -n ll-logs -o name); do kubectl logs -n ll-logs $p | grep ERR_DB_CONN && echo $p; done

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
for pod in $(kubectl -n ll-logs get pods -o jsonpath='{.items[*].metadata.name}'); do
  if kubectl -n ll-logs logs $pod | grep -q ERR_DB_CONN; then
    echo "$pod" > /tmp/cka/ll-06-pod.txt
    kubectl -n ll-logs logs $pod | grep ERR_DB_CONN > /tmp/cka/ll-06-line.txt
  fi
done
cat /tmp/cka/ll-06-pod.txt /tmp/cka/ll-06-line.txt
```

**Explanation:**

- `for pod in $(kubectl -n ll-logs get pods` — Loops over the Pod names. jsonpath prints bare names, without the `pod/` prefix the answer file must not have.
- `grep -q ERR_DB_CONN; then` — `grep -q` prints nothing and only reports whether the text was found, which is what `if` tests.
- `echo "$pod" > /tmp/cka/ll-06-pod.txt` — Writes the matching Pod's name to the first answer file.
- `grep ERR_DB_CONN > /tmp/cka/ll-06-line.txt` — Saves only the matching log line to the second file.
- `cat /tmp/cka/ll-06-pod.txt` — Prints both files so you can check them.

**Notes:** With three Pods you can simply run `kubectl logs` on each; with thirty, loop as above or use `kubectl logs -l  --prefix`. The grader compares file contents exactly, so write the bare Pod name (no `pod/` prefix) and only the matching line.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=ll-logs
[ "$(tr -d '[:space:]' < /tmp/cka/ll-06-pod.txt 2>/dev/null)" = "beta" ] && p "pod file names beta" || f "pod file names beta"
line=$(kubectl -n $ns logs beta 2>/dev/null | grep ERR_DB_CONN | head -1)
[ -n "$line" ] && grep -qxF "$line" /tmp/cka/ll-06-line.txt 2>/dev/null && p "line file holds the exact log line" || f "line file holds the exact log line"
[ "$(grep -c . /tmp/cka/ll-06-line.txt 2>/dev/null)" = "1" ] && p "line file has exactly one line" || f "line file has exactly one line"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka)*
