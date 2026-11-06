# Kustomize: bases, overlays and patches

> **Module 1** · Lesson 1.9 · 35 minutes

Adjust plain YAML for each environment without copying it: a base holds the manifests and an overlay lists the changes.

## Learning Objectives

- You can write an overlay that changes the namespace, name prefix, labels, image tag and replica count, without touching the base.
- You can change any field with a patch, and choose between a strategic merge patch and a JSON 6902 patch.
- You can generate a ConfigMap, explain the hash in its name, and build, compare, apply and delete with -k.


**Kustomize** lets you keep one set of YAML files and adjust it for each environment. Example: your Django app runs 1 replica in `dev` and 3 in `prod`, each in its own namespace. Instead of two copies of every file, you keep one **base**. Then you write a small **overlay** for each environment that lists only the differences.

Kustomize is built into kubectl, so it is already in the exam terminal. There are no templates: the base is plain YAML that works on its own. Exam tasks usually give you a base and ask for an overlay, or give you an overlay that does not build.

**How an overlay becomes objects**

*The overlay points at the base and lists its changes. kubectl builds the final YAML and applies it. The base files never change.*

`Base` — plain YAML, shared by every environment (`base/`) → `Overlay` — the changes for one environment (`overlays/prod/`) → `kubectl apply -k` — builds the result and applies it → `Live objects` — prod-api in shop-prod, 3 replicas

## A base and an overlay

The base and each overlay are folders, each with a file called `kustomization.yaml`. The base's file just lists its manifests. An overlay's file points at the base and says what to change. Here is a production overlay:

**app/overlays/prod/kustomization.yaml**

```yaml
# Layout:
#   app/base/kustomization.yaml            resources: [deployment.yaml, service.yaml]
#   app/overlays/dev/kustomization.yaml    resources: [../../base]
#   app/overlays/prod/kustomization.yaml   this file
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - namespace.yaml            # apiVersion: v1, kind: Namespace, metadata.name: shop-prod
namespace: shop-prod
namePrefix: prod-
labels:
  - pairs:
      env: prod
    includeTemplates: true     # label the Pods too, leave selectors alone
images:
  - name: nginx                # every container whose image is nginx:<anything>
    newTag: "1.27"
replicas:
  - name: api                  # the base name, before the prefix
    count: 3
```

<details>
<summary>Line-by-line explanation</summary>

- `# Layout:` — One base holds the plain manifests; each environment gets an overlay folder that points back at it. Overlays never copy the base files.
- `apiVersion: kustomize.config.k8s.io/v1beta1` — This file is read by Kustomize and never sent to the cluster, so its `apiVersion` and `kind` are Kustomize's own.
- `- ../../base` — `../..` climbs two folders, from `overlays/prod` back to `app`, then into `base`. Pointing at a folder pulls in that folder's whole kustomization.
- `- namespace.yaml` — A file in this folder holding the Namespace object. It is what actually creates `shop-prod`; the `namespace:` field below only sets it on objects.
- `namespace: shop-prod` — Sets `metadata.namespace` on every namespaced object, overriding whatever the base had.
- `namePrefix: prod-` — Puts `prod-` in front of object names, so `api` becomes `prod-api`, and updates the references Kustomize knows about. The Namespace keeps its name.
- `labels:` — Adds labels. Each list item holds the labels under `pairs`, plus options saying where else they go.
- `includeTemplates: true` — Also puts `env: prod` on the Pod template. Selectors are left alone, which matters because a Deployment's selector cannot change after it is created.
- `images:` — Rewrites container images without editing the base.
- `newTag:` — Swaps only the tag. Quoting keeps it a string; unquoted, YAML reads `1.27` as a number.
- `replicas:` — Sets a replica count by object name, without writing a patch.

</details>

Always look at the result before you apply it. `-k` takes a kustomization folder, where `-f` takes a file:

**Render, compare, apply, remove**

```bash
kubectl kustomize app/overlays/prod                      # print the result, change nothing
kubectl kustomize app/overlays/prod | grep -nE 'name:|namespace:|image:|replicas:'
kubectl diff -k app/overlays/prod                         # what would change on the live cluster
kubectl apply -k app/overlays/prod
kubectl get -k app/overlays/prod                          # the live objects this overlay produces
kubectl delete -k app/overlays/prod
kubectl version --client                                  # also prints the bundled Kustomize version
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl kustomize app/overlays/prod  ` — Builds the overlay and prints the final YAML. Kustomize is built into kubectl, so no extra tool is needed on the exam.
- `| grep -nE` — Filters the output to the lines you usually check: names, namespaces, images and replica counts.
- `kubectl diff -k` — `-k` means a kustomization folder, where `-f` means a file. `diff` shows line by line how the live objects would change.
- `kubectl apply -k` — Builds the overlay and applies the result in one step, like `apply -f` on the rendered YAML.
- `kubectl get -k` — Looks up the live objects by the names the overlay gives them, prefix included.
- `kubectl delete -k` — Deletes every object the overlay builds. That includes the Namespace, and with it everything inside.
- `kubectl version --client` — Prints kubectl's own version and the Kustomize version built into it, without contacting the cluster.

</details>

## The fields you will use most

| Field | What it does | Watch out for |
| --- | --- | --- |
| `resources` | Lists the files and folders to include | The output puts Namespaces first, so one `apply -k` can create a namespace and fill it |
| `namespace` | Sets the namespace on every object | It does not create the Namespace. List a Namespace file under `resources` for that. |
| `namePrefix`, `nameSuffix` | Adds text to every name, and fixes references to those names | Namespace names and label selectors stay as they are |
| `labels` | Adds labels. `includeTemplates: true` labels the Pods too. | `includeSelectors: true` also changes selectors, which an existing Deployment cannot accept |
| `images` | Changes an image's name or tag | Match the image name without its tag, and quote tags such as `"1.27"` |
| `replicas` | Sets the replica count by object name | Use the base name, not the prefixed one |
| `patches` | Changes any other field (see below) | Replaces the old `patchesStrategicMerge` and `patchesJson6902` |
| `configMapGenerator` | Builds a ConfigMap with a hash in its name | Only references Kustomize knows about get the new name |

## Patches: change any field

When no simple field does the job, write a **patch**. Kustomize knows two kinds, and both go in the same `patches` list.

| Kind | What you write | Good for |
| --- | --- | --- |
| **Strategic merge patch** | A small piece of the object, with only the fields to change | Adding or changing fields, such as a memory limit or `envFrom` on one container |
| **JSON 6902 patch** | A list of steps. Each has an `op` (`add`, `replace` or `remove`), a `path` such as `/spec/type`, and a `value`. | Removing a field, or changing one list item by its position |

In a strategic merge patch, lists such as `containers` are merged by each item's `name`. So you can change one container without repeating the others. A JSON 6902 patch names no object, so it needs a `target` to say which one.

**In kustomization.yaml: one patch of each kind**

```yaml
patches:
  # Strategic merge: name the object, write only what changes
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: api
      spec:
        template:
          spec:
            containers:
              - name: api                 # merged by container name
                resources:
                  limits:
                    memory: 256Mi
  # JSON 6902: operations need a target
  - target:
      kind: Service
      name: api
    patch: |-
      - op: replace
        path: /spec/type
        value: NodePort
      - op: add
        path: /metadata/labels/exposed
        value: "true"
```

<details>
<summary>Line-by-line explanation</summary>

- `- patch: |-` — Every patch goes in the one `patches` list. `|-` starts a block of text: everything indented below is the patch, kept as written, without a trailing newline.
- `kind: Deployment` — `apiVersion`, `kind` and `metadata.name` identify the object to patch, so this style needs no `target`.
- `containers:` — Kubernetes merges the `containers` list by each container's `name`. This adds a memory limit to `api` and leaves its image, ports and any other containers alone.
- `- target:` — A JSON 6902 patch names no object of its own, so `target` picks what it applies to: here the Service `api`.
- `- op: replace` — Each operation has an `op`, a `path` written like a folder path into the object, and a `value`. This one sets `spec.type` to `NodePort`.
- `- op: add` — `add` creates a field, here the label `exposed`. The value is quoted because label values must be strings.

</details>

## Generated ConfigMaps

Kustomize can also write ConfigMaps for you. You list the keys; it builds the ConfigMap and adds a hash of the content to its name, such as `api-config-`. `secretGenerator` builds Secrets the same way.

**In kustomization.yaml: a ConfigMap generator**

```yaml
configMapGenerator:
  - name: api-config
    literals:
      - MODE=production
      - CACHE_TTL=300
```

<details>
<summary>Line-by-line explanation</summary>

- `configMapGenerator:` — Kustomize builds these ConfigMaps for you, so you never write their YAML. Each one gets a hash of its content added to its name.
- `literals:` — Each `KEY=value` line becomes one key, like `kubectl create configmap --from-literal`.

</details>

Kustomize rewrites every reference it knows to the hashed name: `envFrom`, `valueFrom` and volumes. (`envFrom` loads every key of a ConfigMap as environment variables; [ConfigMaps and Secrets](/cka/workloads/configmaps-and-secrets) teaches it.) The hash is what makes a settings change roll out:

**Why the name has a hash**

*The old ConfigMap stays behind until you delete it.*

`You change a value` — in kustomization.yaml (`MODE=debug`) → `New hash, new name` — a new ConfigMap (`api-config-<new hash>`) → `Pod template changes` — it now points at the new name → `New Pods` — the Deployment rolls out

> [!WARNING] **Old field names still build**
> `commonLabels`, `patchesStrategicMerge`, `patchesJson6902`, `bases` and `vars` still work but print a deprecation warning, so use `labels`, `patches` and `resources` in new overlays.

> [!IMPORTANT] **What the grader reads**
> The grader reads the live objects, and sometimes your overlay files. Build before you apply: a wrong namespace, a missing prefix or an old tag shows up in `kubectl kustomize` output in seconds. Never edit the base when the question says overlay. If `apply -k` fails with `field is immutable` on `spec.selector`, a label reached an existing Deployment's selector: use `labels` without `includeSelectors`.

## 📝 Key Takeaways

- The base is plain YAML. The overlay points at the base and lists the changes. Never edit the base.
- `namespace:` sets the namespace on objects but does not create it. List a Namespace file under `resources` to create it.
- `images` and `replicas` use the base names (`nginx`, `web`), not the prefixed ones.
- A strategic merge patch is a small piece of the object. A JSON 6902 patch is a list of steps with an `op` and a `path`, and needs a `target`.
- `kubectl kustomize ` shows the result, and `kubectl apply -k ` applies it.

**📖 Official documentation:**

- [Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) *(search: "kustomize")*
- [Managing Secrets using Kustomize](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kustomize/) *(search: "secret kustomize")*
- [kubectl kustomize](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_kustomize/) *(search: "kubectl kustomize")*

---

### 🎯 Task: Build a production overlay

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

A Kustomize base for an app called `web` is in `/tmp/cka/kustomize/base`. Without modifying the base, create an overlay in `/tmp/cka/kustomize/overlays/prod` that puts every resource in namespace `arx-kust-prod` (the overlay must create this namespace), prefixes all names with `prod-`, runs 3 replicas, changes the nginx image tag to `1.27`, and adds the label `env=prod` to every resource. Apply the overlay with `kubectl apply -k`.

<details>
<summary>💡 Hints</summary>

- `namespace:` only sets the field. To create the namespace, list a Namespace manifest under `resources`.
- The `replicas` and `images` entries use the base names (`web`, `nginx`), not the prefixed ones.
- Run `kubectl kustomize /tmp/cka/kustomize/overlays/prod` and read the output before you apply.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka/kustomize/overlays/prod
cat > /tmp/cka/kustomize/overlays/prod/namespace.yaml <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: arx-kust-prod
YAML
cat > /tmp/cka/kustomize/overlays/prod/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - namespace.yaml
namespace: arx-kust-prod
namePrefix: prod-
labels:
  - pairs:
      env: prod
    includeTemplates: true
replicas:
  - name: web
    count: 3
images:
  - name: nginx
    newTag: "1.27"
YAML
kubectl kustomize /tmp/cka/kustomize/overlays/prod
kubectl apply -k /tmp/cka/kustomize/overlays/prod
kubectl -n arx-kust-prod rollout status deploy/prod-web --timeout=180s
```

**Explanation:**

- `mkdir -p` — Creates the overlay folder, and `overlays` above it, in one go.
- `namespace.yaml <<'YAML'` — Writes the Namespace manifest with a heredoc. Listing it under `resources` is what makes the overlay create the namespace.
- `kustomization.yaml <<'YAML'` — Writes the overlay itself. The base folder is never touched.
- `- ../../base` — From `overlays/prod`, two folders up is `/tmp/cka/kustomize`, then into `base`.
- `namespace: arx-kust-prod` — Sets the namespace on every namespaced object.
- `namePrefix: prod-` — Turns `web` into `prod-web` for both the Deployment and the Service.
- `labels:` — Adds `env: prod` to every object's labels, and through `includeTemplates` to the Pods too, while selectors stay as they are.
- `replicas:` — 3 replicas, named as in the base: `web`, not `prod-web`.
- `images:` — Matches containers using the `nginx` image and changes only the tag, to `1.27`.
- `kubectl kustomize` — Prints the rendered YAML. Check names, namespace, image and replicas before you apply.
- `kubectl apply -k` — Applies it. Kustomize puts the Namespace first, so the other objects have somewhere to go.
- `rollout status` — Waits until all 3 replicas of `prod-web` are ready, or fails after 180 seconds.

**Notes:** `commonLabels: {env: prod}` also passes, but it also adds `env` to the Deployment and Service selectors. That is fine for a fresh install. It fails with an immutable-selector error if `prod-web` already existed without the label. `kubectl get -k /tmp/cka/kustomize/overlays/prod` lists the live objects. The IMAGES and READY columns of `kubectl -n arx-kust-prod get deploy -o wide` confirm the tag and the replica count.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-kust-prod
o=/tmp/cka/kustomize/overlays/prod
d="kubectl -n $ns get deploy prod-web -o jsonpath"

[ -f $o/kustomization.yaml ] || [ -f $o/kustomization.yml ] || [ -f $o/Kustomization ] && p "overlay exists in $o" || f "overlay exists in $o"
out=$(kubectl kustomize $o 2>/dev/null)
[ -n "$out" ] && p "overlay builds" || f "overlay builds"
printf '%s\n' "$out" | kubectl create --dry-run=client -f - -o name 2>/dev/null | grep -qx "namespace/$ns" && p "overlay creates namespace $ns" || f "overlay creates namespace $ns"
b=/tmp/cka/kustomize/base
grep -q 'image: nginx:1.26' $b/deployment.yaml 2>/dev/null && grep -q 'replicas: 1' $b/deployment.yaml 2>/dev/null && p "base deployment.yaml unchanged" || f "base deployment.yaml unchanged"
grep -Eq '^(namespace|namePrefix|images|replicas|patches|configMapGenerator):' $b/kustomization.yaml 2>/dev/null && f "base kustomization.yaml unchanged" || p "base kustomization.yaml unchanged"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "deployment prod-web replicas = 3" || f "deployment prod-web replicas = 3"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($d='{.metadata.labels.env}' 2>/dev/null)" = "prod" ] && p "deployment labeled env=prod" || f "deployment labeled env=prod"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
[ "$(kubectl -n $ns get svc prod-web -o jsonpath='{.metadata.labels.env}' 2>/dev/null)" = "prod" ] && p "service prod-web labeled env=prod" || f "service prod-web labeled env=prod"
[ -n "$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=prod-web -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null)" ] && p "service prod-web has endpoints" || f "service prod-web has endpoints"
kubectl -n $ns get deploy web >/dev/null 2>&1 && f "no unprefixed deployment web" || p "no unprefixed deployment web"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Generated config and patches in a staging overlay

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

Using the base in `/tmp/cka/kustomize/base` unchanged, create an overlay in `/tmp/cka/kustomize/overlays/staging` that deploys into the existing namespace `arx-kust-staging` and: generates a ConfigMap named `web-config` with the keys `MODE=staging` and `LOG_LEVEL=debug`; loads every key of that ConfigMap as environment variables into the `web` container; and changes the Service `web` to type `NodePort`. Keep the generated name hash. Apply the overlay with `kubectl apply -k`.

<details>
<summary>💡 Hints</summary>

- A `configMapGenerator` with `literals` creates `web-config` plus a hash. Kustomize updates the references to it for you.
- The shortest way to add `envFrom` is a strategic merge patch on the container named `web`. The shortest way to change the Service is a JSON 6902 `replace` on `/spec/type`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka/kustomize/overlays/staging
cat > /tmp/cka/kustomize/overlays/staging/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: arx-kust-staging
configMapGenerator:
  - name: web-config
    literals:
      - MODE=staging
      - LOG_LEVEL=debug
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: web
      spec:
        template:
          spec:
            containers:
              - name: web
                envFrom:
                  - configMapRef:
                      name: web-config
  - target:
      kind: Service
      name: web
    patch: |-
      - op: replace
        path: /spec/type
        value: NodePort
YAML
kubectl kustomize /tmp/cka/kustomize/overlays/staging
kubectl apply -k /tmp/cka/kustomize/overlays/staging
kubectl -n arx-kust-staging rollout status deploy/web --timeout=180s
```

**Explanation:**

- `mkdir -p` — Creates the staging overlay folder.
- `kustomization.yaml <<'YAML'` — Writes the whole overlay in one heredoc.
- `namespace: arx-kust-staging` — The namespace already exists, so unlike the prod overlay there is no Namespace manifest to add.
- `configMapGenerator:` — Generates `web-config-` holding the two keys.
- `- patch: |-` — A strategic merge patch on the Deployment `web`: it adds to the container named `web` and leaves the rest of the base as it is.
- `envFrom:` — `envFrom` with `configMapRef` turns every key of the ConfigMap into an environment variable. Kustomize rewrites `web-config` to the hashed name when it builds.
- `- target:` — A JSON 6902 patch aimed at the Service `web`.
- `- op: replace` — Sets `spec.type` to `NodePort`. Kubernetes picks the node port number itself.
- `kubectl kustomize` — Renders the overlay. Look for the same hashed ConfigMap name in both the ConfigMap and the Deployment.
- `kubectl apply -k` — Applies the ConfigMap, the patched Deployment and the patched Service.
- `rollout status` — Waits for the Deployment's new Pod, which now carries the environment variables.

**Notes:** In the rendered output the ConfigMap is `web-config-`. The Deployment's `configMapRef` already points at that name, even though the patch says `web-config`. Setting `generatorOptions.disableNameSuffixHash: true` would keep the plain name, and this task would fail, because it asks you to keep the hash. Check the result with `kubectl -n arx-kust-staging exec deploy/web -- printenv MODE`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-kust-staging
o=/tmp/cka/kustomize/overlays/staging

[ -f $o/kustomization.yaml ] || [ -f $o/kustomization.yml ] || [ -f $o/Kustomization ] && p "overlay exists in $o" || f "overlay exists in $o"
kubectl kustomize $o >/dev/null 2>&1 && p "overlay builds" || f "overlay builds"
b=/tmp/cka/kustomize/base
grep -q 'image: nginx:1.26' $b/deployment.yaml 2>/dev/null && grep -q 'replicas: 1' $b/deployment.yaml 2>/dev/null && p "base deployment.yaml unchanged" || f "base deployment.yaml unchanged"
grep -Eq '^(namespace|namePrefix|images|replicas|patches|configMapGenerator):' $b/kustomization.yaml 2>/dev/null && f "base kustomization.yaml unchanged" || p "base kustomization.yaml unchanged"
ref=$(kubectl -n $ns get deploy web -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].envFrom[*].configMapRef.name}' 2>/dev/null)
echo "$ref" | grep -Eq '^web-config-[a-z0-9]{6,}$' && p "container web loads a hashed web-config ConfigMap ($ref)" || f "container web loads a hashed web-config ConfigMap"
[ -n "$ref" ] && [ "$(kubectl -n $ns get cm "$ref" -o jsonpath='{.data.MODE}/{.data.LOG_LEVEL}' 2>/dev/null)" = "staging/debug" ] && p "ConfigMap has MODE=staging, LOG_LEVEL=debug" || f "ConfigMap has MODE=staging, LOG_LEVEL=debug"
[ "$(kubectl -n $ns get svc web -o jsonpath='{.spec.type}' 2>/dev/null)" = "NodePort" ] && p "service web is NodePort" || f "service web is NodePort"
[ "$(kubectl -n $ns get deploy web -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "1" ] && p "deployment web available" || f "deployment web available"
[ "$(kubectl -n $ns exec deploy/web -c web -- printenv MODE 2>/dev/null)" = "staging" ] && p "running container sees MODE=staging" || f "running container sees MODE=staging"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
