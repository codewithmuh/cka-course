# Mock exam 1

> ⏱️ 120 minutes · 17 tasks · Pass mark: 66%

Seventeen tasks across all five domains in two hours, weighted like the real curriculum, with one node-maintenance task that is disruptive.

## Tasks

### Task 1: Permissions for a pipeline bot

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 9 min |

**Question:**

Use `kubectl config use-context kind-cka` for every task in this exam. A CustomResourceDefinition for *Pipelines* is installed in the cluster. In namespace `m1-rbac`: create a ServiceAccount `ci-bot`; create a Role `pipeline-runner` that allows `get`, `list`, `watch`, `create`, `update` and `patch` on Deployments and `get`, `list`, `create` and `delete` on Pipelines; bind the Role to the ServiceAccount with a RoleBinding `ci-bot-pipeline-runner`. Finally create a Pipeline named `nightly` in `m1-rbac` with `spec.schedule` set to `0 2 * * *` and `spec.stages` set to `3`. `ci-bot` must not be able to delete Deployments or read Secrets.

<details>
<summary>💡 Hints</summary>

- kubectl get crd and kubectl api-resources --api-group= give you the group, the plural and the kind of the custom resource.
- A Role needs one rule per API group: apps for Deployments, the CRD's group for Pipelines.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get crd | grep -i pipeline
kubectl api-resources --api-group=m1.cka.codewithmuh.com
kubectl -n m1-rbac create serviceaccount ci-bot
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pipeline-runner
  namespace: m1-rbac
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["m1.cka.codewithmuh.com"]
    resources: ["pipelines"]
    verbs: ["get", "list", "create", "delete"]
EOF
kubectl -n m1-rbac create rolebinding ci-bot-pipeline-runner --role=pipeline-runner --serviceaccount=m1-rbac:ci-bot
cat <<'EOF' | kubectl apply -f -
apiVersion: m1.cka.codewithmuh.com/v1
kind: Pipeline
metadata:
  name: nightly
  namespace: m1-rbac
spec:
  schedule: "0 2 * * *"
  stages: 3
EOF
kubectl -n m1-rbac get pipelines
```

**Explanation:**

- `kubectl get crd | grep -i pipeline` — Finds the CRD. Its name, `pipelines.m1.cka.codewithmuh.com`, is plural.group.
- `api-resources --api-group=` — Shows the resource name RBAC needs (`pipelines`), the kind (`Pipeline`) and the short name.
- `create serviceaccount ci-bot` — The ServiceAccount the binding will name.
- `cat <<'EOF' | kubectl apply -f -` — The Role is written in YAML because it needs two rules, one per API group.
- `apiGroups: ["apps"]` — Rule one: Deployments, in the `apps` group, with the six verbs asked for.
- `apiGroups: ["m1.cka.codewithmuh.com"]` — Rule two: the custom resource by group and plural, with only its four verbs. Secrets appear nowhere, so they stay forbidden.
- `create rolebinding ci-bot-pipeline-runner` — Grants the Role to `ci-bot`.
- `apiVersion: m1.cka.codewithmuh.com/v1` — A custom resource is written like any object: apiVersion is the CRD's group/version, kind is `Pipeline`.
- `schedule: "0 2 * * *"` — Quoting is a safe habit for schedules: one that starts with `*`, like `*/5 * * * *`, is invalid YAML unquoted.
- `stages: 3` — Unquoted, so it is an integer, as the CRD's schema requires.
- `kubectl -n m1-rbac get pipelines` — Lists the new Pipeline to confirm it was accepted.

**Notes:** Start with `kubectl get crd`: the CRD's name is `.`, and `kubectl explain pipeline.spec` shows the fields once you know the kind. `kubectl create role` accepts `--resource=pipelines.m1.cka.codewithmuh.com` for one rule; with two API groups it is quicker to generate YAML and add the second rule. Quote the schedule in YAML: a value that starts with `*`, like `*/5 * * * *`, is read as an alias and the apply fails, and quoting every schedule means you never have to think about it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-rbac
sa=system:serviceaccount:m1-rbac:ci-bot
kubectl -n $ns get sa ci-bot >/dev/null 2>&1 && p "serviceaccount ci-bot exists" || f "serviceaccount ci-bot exists"
[ "$(kubectl -n $ns get rolebinding ci-bot-pipeline-runner -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)" = "Role/pipeline-runner" ] && p "rolebinding references Role pipeline-runner" || f "rolebinding references Role pipeline-runner"
[ "$(kubectl -n $ns get rolebinding ci-bot-pipeline-runner -o jsonpath='{.subjects[?(@.kind=="ServiceAccount")].name}' 2>/dev/null)" = "ci-bot" ] && p "rolebinding subject ci-bot" || f "rolebinding subject ci-bot"
for v in get list watch create update patch; do
  [ "$(kubectl -n $ns auth can-i $v deployments.apps --as=$sa 2>/dev/null)" = "yes" ] && p "can $v deployments" || f "can $v deployments"
done
for v in get list create delete; do
  [ "$(kubectl -n $ns auth can-i $v pipelines.m1.cka.codewithmuh.com --as=$sa 2>/dev/null)" = "yes" ] && p "can $v pipelines" || f "can $v pipelines"
done
[ "$(kubectl -n $ns auth can-i delete deployments.apps --as=$sa 2>/dev/null)" = "no" ] && p "cannot delete deployments" || f "cannot delete deployments"
[ "$(kubectl -n $ns auth can-i get secrets --as=$sa 2>/dev/null)" = "no" ] && p "cannot read secrets" || f "cannot read secrets"
[ "$(kubectl -n $ns get pipelines.m1.cka.codewithmuh.com nightly -o jsonpath='{.spec.schedule}' 2>/dev/null)" = "0 2 * * *" ] && p "pipeline nightly schedule 0 2 * * *" || f "pipeline nightly schedule 0 2 * * *"
[ "$(kubectl -n $ns get pipelines.m1.cka.codewithmuh.com nightly -o jsonpath='{.spec.stages}' 2>/dev/null)" = "3" ] && p "pipeline nightly stages 3" || f "pipeline nightly stages 3"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 2: Rolling update without losing capacity

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Deployment `checkout` in namespace `m1-shop` must be updated to image `nginx:1.27`. Before updating, configure its rolling update so that at no point fewer than 3 Pods are available and at most 1 extra Pod is created during the rollout. Record the update by setting the annotation `kubernetes.io/change-cause` on the Deployment to `image nginx:1.27`. When you finish, all 3 replicas must be available.

<details>
<summary>💡 Hints</summary>

- maxUnavailable: 0 and maxSurge: 1 under spec.strategy.rollingUpdate.
- kubectl annotate deploy/checkout kubernetes.io/change-cause='image nginx:1.27' sets the cause; --record no longer exists.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m1-shop patch deploy checkout -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl -n m1-shop set image deploy/checkout nginx=nginx:1.27
kubectl -n m1-shop annotate deploy/checkout kubernetes.io/change-cause='image nginx:1.27' --overwrite
kubectl -n m1-shop rollout status deploy/checkout --timeout=180s
kubectl -n m1-shop rollout history deploy/checkout
```

**Explanation:**

- `patch deploy checkout` — Sets the rollout limits before the image changes: `maxUnavailable: 0` keeps all 3 Pods serving, `maxSurge: 1` allows one extra Pod at a time. `-p` merges the patch into the live object.
- `set image deploy/checkout` — Starts the rollout, now under the new limits.
- `annotate deploy/checkout` — Records the reason shown in `rollout history`. `--overwrite` replaces any existing value.
- `rollout status deploy/checkout` — Waits for the rollout. It replaces one Pod at a time, so the timeout is a little longer.
- `rollout history deploy/checkout` — Confirms a new revision with your change cause.

**Notes:** On the exam open the Deployment with `kubectl edit`, set the two `rollingUpdate` values and the image in one go, then annotate. Changing the strategy alone does not create a revision; the image change does. The annotation is copied to the new ReplicaSet so it shows up in `rollout history`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-shop
d="kubectl -n $ns get deploy checkout -o jsonpath"
[ "$($d='{.spec.strategy.type}' 2>/dev/null)" = "RollingUpdate" ] && p "strategy RollingUpdate" || f "strategy RollingUpdate"
[ "$($d='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)" = "1" ] && p "maxSurge 1" || f "maxSurge 1"
[ "$($d='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)" = "0" ] && p "maxUnavailable 0" || f "maxUnavailable 0"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($d='{.metadata.annotations.kubernetes\.io/change-cause}' 2>/dev/null)" = "image nginx:1.27" ] && p "change-cause recorded" || f "change-cause recorded"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 3: Ingress for the shop

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

Deployment `shop` in namespace `m1-ing` is exposed by Service `shop` on port `80`. Create an Ingress named `shop` in that namespace, using IngressClass `nginx`, that routes HTTP requests for host `m1-shop.local` and path `/` (type `Prefix`) to that Service. The lab's ingress controller answers on `http://localhost:8080`; `curl -s -H 'Host: m1-shop.local' localhost:8080/` must return the nginx welcome page.

<details>
<summary>💡 Hints</summary>

- kubectl create ingress shop --class=nginx --rule='m1-shop.local/*=shop:80' -n m1-ing generates it; check the result with kubectl get ingress -o yaml.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: m1-ing
spec:
  ingressClassName: nginx
  rules:
    - host: m1-shop.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: shop
                port:
                  number: 80
EOF
for i in $(seq 1 15); do
  curl -s -H 'Host: m1-shop.local' http://localhost:8080/ | grep -q 'Welcome to nginx' && break
  sleep 2
done
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: m1-shop.local' http://localhost:8080/
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — The Ingress as YAML. `kubectl create ingress shop --class=nginx --rule='m1-shop.local/*=shop:80' -n m1-ing` makes the same object in one line.
- `ingressClassName: nginx` — Hands the Ingress to the lab's ingress-nginx controller.
- `host: m1-shop.local` — Only requests with this Host header match.
- `pathType: Prefix` — With path `/`, Prefix matches every path.
- `number: 80` — The backend is Service `shop` on its port 80.
- `for i in $(seq 1 15); do` — Retries for up to 30 seconds while the controller loads the rule. `grep -q` succeeds once the welcome page appears, and `break` ends the loop.
- `-w '%{http_code}` — Prints only the HTTP status code; 200 means the route works. `-o /dev/null` throws the page away.

**Notes:** The imperative `kubectl create ingress` form is quicker; `/*` in the rule means pathType Prefix. Three fields decide whether it serves: `ingressClassName`, the host, and the backend Service name plus port number. The controller needs a second or two to reload after you create the object, so repeat the curl before you panic.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-ing
g="kubectl -n $ns get ingress shop -o jsonpath"
kubectl -n $ns get ingress shop >/dev/null 2>&1 && p "ingress shop exists" || f "ingress shop exists"
[ "$($g='{.spec.ingressClassName}' 2>/dev/null)" = "nginx" ] && p "ingressClassName nginx" || f "ingressClassName nginx"
[ "$($g='{.spec.rules[0].host}' 2>/dev/null)" = "m1-shop.local" ] && p "host m1-shop.local" || f "host m1-shop.local"
[ "$($g='{.spec.rules[0].http.paths[0].path}' 2>/dev/null)" = "/" ] && p "path /" || f "path /"
[ "$($g='{.spec.rules[0].http.paths[0].pathType}' 2>/dev/null)" = "Prefix" ] && p "pathType Prefix" || f "pathType Prefix"
[ "$($g='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)" = "shop" ] && p "backend service shop" || f "backend service shop"
[ "$($g='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)" = "80" ] && p "backend port 80" || f "backend port 80"
ok=0
for i in $(seq 1 15); do
  curl -s -m 5 -H 'Host: m1-shop.local' http://localhost:8080/ 2>/dev/null | grep -q 'Welcome to nginx' && { ok=1; break; }
  sleep 2
done
[ $ok = 1 ] && p "ingress serves m1-shop.local via localhost:8080" || f "ingress serves m1-shop.local via localhost:8080"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 4: New StorageClass with dynamic provisioning

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 8% |
| **Time** | 7 min |

**Question:**

Create a StorageClass named `m1-local` that uses provisioner `rancher.io/local-path`, binds a volume only once a Pod uses the claim, and deletes the volume when the claim is released. Then, in namespace `m1-data`, create a PersistentVolumeClaim named `data` requesting `1Gi` with access mode `ReadWriteOnce` and that StorageClass, and a Deployment named `notes` (1 replica, image `nginx:1.27`) that mounts the claim at `/usr/share/nginx/html`. The claim must end up `Bound` and the Pod `Running`. The cluster's default StorageClass must stay as it is.

<details>
<summary>💡 Hints</summary>

- volumeBindingMode: WaitForFirstConsumer and reclaimPolicy: Delete on the StorageClass; no is-default-class annotation.
- A PVC with WaitForFirstConsumer stays Pending until the Deployment's Pod is scheduled; that is normal.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: m1-local
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: m1-data
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: m1-local
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes
  namespace: m1-data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notes
  template:
    metadata:
      labels:
        app: notes
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      volumes:
        - name: html
          persistentVolumeClaim:
            claimName: data
EOF
kubectl -n m1-data rollout status deploy/notes --timeout=120s
kubectl -n m1-data get pvc data
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — Three objects in one apply: the StorageClass, the claim and the Deployment.
- `kind: StorageClass` — Cluster-wide. It has no `is-default-class` annotation, so the default class stays as it is.
- `provisioner: rancher.io/local-path` — The lab's dynamic provisioner, which creates a folder on the node for each claim.
- `volumeBindingMode: WaitForFirstConsumer` — Binding waits until a Pod uses the claim.
- `reclaimPolicy: Delete` — The volume is deleted together with its claim.
- `storageClassName: m1-local` — The claim asks the new class for 1Gi, and the provisioner creates a PV for it.
- `mountPath: /usr/share/nginx/html` — Mounts the volume at nginx's web root.
- `claimName: data` — The volume is claim `data`.
- `rollout status deploy/notes` — The Pod being scheduled is what triggers provisioning, so once it is Running the claim is Bound.
- `get pvc data` — STATUS should read Bound.

**Notes:** Copy the StorageClass example from the docs and change three fields. Because of `WaitForFirstConsumer`, `kubectl get pvc` shows `Pending` until the Pod lands on a node; do not "fix" that. The question's last sentence is a trap for people who add `storageclass.kubernetes.io/is-default-class: "true"` out of habit.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-data
s="kubectl get sc m1-local -o jsonpath"
c="kubectl -n $ns get pvc data -o jsonpath"
d="kubectl -n $ns get deploy notes -o jsonpath"
kubectl get sc m1-local >/dev/null 2>&1 && p "storageclass m1-local exists" || f "storageclass m1-local exists"
[ "$($s='{.provisioner}' 2>/dev/null)" = "rancher.io/local-path" ] && p "provisioner rancher.io/local-path" || f "provisioner rancher.io/local-path"
[ "$($s='{.volumeBindingMode}' 2>/dev/null)" = "WaitForFirstConsumer" ] && p "WaitForFirstConsumer" || f "WaitForFirstConsumer"
[ "$($s='{.reclaimPolicy}' 2>/dev/null)" = "Delete" ] && p "reclaimPolicy Delete" || f "reclaimPolicy Delete"
[ "$($s='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" != "true" ] && p "m1-local is not the default" || f "m1-local is not the default"
[ "$(kubectl get sc standard -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" = "true" ] && p "standard is still the default" || f "standard is still the default"
[ "$($c='{.spec.storageClassName}' 2>/dev/null)" = "m1-local" ] && p "pvc uses m1-local" || f "pvc uses m1-local"
[ "$($c='{.spec.resources.requests.storage}' 2>/dev/null)" = "1Gi" ] && p "pvc requests 1Gi" || f "pvc requests 1Gi"
[ "$($c='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "pvc Bound" || f "pvc Bound"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "1" ] && p "notes pod available" || f "notes pod available"
[ -n "$($d='{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="data")].name}' 2>/dev/null)" ] && p "deployment mounts claim data" || f "deployment mounts claim data"
[ -n "$($d='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/usr/share/nginx/html")].name}' 2>/dev/null)" ] && p "mounted at /usr/share/nginx/html" || f "mounted at /usr/share/nginx/html"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 5: A gateway that will not start

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 8% |
| **Time** | 9 min |

**Question:**

The Pods of Deployment `gateway` in namespace `m1-api` restart over and over and never become ready. Save the error line the container prints right before it exits (the line containing `[emerg]`) to `/tmp/cka/m1-05-error.txt`. Then fix the problem so that both replicas are `Running` and Ready and stay that way, and `curl -s localhost/healthz` inside a gateway container returns `ok`. The server configuration must still come from the ConfigMap the Deployment already uses.

<details>
<summary>💡 Hints</summary>

- kubectl logs  -n m1-api (add --previous once the container has restarted) shows what nginx complained about.
- Fix the ConfigMap, then restart the rollout so new Pods load the corrected file straight away.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
line=""
for i in $(seq 1 20); do
  for pod in $(kubectl -n m1-api get pods -l app=gateway -o jsonpath='{.items[*].metadata.name}'); do
    line=$( { kubectl -n m1-api logs "$pod" --previous 2>/dev/null; kubectl -n m1-api logs "$pod" 2>/dev/null; } | grep -m1 '\[emerg\]' || true)
    [ -n "$line" ] && break 2
  done
  sleep 2
done
echo "$line" > /tmp/cka/m1-05-error.txt
cat /tmp/cka/m1-05-error.txt
kubectl -n m1-api get configmap gateway-conf -o yaml | sed 's/listn 80;/listen 80;/' | kubectl apply -f -
kubectl -n m1-api rollout restart deploy/gateway
kubectl -n m1-api rollout status deploy/gateway --timeout=120s
kubectl -n m1-api exec deploy/gateway -- curl -s localhost/healthz
```

**Explanation:**

- `for i in $(seq 1 20); do` — Tries for up to 40 seconds: a crash-looping container may be between attempts, with no log yet.
- `for pod in $(kubectl -n m1-api get pods` — Goes through each gateway Pod.
- `logs "$pod" --previous` — Reads the previous attempt's log and the current one, keeping the first line with `[emerg]` (`-m1`). The backslashes make the brackets literal.
- `break 2` — Leaves both loops as soon as a line is found.
- `echo "$line" > /tmp/cka/m1-05-error.txt` — Saves the error line to the answer file.
- `sed 's/listn 80;/listen 80;/'` — Fixes the typo in a copy of the ConfigMap and applies it back. On the exam, `kubectl edit cm gateway-conf -n m1-api` is quicker.
- `rollout restart deploy/gateway` — New Pods read the fixed file at once instead of waiting out the crash back-off.
- `rollout status deploy/gateway` — Waits until both new Pods are Ready.
- `exec deploy/gateway -- curl` — Runs curl inside one gateway container; it should print `ok`.

**Notes:** CrashLoopBackOff means the process exits; the log of the last attempt says why: *unknown directive "listn"*. `kubectl logs --previous` reads the attempt before the current one, which matters when the current container has just started. On the exam fix the typo with `kubectl edit cm gateway-conf -n m1-api`, then `kubectl rollout restart`: a ConfigMap change is not a template change, so the Deployment would otherwise keep waiting out the back-off.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-api
file=/tmp/cka/m1-05-error.txt
[ -s "$file" ] && p "error file exists" || f "error file exists"
[ -s "$file" ] && [ -z "$(grep -v 'emerg' "$file" 2>/dev/null | grep .)" ] && grep -q 'listn' "$file" 2>/dev/null && p "error file holds the [emerg] line about listn" || f "error file holds the [emerg] line about listn"
kubectl -n $ns get cm gateway-conf -o jsonpath='{.data.default\.conf}' 2>/dev/null | grep -q 'listn' && f "configmap typo fixed" || p "configmap typo fixed"
[ "$(kubectl -n $ns get deploy gateway -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}' 2>/dev/null)" = "gateway-conf" ] && p "deployment still uses configmap gateway-conf" || f "deployment still uses configmap gateway-conf"
for i in $(seq 1 20); do [ "$(kubectl -n $ns get pods -l app=gateway --no-headers 2>/dev/null | grep -vc Terminating)" = "2" ] && ! kubectl -n $ns get pods -l app=gateway --no-headers 2>/dev/null | grep -q Terminating && break; sleep 2; done
[ "$(kubectl -n $ns get deploy gateway -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
rev=$(kubectl -n $ns get deploy gateway -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
h=$(kubectl -n $ns get rs -l app=gateway -o jsonpath="{range .items[?(@.metadata.annotations.deployment\.kubernetes\.io/revision=='$rev')]}{.metadata.labels.pod-template-hash}{end}" 2>/dev/null)
rc() { kubectl -n $ns get pods -l app=gateway,pod-template-hash=$h -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[0].restartCount}/{.status.containerStatuses[0].ready} {end}' 2>/dev/null; }
stable=0
for i in 1 2 3; do
  r1=$(rc); sleep 6; r2=$(rc)
  [ -n "$h" ] && [ -n "$r1" ] && [ "$r1" = "$r2" ] && ! echo "$r2" | grep -q '/false' && { stable=1; break; }
done
[ $stable = 1 ] && p "pods ready and not restarting" || f "pods ready and not restarting"
[ "$(kubectl -n $ns exec deploy/gateway -- curl -s -m 3 localhost/healthz 2>/dev/null)" = "ok" ] && p "/healthz returns ok" || f "/healthz returns ok"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 6: Back up etcd

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 5 min |

**Question:**

Create a snapshot of the cluster's etcd database and save it on the control plane node as `/var/lib/etcd/m1-backup.db`. etcd listens on `https://127.0.0.1:2379`; its CA certificate, server certificate and key are in `/etc/kubernetes/pki/etcd/` (`ca.crt`, `server.crt`, `server.key`). *Lab note:* on the kind cluster `etcdctl` is only available inside the etcd Pod, so run it with `kubectl -n kube-system exec etcd-cka-control-plane -- etcdctl …`; on the exam you would `ssh` to the control plane node and run `etcdctl` there.

<details>
<summary>💡 Hints</summary>

- The flags are --endpoints, --cacert, --cert and --key; the docs page is 'Operating etcd clusters for Kubernetes', search 'snapshot save'.
- The etcd Pod mounts /var/lib/etcd from the node, so a file saved there inside the Pod is the file on the node.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n kube-system exec etcd-cka-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /var/lib/etcd/m1-backup.db
docker exec cka-control-plane ls -l /var/lib/etcd/m1-backup.db
```

**Explanation:**

- `snapshot save /var/lib/etcd/m1-backup.db` — Runs etcdctl inside the etcd Pod with the endpoint and the three certificate flags. `/var/lib/etcd` is shared with the node, so the file lands there. On the exam, run the same etcdctl on the node.
- `docker exec cka-control-plane ls -l` — Checks on the node that the file exists and is not empty.

**Notes:** On a kubeadm node the same command is `ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=… --cert=… --key=… snapshot save /var/lib/etcd/m1-backup.db` (the API version variable is harmless with etcd 3.5+). If you forget the certificate flags the command hangs or reports a TLS error. Read the paths from `/etc/kubernetes/manifests/etcd.yaml` instead of guessing. Restoring is the companion task: `etcdutl snapshot restore` into a new data directory and pointing the static Pod at it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
docker exec cka-control-plane test -s /var/lib/etcd/m1-backup.db 2>/dev/null && p "snapshot file exists on the node" || f "snapshot file exists on the node"
kubectl -n kube-system exec etcd-cka-control-plane -- etcdutl snapshot status /var/lib/etcd/m1-backup.db >/dev/null 2>&1 && p "file is a valid etcd snapshot" || f "file is a valid etcd snapshot"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 7: Restrict who can reach the cache

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 9 min |

**Question:**

In namespace `m1-cache` the Pods labeled `app=cache` listen on TCP `8080` behind Service `cache`. Create a NetworkPolicy named `cache-access` in that namespace so that only Pods labeled `app=api` in the same namespace can connect to the cache Pods on TCP port `8080`; every other inbound connection to them must be blocked. Do not restrict traffic leaving the cache Pods, and do not affect any other Pod in the namespace.

<details>
<summary>💡 Hints</summary>

- podSelector app=cache, policyTypes [Ingress], one ingress rule with a podSelector app=api and port 8080.
- Test from both sides: kubectl exec deploy/api -- wget -qO- -T 3 http://cache:8080/hostname should answer, the same from deploy/web should time out.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cache-access
  namespace: m1-cache
spec:
  podSelector:
    matchLabels:
      app: cache
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 8080
EOF
sleep 3
kubectl -n m1-cache exec deploy/api -- wget -qO- -T 3 http://cache:8080/hostname
kubectl -n m1-cache exec deploy/web -- wget -qO- -T 3 http://cache:8080/hostname || echo "web is blocked, as required"
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `podSelector:` — The Pods the policy protects: `app=cache` only, so other Pods are untouched.
- `policyTypes: ["Ingress"]` — Only inbound traffic is restricted; outbound stays open.
- `- from:` — The one allowed source: Pods labeled `app=api` in this namespace.
- `port: 8080` — `ports` belongs to the same rule as `from` (no dash before it), so api Pods may connect on TCP 8080 only.
- `sleep 3` — Gives the network plugin a moment to enforce the policy.
- `exec deploy/api -- wget` — From an api Pod: should print the cache Pod's name.
- `exec deploy/web -- wget` — From a web Pod: should time out after 3 seconds, and `||` prints the message instead.

**Notes:** Listing only `Ingress` in `policyTypes` keeps egress from the cache Pods untouched. A common mistake is a dash before `ports`, which turns it into a second rule (*anyone on 8080*); keep `from` and `ports` in the same list item. Another is creating the policy in the wrong namespace: `podSelector` only ever selects Pods in the policy's own namespace.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-cache
n="kubectl -n $ns get netpol cache-access -o jsonpath"
kubectl -n $ns get netpol cache-access >/dev/null 2>&1 && p "networkpolicy cache-access exists" || f "networkpolicy cache-access exists"
[ "$($n='{.spec.podSelector.matchLabels.app}' 2>/dev/null)" = "cache" ] && p "selects app=cache" || f "selects app=cache"
pt="$($n='{.spec.policyTypes[*]}' 2>/dev/null)"
case " $pt " in *" Ingress "*) p "policyTypes includes Ingress";; *) f "policyTypes includes Ingress";; esac
case " $pt " in *" Egress "*) f "egress left alone";; *) p "egress left alone";; esac
[ "$($n='{.spec.ingress[0].from[0].podSelector.matchLabels.app}' 2>/dev/null)" = "api" ] && p "allows from app=api" || f "allows from app=api"
[ "$($n='{.spec.ingress[0].ports[0].port}' 2>/dev/null)" = "8080" ] && p "port 8080" || f "port 8080"
ok=0
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec deploy/api -- wget -qO- -T 3 http://cache:8080/hostname 2>/dev/null)
  case "$out" in cache-*) ok=1; break;; esac
  sleep 2
done
[ $ok = 1 ] && p "api can reach cache" || f "api can reach cache"
kubectl -n $ns exec deploy/web -- wget -qO- -T 3 http://cache:8080/hostname >/dev/null 2>&1 && f "web is blocked" || p "web is blocked"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 8: Configure a worker from a Secret and a ConfigMap

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `m1-conf` create a Secret `db-credentials` with keys `username` = `app` and `password` = `s3cr3t-pw`, and a ConfigMap `app-config` with keys `LOG_LEVEL` = `debug` and `app.properties` = `mode=fast`. Then create a Deployment `worker` with 2 replicas, image `busybox:1.36`, command `sleep 3600`, whose container receives the environment variables `DB_USER` and `DB_PASS` from the Secret's `username` and `password` keys and has the ConfigMap mounted read-only at `/etc/app`.

<details>
<summary>💡 Hints</summary>

- kubectl create secret generic / kubectl create configmap with --from-literal, then kubectl create deployment --dry-run=client -o yaml and add env and volumes.
- Check with kubectl exec deploy/worker -- sh -c 'echo $DB_USER; cat /etc/app/LOG_LEVEL'.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m1-conf create secret generic db-credentials --from-literal=username=app --from-literal=password=s3cr3t-pw
kubectl -n m1-conf create configmap app-config --from-literal=LOG_LEVEL=debug --from-literal=app.properties=mode=fast
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: m1-conf
spec:
  replicas: 2
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: worker
          image: busybox:1.36
          command: ["sleep", "3600"]
          env:
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DB_PASS
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
          volumeMounts:
            - name: config
              mountPath: /etc/app
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: app-config
EOF
kubectl -n m1-conf rollout status deploy/worker --timeout=120s
kubectl -n m1-conf exec deploy/worker -- sh -c 'echo "$DB_USER"; cat /etc/app/LOG_LEVEL /etc/app/app.properties'
```

**Explanation:**

- `create secret generic db-credentials` — A Secret with two keys from literal values; kubectl encodes them.
- `create configmap app-config` — Two keys. In `app.properties=mode=fast`, only the first `=` separates key from value.
- `env:` — Each variable takes one Secret key through `valueFrom.secretKeyRef`: the Secret's name and the key.
- `readOnly: true` — Mounts the ConfigMap volume at `/etc/app` read-only. Each key becomes a file there.
- `name: app-config` — The volume's source is ConfigMap `app-config`.
- `rollout status deploy/worker` — Waits for both replicas.
- `exec deploy/worker -- sh -c` — Prints the variable and both files from inside a Pod. The single quotes stop your own shell from expanding `$DB_USER`; the container's shell does it.

**Notes:** The env block is where people lose time: it is `valueFrom.secretKeyRef` with `name` and `key`, one entry per variable (`envFrom` would import the keys under their own names, which is not what was asked). A ConfigMap volume creates one file per key, so `/etc/app/LOG_LEVEL` and `/etc/app/app.properties` appear automatically.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-conf
d="kubectl -n $ns get deploy worker -o jsonpath"
[ "$(kubectl -n $ns get secret db-credentials -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)" = "app" ] && p "secret username=app" || f "secret username=app"
[ "$(kubectl -n $ns get secret db-credentials -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)" = "s3cr3t-pw" ] && p "secret password set" || f "secret password set"
[ "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.LOG_LEVEL}' 2>/dev/null)" = "debug" ] && p "configmap LOG_LEVEL=debug" || f "configmap LOG_LEVEL=debug"
[ "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.app\.properties}' 2>/dev/null)" = "mode=fast" ] && p "configmap app.properties" || f "configmap app.properties"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "2 replicas" || f "2 replicas"
[ "$($d='{.spec.template.spec.containers[0].env[?(@.name=="DB_USER")].valueFrom.secretKeyRef.key}' 2>/dev/null)" = "username" ] && p "DB_USER from secret key username" || f "DB_USER from secret key username"
[ "$($d='{.spec.template.spec.containers[0].env[?(@.name=="DB_PASS")].valueFrom.secretKeyRef.name}' 2>/dev/null)" = "db-credentials" ] && p "DB_PASS from secret db-credentials" || f "DB_PASS from secret db-credentials"
[ "$($d='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/etc/app")].readOnly}' 2>/dev/null)" = "true" ] && p "/etc/app mounted read-only" || f "/etc/app mounted read-only"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
[ "$(kubectl -n $ns exec deploy/worker -- sh -c 'echo "$DB_USER"' 2>/dev/null)" = "app" ] && p "DB_USER resolves to app in the container" || f "DB_USER resolves to app in the container"
[ "$(kubectl -n $ns exec deploy/worker -- cat /etc/app/LOG_LEVEL 2>/dev/null)" = "debug" ] && p "/etc/app/LOG_LEVEL readable" || f "/etc/app/LOG_LEVEL readable"
[ "$(kubectl -n $ns exec deploy/worker -- cat /etc/app/app.properties 2>/dev/null)" = "mode=fast" ] && p "/etc/app/app.properties readable" || f "/etc/app/app.properties readable"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 9: Production overlay with Kustomize

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

A Kustomize base for the `web` application is in `/tmp/cka/m1-kustomize/base` (on the exam such files live under `/opt/course/…`). Without changing the base, create an overlay in `/tmp/cka/m1-kustomize/overlays/prod` that deploys it into namespace `m1-kz` with the name prefix `prod-`, **3** replicas, image `nginx:1.27` and the label `env=prod` on every resource it creates. Apply the overlay to the cluster; all replicas must be available.

<details>
<summary>💡 Hints</summary>

- The overlay's kustomization.yaml lists ../../base under resources and uses namespace, namePrefix, replicas, images and labels.
- kubectl kustomize  prints the result without applying; kubectl apply -k  applies it.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka/m1-kustomize/overlays/prod
cat > /tmp/cka/m1-kustomize/overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m1-kz
namePrefix: prod-
resources:
  - ../../base
replicas:
  - name: web
    count: 3
images:
  - name: nginx
    newTag: "1.27"
labels:
  - pairs:
      env: prod
EOF
kubectl kustomize /tmp/cka/m1-kustomize/overlays/prod
kubectl apply -k /tmp/cka/m1-kustomize/overlays/prod
kubectl -n m1-kz rollout status deploy/prod-web --timeout=120s
```

**Explanation:**

- `mkdir -p /tmp/cka/m1-kustomize/overlays/prod` — Creates the overlay folder beside the base.
- `cat > /tmp/cka/m1-kustomize/overlays/prod/kustomization.yaml` — Writes the overlay's kustomization file with a heredoc.
- `namespace: m1-kz` — Every resource goes into `m1-kz`.
- `namePrefix: prod-` — `web` becomes `prod-web`, for the Deployment and the Service.
- `- ../../base` — The base, two folders up, used unchanged.
- `replicas:` — Sets the replica count of Deployment `web`, named as in the base, before the prefix.
- `newTag: "1.27"` — Changes the tag of image `nginx`. Quote it: unquoted, YAML reads 1.27 as a number and kustomize rejects it.
- `labels:` — Adds `env: prod` to every resource's metadata. Without `includeSelectors`, selectors stay as they are.
- `kubectl kustomize /tmp` — Prints the result so you can check names, namespace and labels before applying.
- `kubectl apply -k` — Builds the overlay and applies it.
- `rollout status deploy/prod-web` — The Deployment's new name, waited on until all 3 replicas are available.

**Notes:** The `replicas` and `images` transformers refer to the base names (`web`, `nginx`), not the prefixed ones. `labels` without `includeSelectors` only touches metadata, which keeps selectors stable; the older `commonLabels` also rewrites selectors and still works, with a deprecation warning. Run `kubectl kustomize` first and read the output: it is the cheapest way to catch an indentation mistake.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-kz
ov=/tmp/cka/m1-kustomize/overlays/prod
d="kubectl -n $ns get deploy prod-web -o jsonpath"
[ -f $ov/kustomization.yaml ] || [ -f $ov/kustomization.yml ] || [ -f $ov/Kustomization ] && p "overlay kustomization exists" || f "overlay kustomization exists"
kubectl kustomize $ov 2>/dev/null | grep -q 'name: prod-web' && p "overlay renders prod-web" || f "overlay renders prod-web"
grep -q 'image: nginx:1.26' /tmp/cka/m1-kustomize/base/deployment.yaml 2>/dev/null && grep -q 'replicas: 1' /tmp/cka/m1-kustomize/base/deployment.yaml 2>/dev/null && p "base left unchanged" || f "base left unchanged"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "prod-web replicas 3" || f "prod-web replicas 3"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "prod-web image nginx:1.27" || f "prod-web image nginx:1.27"
[ "$($d='{.metadata.labels.env}' 2>/dev/null)" = "prod" ] && p "deployment labeled env=prod" || f "deployment labeled env=prod"
[ "$(kubectl -n $ns get svc prod-web -o jsonpath='{.metadata.labels.env}' 2>/dev/null)" = "prod" ] && p "service prod-web labeled env=prod" || f "service prod-web labeled env=prod"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 10: Install a chart with Helm

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Add the Helm repository `https://stefanprodan.github.io/podinfo` under the name `podinfo` and install chart `podinfo/podinfo`, chart version `6.9.1`, as release `m1-podinfo` into a new namespace `m1-helm`. The release must run **2** replicas (chart value `replicaCount`) and all its Pods must be Ready.

<details>
<summary>💡 Hints</summary>

- helm repo add, helm repo update, then helm install with --version, --namespace, --create-namespace and --set replicaCount=2.
- helm list -n m1-helm and kubectl get deploy -n m1-helm confirm the result.

</details>

<details>
<summary>✅ Solution</summary>

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo --force-update
helm repo update podinfo
helm install m1-podinfo podinfo/podinfo --version 6.9.1 --namespace m1-helm --create-namespace --set replicaCount=2 --wait --timeout 5m
helm -n m1-helm list
```

**Explanation:**

- `helm repo add podinfo` — Registers the repository as `podinfo`. `--force-update` avoids an error if the name already exists.
- `helm repo update podinfo` — Fetches the repository's current chart index.
- `helm install m1-podinfo` — Installs chart version 6.9.1 as release `m1-podinfo` into a new namespace, with 2 replicas. `--wait` returns only when the Pods are Ready, or after 5 minutes.
- `helm -n m1-helm list` — Shows the release, its chart version and status deployed.

**Notes:** `helm search repo podinfo --versions` lists the chart versions if the question names one. `--create-namespace` saves a command; `--wait` blocks until the Pods are Ready so you can move on with confidence. If a value name is unknown, `helm show values podinfo/podinfo --version 6.9.1 | less` is the reference; helm.sh/docs is allowed on the exam.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-helm
hl=$(helm -n $ns list -o json 2>/dev/null)
echo "$hl" | grep -q '"name":"m1-podinfo"' && p "release m1-podinfo listed" || f "release m1-podinfo listed"
echo "$hl" | grep -q '"chart":"podinfo-6.9.1"' && p "chart podinfo-6.9.1" || f "chart podinfo-6.9.1"
echo "$hl" | grep -q '"status":"deployed"' && p "status deployed" || f "status deployed"
[ "$(kubectl -n $ns get deploy m1-podinfo -o jsonpath='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "2 replicas" || f "2 replicas"
[ "$(kubectl -n $ns get deploy m1-podinfo -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 11: Pods stuck Pending on a dedicated node

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 8% |
| **Time** | 6 min |

**Question:**

Deployment `edge-agent` in namespace `m1-edge` is meant to run only on the node labeled `m1-edge=true`, but both of its Pods are `Pending`. The node is configured deliberately and must not be changed. Fix the Deployment so that both Pods are `Running` on that node.

<details>
<summary>💡 Hints</summary>

- kubectl describe pod on a Pending Pod: the scheduler message tells you about an untolerated taint; kubectl describe node cka-worker2 shows it.
- Add a toleration for that taint to the Pod template and keep the nodeSelector.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m1-edge describe pods -l app=edge-agent | grep -i 'taint' | head -2 || true
kubectl get node cka-worker2 -o jsonpath='{.spec.taints}'; echo
kubectl -n m1-edge patch deploy edge-agent --type=json -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"m1-edge","operator":"Equal","value":"true","effect":"NoSchedule"}]}]'
kubectl -n m1-edge rollout status deploy/edge-agent --timeout=120s
kubectl -n m1-edge get pods -o wide
```

**Explanation:**

- `describe pods -l app=edge-agent` — Shows the scheduler's FailedScheduling message, which names the taint the Pods do not tolerate.
- `get node cka-worker2 -o jsonpath` — Prints the node's taints as JSON: key `m1-edge`, value `true`, effect NoSchedule. The `echo` adds a newline.
- `patch deploy edge-agent --type=json` — A JSON patch adds a matching toleration to the Pod template. On the exam, adding the four fields with `kubectl edit` is just as good.
- `rollout status deploy/edge-agent` — New Pods with the toleration replace the Pending ones.
- `get pods -o wide` — The NODE column should show `cka-worker2` for both.

**Notes:** The scheduler event reads *1 node(s) had untolerated taint {m1-edge: true}*. Removing the taint would also get the Pods running but breaks the question's rule, and graders check the node too. A toleration with `operator: Exists` on the key is equally valid. Keep the `nodeSelector`; the toleration only permits the node, the selector is what pins to it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-edge
d="kubectl -n $ns get deploy edge-agent -o jsonpath"
[ "$(kubectl get node cka-worker2 -o jsonpath='{.spec.taints[?(@.key=="m1-edge")].effect}' 2>/dev/null)" = "NoSchedule" ] && p "taint still on cka-worker2" || f "taint still on cka-worker2"
[ "$($d='{.spec.template.spec.nodeSelector.m1-edge}' 2>/dev/null)" = "true" ] && p "nodeSelector kept" || f "nodeSelector kept"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
n=$(kubectl -n $ns get pods -l app=edge-agent -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null | xargs -n1 2>/dev/null | grep -c '^cka-worker2$')
[ "$n" = "2" ] && p "both pods on cka-worker2" || f "both pods on cka-worker2 (got $n)"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 12: Route traffic with an HTTPRoute

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

A Gateway named `m1-gateway` exists in namespace `m1-gw`. Create an HTTPRoute named `store` in that namespace, attached to the Gateway, for hostname `store.m1.local`, that sends requests whose path starts with `/api` to Service `api` on port `8080` and every other request to Service `web` on port `80`. The lab has no Gateway controller, so only the HTTPRoute object is graded.

<details>
<summary>💡 Hints</summary>

- parentRefs → the Gateway name; hostnames; two rules, each with a PathPrefix match and a backendRefs entry (name + port).
- The Gateway API docs on kubernetes.io ('Gateway API' concepts page) include an HTTPRoute example you can adapt.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store
  namespace: m1-gw
spec:
  parentRefs:
    - name: m1-gateway
  hostnames:
    - store.m1.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
EOF
kubectl -n m1-gw get httproute store
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `parentRefs:` — Attaches the route to Gateway `m1-gateway` in the same namespace.
- `- store.m1.local` — The host this route serves; it fits the listener's `*.m1.local`.
- `value: /api` — Rule one: paths starting with `/api` go to Service `api` on port 8080.
- `value: /` — Rule two: everything else to `web` on port 80. The longest matching prefix wins, so `/api` requests never land here.
- `get httproute store` — Confirms the object exists. With no controller, nothing marks it accepted.

**Notes:** The route is namespaced; `parentRefs` without a namespace means the Gateway is in the same one. Order of rules does not matter for matching (the most specific path wins), but keep the catch-all `/` rule explicit so the grader can read it. With a real controller the route's `status.parents` would show `Accepted`; here it stays empty.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-gw
r="kubectl -n $ns get httproute store -o jsonpath"
kubectl -n $ns get httproute store >/dev/null 2>&1 && p "httproute store exists" || f "httproute store exists"
[ "$($r='{.spec.parentRefs[0].name}' 2>/dev/null)" = "m1-gateway" ] && p "attached to m1-gateway" || f "attached to m1-gateway"
case " $($r='{.spec.hostnames[*]}' 2>/dev/null) " in *" store.m1.local "*) p "hostname store.m1.local";; *) f "hostname store.m1.local";; esac
[ "$($r='{.spec.rules[?(@.backendRefs[0].name=="api")].matches[0].path.value}' 2>/dev/null)" = "/api" ] && p "/api goes to api" || f "/api goes to api"
[ "$($r='{.spec.rules[?(@.backendRefs[0].name=="api")].matches[0].path.type}' 2>/dev/null)" = "PathPrefix" ] && p "/api is a PathPrefix match" || f "/api is a PathPrefix match"
[ "$($r='{.spec.rules[?(@.backendRefs[0].name=="api")].backendRefs[0].port}' 2>/dev/null)" = "8080" ] && p "api port 8080" || f "api port 8080"
wv="$($r='{.spec.rules[?(@.backendRefs[0].name=="web")].matches[0].path.value}' 2>/dev/null)"
{ [ "$wv" = "/" ] || [ -z "$wv" ]; } && [ "$($r='{.spec.rules[?(@.backendRefs[0].name=="web")].backendRefs[0].port}' 2>/dev/null)" = "80" ] && p "everything else goes to web:80" || f "everything else goes to web:80"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 13: Find the busiest Pod

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 6% |
| **Time** | 4 min |

**Question:**

Using the cluster's resource metrics, find the Pod in namespace `m1-top` that is consuming the most CPU and write its name to `/tmp/cka/m1-13-pod.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl top pod -n m1-top --sort-by=cpu puts the answer on the first line.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n m1-top top pod --sort-by=cpu
kubectl -n m1-top top pod --sort-by=cpu --no-headers | awk 'NR==1 {print $1}' > /tmp/cka/m1-13-pod.txt
cat /tmp/cka/m1-13-pod.txt
```

**Explanation:**

- `kubectl -n m1-top top pod --sort-by=cpu` — Shows each Pod's current CPU and memory from metrics-server, highest CPU first.
- `awk 'NR==1 {print $1}'` — `--no-headers` drops the header row; awk prints the first column of the first line, the busiest Pod's name.
- `cat /tmp/cka/m1-13-pod.txt` — Checks the file holds only the name.

**Notes:** `kubectl top` needs metrics-server and shows nothing for Pods younger than about 30 seconds; if the list is empty, wait and retry rather than guessing. `--sort-by=cpu` (or `memory`) sorts descending. Write only the name to the file.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
[ "$(tr -d '[:space:]' < /tmp/cka/m1-13-pod.txt 2>/dev/null)" = "indexer" ] && p "answer file names indexer" || f "answer file names indexer"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 14: Autoscale an API Deployment

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 5 min |

**Question:**

Deployment `api` in namespace `m1-auto` has no resource requests. Set a CPU request of `100m` and a CPU limit of `250m` on its container, then create a HorizontalPodAutoscaler named `api` for the Deployment with a minimum of **2** and a maximum of **6** replicas that targets **60%** average CPU utilization.

<details>
<summary>💡 Hints</summary>

- kubectl set resources deploy/api --requests=cpu=100m --limits=cpu=250m, then kubectl autoscale deploy/api --min=2 --max=6 --cpu=60%.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m1-auto set resources deploy/api --requests=cpu=100m --limits=cpu=250m
kubectl -n m1-auto rollout status deploy/api --timeout=120s
kubectl -n m1-auto autoscale deploy/api --name=api --min=2 --max=6 --cpu=60%
kubectl -n m1-auto get hpa api
```

**Explanation:**

- `set resources deploy/api` — Adds the CPU request and limit to the container, which rolls out new Pods.
- `rollout status deploy/api` — Waits for the new Pods.
- `autoscale deploy/api --name=api` — Creates HPA `api`: 2 to 6 replicas at 60% of the 100m request. `--cpu=60%` replaces the deprecated `--cpu-percent=60`, which still works but prints a warning.
- `get hpa api` — TARGETS shows usage against 60%; it reads unknown until the first metrics arrive.

**Notes:** An HPA on CPU utilization needs a CPU request to compute the percentage, which is why the question starts there. `kubectl autoscale` creates an `autoscaling/v2` object with a `Utilization` target; writing the YAML by hand gives the same result. The HPA raises the Deployment to 2 replicas on its first sync even before metrics arrive.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-auto
d="kubectl -n $ns get deploy api -o jsonpath"
h="kubectl -n $ns get hpa api -o jsonpath"
[ "$($d='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)" = "100m" ] && p "cpu request 100m" || f "cpu request 100m"
[ "$($d='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null)" = "250m" ] && p "cpu limit 250m" || f "cpu limit 250m"
kubectl -n $ns get hpa api >/dev/null 2>&1 && p "hpa api exists" || f "hpa api exists"
[ "$($h='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}' 2>/dev/null)" = "Deployment/api" ] && p "targets Deployment/api" || f "targets Deployment/api"
[ "$($h='{.spec.minReplicas}' 2>/dev/null)" = "2" ] && p "minReplicas 2" || f "minReplicas 2"
[ "$($h='{.spec.maxReplicas}' 2>/dev/null)" = "6" ] && p "maxReplicas 6" || f "maxReplicas 6"
[ "$($h='{.spec.metrics[0].resource.name}' 2>/dev/null)" = "cpu" ] && p "metric cpu" || f "metric cpu"
[ "$($h='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null)" = "60" ] && p "target 60% utilization" || f "target 60% utilization"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 15: Resolve a Service through cluster DNS

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 5 min |

**Question:**

A Service named `ledger` exists in namespace `m1-dns`. From inside Pod `lookup` in the same namespace, resolve the Service's fully qualified DNS name with `nslookup` and save the complete command output to `/tmp/cka/m1-15-dns.txt`. Then write the Service's ClusterIP, and nothing else, to `/tmp/cka/m1-15-ip.txt`.

<details>
<summary>💡 Hints</summary>

- The FQDN of a Service is ..svc.cluster.local; kubectl exec lookup -n m1-dns -- nslookup ledger.m1-dns.svc.cluster.local.
- kubectl get svc ledger -n m1-dns -o jsonpath='{.spec.clusterIP}' gives the IP without decoration.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n m1-dns exec lookup -- nslookup ledger.m1-dns.svc.cluster.local > /tmp/cka/m1-15-dns.txt
kubectl -n m1-dns get svc ledger -o jsonpath='{.spec.clusterIP}' > /tmp/cka/m1-15-ip.txt
cat /tmp/cka/m1-15-dns.txt /tmp/cka/m1-15-ip.txt; echo
```

**Explanation:**

- `nslookup ledger.m1-dns.svc.cluster.local >` — Runs nslookup inside the Pod with the full name, `..svc.cluster.local`. The `>` runs on your machine, so the output is saved locally.
- `jsonpath='{.spec.clusterIP}' >` — Writes only the ClusterIP, without a newline or headers.
- `cat /tmp/cka/m1-15-dns.txt` — Shows both files; `echo` adds the newline the IP file lacks.

**Notes:** Busybox's `nslookup` prints the DNS server (the `kube-dns` ClusterIP) and the answer. Looking up the short name `ledger` also works because of the Pod's search list, but it prints NXDOMAIN noise for the other search domains and exits non-zero, so use the FQDN when the output is graded. A Service with no endpoints still gets a ClusterIP and a DNS record.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-dns
ip=$(kubectl -n $ns get svc ledger -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
grep -q 'ledger.m1-dns.svc.cluster.local' /tmp/cka/m1-15-dns.txt 2>/dev/null && p "lookup output names the FQDN" || f "lookup output names the FQDN"
[ -n "$ip" ] && grep -q "$ip" /tmp/cka/m1-15-dns.txt 2>/dev/null && p "lookup output contains the ClusterIP" || f "lookup output contains the ClusterIP"
[ -n "$ip" ] && [ "$(tr -d '[:space:]' < /tmp/cka/m1-15-ip.txt 2>/dev/null)" = "$ip" ] && p "ip file holds the ClusterIP" || f "ip file holds the ClusterIP"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 16: Requests to a Service are refused

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 8% |
| **Time** | 6 min |

**Question:**

In namespace `m1-front`, clients cannot use the application behind Service `front` (port `80`): connections are refused, although the Deployment `front` is healthy. Find and fix the problem on the Service so that `wget -qO- http://front/hostname` run from a Pod of Deployment `client` in the same namespace returns the name of a `front` Pod. Do not change the Deployment `front`.

<details>
<summary>💡 Hints</summary>

- kubectl get endpointslices -n m1-front shows the endpoints and the port they point at; compare it with the container port in kubectl describe deploy front.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m1-front get endpointslices -l kubernetes.io/service-name=front
kubectl -n m1-front patch svc front -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}'
sleep 3
kubectl -n m1-front exec deploy/client -- wget -qO- -T 5 http://front/hostname
```

**Explanation:**

- `get endpointslices` — Endpoints exist, but they point at port 80, where agnhost does not listen.
- `patch svc front` — Sets `targetPort` to the container's 8080 and keeps `port` 80. Service ports merge by their `port` number, so the existing entry is updated.
- `exec deploy/client -- wget` — From a client Pod: should print a front Pod's name.

**Notes:** *Connection refused* with endpoints present means the Service reaches the Pods but on a port nothing listens on: `targetPort` 80 does not match container port 8080. A selector mismatch would show *no endpoints* and time out instead. On the exam use `kubectl edit svc front`; the patch above is the non-interactive version.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-front
[ "$(kubectl -n $ns get svc front -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)" = "8080" ] && p "targetPort 8080" || f "targetPort 8080"
[ "$(kubectl -n $ns get svc front -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "port still 80" || f "port still 80"
eps=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=front -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null | wc -w | tr -d ' ')
[ "$eps" = "2" ] && p "2 endpoints" || f "2 endpoints (got $eps)"
[ "$(kubectl -n $ns get deploy front -o jsonpath='{.spec.template.spec.containers[0].args[1]}' 2>/dev/null)" = "--http-port=8080" ] && p "deployment front untouched" || f "deployment front untouched"
ok=0
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec deploy/client -- wget -qO- -T 3 http://front/hostname 2>/dev/null)
  case "$out" in front-*) ok=1; break;; esac
  sleep 2
done
[ $ok = 1 ] && p "client reaches http://front/hostname" || f "client reaches http://front/hostname"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 17: Node maintenance window

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Node `cka-worker` needs a maintenance reboot. Mark it unschedulable and evict every workload running on it. DaemonSet-managed Pods may stay, data in `emptyDir` volumes may be lost, and standalone Pods that would block the eviction may be deleted. Then, treating the maintenance as finished, put the node back into service. The Deployment `jobs` in namespace `m1-maint` must end with all 4 replicas available.

<details>
<summary>💡 Hints</summary>

- kubectl drain refuses to continue until you pass the right flags; each error message names the one you are missing.
- kubectl uncordon is the opposite of cordon; drain does not undo itself.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=cka-worker
kubectl drain cka-worker --ignore-daemonsets --delete-emptydir-data --force --timeout=180s
kubectl get pods -A -o wide --field-selector spec.nodeName=cka-worker
kubectl uncordon cka-worker
kubectl -n m1-maint rollout status deploy/jobs --timeout=180s
```

**Explanation:**

- `get pods -A -o wide --field-selector spec.nodeName=cka-worker` — Lists everything on the node before the drain, so you know what will move.
- `kubectl drain cka-worker` — Cordons the node and evicts its Pods. `--ignore-daemonsets` leaves DaemonSet Pods, `--delete-emptydir-data` accepts losing emptyDir data, `--force` deletes the unmanaged Pod `scratch`.
- `get pods -A -o wide` — Afterwards only DaemonSet Pods should remain on the node.
- `kubectl uncordon cka-worker` — Ends the maintenance: the node accepts new Pods again.
- `rollout status deploy/jobs` — Waits until the evicted replicas run elsewhere and all 4 are available.

**Notes:** `drain` cordons first, then evicts. It stops without `--ignore-daemonsets` when DaemonSet Pods are present (Calico and kube-proxy always are), without `--delete-emptydir-data` for Pods with `emptyDir` volumes, and without `--force` for Pods no controller manages (those are deleted and never come back: here that is `scratch`). Eviction respects PodDisruptionBudgets, so a drain that hangs usually means a PDB. Graders check the node's `spec.unschedulable` and what is left on it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m1-maint
[ "$(kubectl get node cka-worker -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ] && p "cka-worker schedulable again" || f "cka-worker schedulable again"
kubectl -n $ns get pod scratch >/dev/null 2>&1 && f "standalone pod scratch evicted" || p "standalone pod scratch evicted"
[ "$(kubectl -n $ns get deploy jobs -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "4" ] && p "jobs has 4 available" || f "jobs has 4 available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka)*
