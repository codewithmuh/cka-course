# CRDs and operators

> **Module 1** · Lesson 1.10 · 35 minutes

A CustomResourceDefinition adds a new kind of object to Kubernetes; an operator is a controller that acts on those objects.

## Learning Objectives

- You can write a CRD with required fields, a short name and extra columns, then create objects of the new kind.
- You can find which CRD and API group serve a kind, its scope, and which version is stored.
- You can install an operator and list the CRDs it brought in.


Kubernetes knows kinds such as Pod, Service and Deployment. A **CustomResourceDefinition** (CRD) teaches it a new kind. Example: you install cert-manager, and suddenly `kubectl get certificates` works, because cert-manager added a `Certificate` CRD. Objects of a new kind are called **custom resources**.

A CRD only stores data. An **operator** is a program that watches those objects and does the real work. On the exam you create a small CRD from a description, inspect the CRDs a cluster already has, or install an operator. It is all plain `kubectl`.

**How a CRD and an operator work together**

*The CRD adds the kind. You create objects of that kind. The operator watches them and does the work.*

`CRD` — adds a new kind to the API (`certificates.cert-manager.io`) → `Custom resource` — one object of that kind, made by you (`kind: Certificate`) → `Operator` — a controller that watches those objects (`cert-manager`) → `The result` — a Secret that holds the certificate

## Inside a CRD

Here is a small CRD for a kind called `CacheCluster`. The parts you must get right on the exam are the names, the version, the schema (the allowed fields) and the extra columns.

**A namespaced CRD with a schema, a short name and two extra columns**

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: cacheclusters.data.example.com     # must be <plural>.<group>
spec:
  group: data.example.com
  scope: Namespaced                        # or Cluster
  names:
    kind: CacheCluster                     # used in manifests
    plural: cacheclusters                  # used in URLs and kubectl get
    singular: cachecluster
    shortNames: ["cc"]
  versions:
    - name: v1
      served: true                         # the API answers on /apis/data.example.com/v1
      storage: true                        # exactly one version is written to etcd
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["engine"]
              properties:
                engine:
                  type: string
                replicas:
                  type: integer
                  minimum: 1
      additionalPrinterColumns:
        - name: Engine
          type: string
          jsonPath: .spec.engine
        - name: Replicas
          type: integer
          jsonPath: .spec.replicas
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: apiextensions.k8s.io/v1` — A CRD is itself an ordinary object, from the `apiextensions.k8s.io` group. Creating it adds a brand-new resource type to the API server.
- `name: cacheclusters.data.example.com` — The API server enforces the rule in the comment and rejects any other name. Build it from the `plural` and `group` lines below.
- `group: data.example.com` — The API group of the new kind. Its objects use `apiVersion: data.example.com/v1`: group, slash, version.
- `scope: Namespaced` — Each CacheCluster lives in a namespace, like a Pod. `Cluster` would make it cluster-wide, like a Node.
- `plural: cacheclusters` — The plural is also what RBAC rules list under `resources`, and the first half of the CRD's own name.
- `shortNames:` — Lets you type `kubectl get cc`, the way `po` stands for pods.
- `versions:` — Each API version of the kind gets an entry with its own schema. A CRD can serve several versions at once, such as `v1beta1` and `v1`.
- `openAPIV3Schema:` — The schema lists the allowed fields and their types. The API server checks every object against it, rejecting wrong types and dropping fields it does not know.
- `required: ["engine"]` — A CacheCluster without `spec.engine` is rejected. `required` sits on the parent object and lists its child fields by name.
- `minimum: 1` — Rejects any `replicas` below 1. `type: integer` on the line above already rejects text.
- `additionalPrinterColumns:` — Extra columns for `kubectl get`. Each has a header `name`, a `type` and a `jsonPath` into the object.

</details>

One CRD gives a kind five names that look alike. Each is used in a different place:

| Name | Form | Example |
| --- | --- | --- |
| The CRD's own name | `.` | `cacheclusters.data.example.com` |
| `apiVersion` of its objects | `/` | `data.example.com/v1` |
| `kind` | Capitalized, used in YAML | `CacheCluster` |
| `plural` | Lowercase, used by `kubectl get` and RBAC rules | `cacheclusters` |
| Short name | Your shortcut for `kubectl get` | `cc` |

## Rules worth knowing

- **Schema.** Every version needs a schema with a `type` on every field. The API server rejects objects that break it, with a message naming the field. `kubectl explain` reads the same schema.
- **Versions.** A CRD can serve several versions, but exactly one has `storage: true`. That is the version its objects are saved as in etcd. `status.storedVersions` lists every version that may still be in etcd.
- **Established.** A new CRD needs a moment before you can create objects of its kind. Wait for it with `kubectl wait --for=condition=Established crd/`.
- **Deleting a CRD deletes every object of its kind,** in every namespace. Treat `kubectl delete crd` like deleting a namespace.

## Inspect the CRDs a cluster already has

Clusters often come with CRDs already installed; this lab has the Gateway API and Calico ones. To trace a kind back to its CRD, first find its plural and its group:

**From a kind to its CRD**

```bash
kubectl get crd                                        # every CRD and when it was created
kubectl api-resources --api-group=gateway.networking.k8s.io   # NAME, SHORTNAMES, APIVERSION, NAMESPACED, KIND
kubectl api-resources | grep -i referencegrant          # find the resource for a kind you were given
kubectl explain referencegrants                         # served version, fields, descriptions
kubectl explain cacheclusters.spec --recursive          # your own CRD, once you have applied it
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get crd` — Lists every CustomResourceDefinition. Names have the form `.`, so each one shows its group.
- `--api-group=gateway.networking.k8s.io` — Lists only the resources of one API group. The NAMESPACED column answers the scope question at a glance.
- `grep -i referencegrant` — `-i` ignores case, so the kind `ReferenceGrant` finds the lowercase resource. The line shows the plural, the group and whether it is namespaced.
- `kubectl explain referencegrants` — Reads the documentation stored in the CRD's schema, the same way `explain` works for built-in kinds.
- `--recursive` — Prints every field under `spec` at once. Your own CRD only explains well if its schema has `description` fields.

</details>

The CRD's name is the plural and the group joined by a dot, here `referencegrants.gateway.networking.k8s.io`. Then read the details from the CRD itself:

**Read a CRD's group, scope and versions**

```bash
crd=referencegrants.gateway.networking.k8s.io
kubectl get crd $crd -o jsonpath='{.spec.group}{" "}{.spec.scope}{" "}{.spec.names.kind}{"\n"}'
kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{" storage="}{.storage}{"\n"}{end}'
kubectl get crd $crd -o jsonpath='{.status.storedVersions}{"\n"}'
kubectl get crd $crd -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{end}{"\n"}'

# All CRDs of one group
kubectl get crd -o custom-columns=NAME:.metadata.name,GROUP:.spec.group,SCOPE:.spec.scope | grep projectcalico
```

<details>
<summary>Line-by-line explanation</summary>

- `crd=referencegrants` — Stores the CRD name in a shell variable, so the next commands can write `$crd` instead of the long name.
- `{.spec.group}` — Prints the group, scope and kind on one line. `{" "}` adds a space and `{"\n"}` a newline.
- `{range .spec.versions[*]}` — Loops over the versions and prints each name with its `served` and `storage` flags. Exactly one says `storage=true`.
- `{.status.storedVersions}` — Every version objects may still be saved as in etcd. It can list an old version even after storage moved to a newer one.
- `{range .status.conditions[*]}` — Prints each condition as `Type=Status`. A healthy CRD shows `NamesAccepted=True` and `Established=True`.
- `custom-columns=NAME` — A table of every CRD with its group and scope; `grep projectcalico` keeps the ones Calico installed.

</details>

Careful: `kubectl api-resources` and `kubectl explain` show the preferred version, which is not always the stored one. Only `storage: true` in the CRD tells you which version is stored.

## Operators: CRDs plus a controller

An **operator** adds a controller to its CRDs. The controller is a program, usually a Deployment, that watches the custom resources and changes the cluster to match them. Two examples:

- You create a `Certificate`, and cert-manager makes a Secret that holds the certificate.
- You create a `Postgres` object, and a database operator builds the StatefulSets, Services and backups for it.

To **install** an operator, you apply its CRDs, its RBAC and its controller, from a release manifest or a Helm chart. To **configure** it, you create its custom resources.

**Install an operator from its release manifest and see what it brought**

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s

kubectl get crd -l app.kubernetes.io/name=cert-manager    # if the project labels its CRDs
kubectl get crd | grep cert-manager.io                    # otherwise filter by group
kubectl api-resources --api-group=cert-manager.io
kubectl -n cert-manager get deploy,sa                     # the controller side
kubectl get clusterroles | grep cert-manager

# Configure it through a custom resource
kubectl apply -f - <<'YAML'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
YAML
kubectl get clusterissuers

# Remove it: custom resources first, then the manifest (this deletes the CRDs and any remaining CRs)
kubectl delete clusterissuer selfsigned
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl apply -f https://github.com/cert-manager` — Applies the project's release manifest straight from its URL: one big file with the namespace, CRDs, RBAC and controller Deployments. The version in the URL pins the release.
- `rollout status deploy/cert-manager-webhook` — Waits for the webhook Deployment. cert-manager checks its custom resources through this webhook, so creating one before it is ready can fail with a webhook error.
- `kubectl get crd -l` — `-l` filters by label. Many projects label everything they install, which makes this the cleanest list.
- `grep cert-manager.io` — CRD names end in their group, so grepping for the group finds them even without labels.
- `--api-group=cert-manager.io` — Shows the kinds those CRDs added, with short names and scope. `ClusterIssuer` is cluster-scoped; `Issuer` and `Certificate` are namespaced.
- `get deploy,sa` — Two kinds in one `get`: the controller Deployments and the ServiceAccounts they run as.
- `get clusterroles | grep cert-manager` — The ClusterRoles that let the controllers watch and write resources across the cluster.
- `kind: ClusterIssuer` — A cert-manager custom resource, written like any object with the CRD's group and version as `apiVersion`. Creating it is how you configure the operator.
- `selfSigned: {}` — `{}` is an empty object. The self-signed issuer needs no settings, but the field must be present to choose that type.
- `kubectl get clusterissuers` — Lists the issuers. READY turns `True` once the controller has picked this one up.
- `kubectl delete clusterissuer selfsigned` — Delete your custom resources first, while the controller is still running to clean up after them.
- `kubectl delete -f https://` — Deletes everything in the manifest. That includes the CRDs, so any custom resources still left go with them.

</details>

One Helm detail: Helm installs the CRDs in a chart's `crds/` folder once, and never upgrades or deletes them. `helm uninstall` leaves them behind.

> [!IMPORTANT] **What the grader reads**
> For a CRD you create, the grader checks that it is `Established`. It checks that the group, kind, plural, scope and versions match the question, and that the schema rejects bad input. For a custom resource, it reads the fields back. For questions about installed CRDs, it compares your file with the live CRD. Copy names from `kubectl get crd` instead of typing them.

## 📝 Key Takeaways

- A CRD adds a new kind to the API. A custom resource is one object of that kind. An operator is a controller that acts on those objects.
- The CRD's name is `.`; a manifest's `apiVersion` is `/`.
- `required` sits on the parent object and lists its fields by name.
- Exactly one version has `storage: true`, and it is not always the newest one.
- Deleting a CRD deletes every object of that kind.

**📖 Official documentation:**

- [Extend the Kubernetes API with CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) *(search: "customresourcedefinition")*
- [Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) *(search: "custom resources")*
- [Versions in CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/) *(search: "crd versioning")*
- [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) *(search: "operator pattern")*

---

### 🎯 Task: Create a CRD with validation, then a custom resource

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 9 min |

**Question:**

Create a CustomResourceDefinition for the kind `BackupPolicy` in API group `ops.example.com`: version `v1` (served and used for storage), namespaced, plural `backuppolicies`, singular `backuppolicy`, short name `bp`. Its schema must require `spec.schedule` (a string) and `spec.retentionDays` (an integer of at least 1). `kubectl get bp` must show the columns `Schedule` and `Retention`. Then create a BackupPolicy named `nightly` in namespace `arx-crd` with schedule `0 2 * * *` and retentionDays `14`.

<details>
<summary>💡 Hints</summary>

- The CRD's `metadata.name` is `backuppolicies.ops.example.com`.
- `required` is a list on the object that holds the fields (`spec`), not on each field.
- Printer columns go in `additionalPrinterColumns` under the version, each with a `jsonPath` such as `.spec.schedule`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl apply -f - <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backuppolicies.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names:
    kind: BackupPolicy
    plural: backuppolicies
    singular: backuppolicy
    shortNames: ["bp"]
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: ["schedule", "retentionDays"]
              properties:
                schedule:
                  type: string
                retentionDays:
                  type: integer
                  minimum: 1
      additionalPrinterColumns:
        - name: Schedule
          type: string
          jsonPath: .spec.schedule
        - name: Retention
          type: integer
          jsonPath: .spec.retentionDays
YAML
kubectl wait --for=condition=Established crd/backuppolicies.ops.example.com --timeout=60s
kubectl apply -f - <<'YAML'
apiVersion: ops.example.com/v1
kind: BackupPolicy
metadata:
  name: nightly
  namespace: arx-crd
spec:
  schedule: "0 2 * * *"
  retentionDays: 14
YAML
kubectl -n arx-crd get bp
```

**Explanation:**

- `name: backuppolicies.ops.example.com` — The CRD's name must be the plural, a dot, then the group.
- `scope: Namespaced` — BackupPolicies live in namespaces, so `nightly` can be created in `arx-crd`.
- `shortNames: ["bp"]` — Makes `kubectl get bp` work.
- `served: true` — `v1` is the only version, so it is both served by the API and the one saved in etcd.
- `required: ["schedule", "retentionDays"]` — Both fields are mandatory. The list sits on `spec`, the object that holds them.
- `minimum: 1` — Rejects `retentionDays` of 0 or less; `type: integer` above rejects text.
- `additionalPrinterColumns:` — The two columns `kubectl get bp` must show, each reading one field through its `jsonPath`.
- `kubectl wait --for=condition=Established` — Waits until the API server serves the new kind. Creating a BackupPolicy before that fails with "no matches for kind".
- `apiVersion: ops.example.com/v1` — The custom resource: group and version from the CRD, then kind, name and namespace like any object.
- `schedule: "0 2 * * *"` — Quoted, because a bare `*` starts a YAML alias and the file would not parse.
- `get bp` — Lists it with the new SCHEDULE and RETENTION columns.

**Notes:** Start from the CRD example on the kubernetes.io page "Extend the Kubernetes API with CustomResourceDefinitions" and change the names. Typing a schema from memory under time pressure is where indentation mistakes happen. Quote the schedule in YAML, because a bare `*` starts an alias. To prove the validation works, run `kubectl apply --dry-run=server` on a copy that sets `retentionDays: 0`. It must be rejected.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-crd
c="kubectl get crd backuppolicies.ops.example.com -o jsonpath"

[ "$($c='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)" = "True" ] && p "CRD backuppolicies.ops.example.com is Established" || f "CRD backuppolicies.ops.example.com is Established"
[ "$($c='{.spec.group}/{.spec.scope}/{.spec.names.kind}/{.spec.names.singular}' 2>/dev/null)" = "ops.example.com/Namespaced/BackupPolicy/backuppolicy" ] && p "group, scope, kind and singular" || f "group, scope, kind and singular"
$c='{.spec.names.shortNames}' 2>/dev/null | grep -q '"bp"' && p "short name bp" || f "short name bp"
[ "$($c='{.spec.versions[?(@.name=="v1")].served}/{.spec.versions[?(@.name=="v1")].storage}' 2>/dev/null)" = "true/true" ] && p "v1 served and storage" || f "v1 served and storage"
hdr=$(kubectl -n $ns get bp 2>/dev/null | head -1)
echo "$hdr" | grep -q SCHEDULE && echo "$hdr" | grep -q RETENTION && p "kubectl get bp shows Schedule and Retention" || f "kubectl get bp shows Schedule and Retention"
[ "$(kubectl -n $ns get backuppolicy nightly -o jsonpath='{.spec.schedule}|{.spec.retentionDays}' 2>/dev/null)" = "0 2 * * *|14" ] && p "nightly has schedule '0 2 * * *' and retentionDays 14" || f "nightly has schedule '0 2 * * *' and retentionDays 14"
bad() { kubectl create --dry-run=server -o name -f - >/dev/null 2>&1 <<EOF
apiVersion: ops.example.com/v1
kind: BackupPolicy
metadata:
  name: verify-probe
  namespace: $ns
spec:
$1
EOF
}
kubectl get crd backuppolicies.ops.example.com >/dev/null 2>&1 && ! bad '  schedule: "@daily"
  retentionDays: 0' && p "schema rejects retentionDays 0" || f "schema rejects retentionDays 0"
kubectl get crd backuppolicies.ops.example.com >/dev/null 2>&1 && ! bad '  retentionDays: 3' && p "schema requires schedule" || f "schema requires schedule"
kubectl get crd backuppolicies.ops.example.com >/dev/null 2>&1 && ! bad '  schedule: "@daily"
  retentionDays: "three"' && p "schema types retentionDays as integer" || f "schema types retentionDays as integer"
kubectl get crd backuppolicies.ops.example.com >/dev/null 2>&1 && bad '  schedule: "@daily"
  retentionDays: 3' && p "a valid object is accepted" || f "a valid object is accepted"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Trace a kind back to its CRD

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Objects of kind `ReferenceGrant` can be created in this cluster. Find the CustomResourceDefinition that defines this kind and write four lines to `/tmp/cka/crd/referencegrant.txt`, in this order: the CRD's name, its API group, its scope (as the API reports it), and the version its objects are stored in. Then write the names of all CRDs that belong to the same API group, one per line, to `/tmp/cka/crd/group-crds.txt`.

<details>
<summary>💡 Hints</summary>

- `kubectl api-resources | grep -i referencegrant` gives the plural and the group. The CRD name is `plural.group`.
- The storage version is the entry in `.spec.versions` with `storage: true` (also in `.status.storedVersions`). It is not always the newest served version.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl api-resources | grep -i referencegrant
crd=referencegrants.gateway.networking.k8s.io
kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage}{"\n"}{end}'
{
  echo "$crd"
  kubectl get crd $crd -o jsonpath='{.spec.group}{"\n"}{.spec.scope}{"\n"}{.spec.versions[?(@.storage==true)].name}{"\n"}'
} > /tmp/cka/crd/referencegrant.txt
group=$(kubectl get crd $crd -o jsonpath='{.spec.group}')
kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.group}{"\n"}{end}' | awk -v g="$group" '$2 == g {print $1}' > /tmp/cka/crd/group-crds.txt
cat /tmp/cka/crd/referencegrant.txt /tmp/cka/crd/group-crds.txt
```

**Explanation:**

- `grep -i referencegrant` — Finds the resource behind the kind: its plural and API group, which together make the CRD name.
- `crd=referencegrants` — Saves the CRD name in `$crd` for the next commands.
- `{range .spec.versions[*]}` — Shows each version with its served and storage flags, so you can see that the stored one is not the newest.
- `{` — Braces group the commands, so all their output goes to the file through one redirect at the end.
- `echo "$crd"` — Line 1: the CRD name.
- `?(@.storage==true)` — Lines 2 to 4: group, scope and storage version. `?(@.storage==true)` keeps only the version marked for storage.
- `} > /tmp/cka/crd/referencegrant.txt` — Closes the group and writes all four lines to the file.
- `group=$(` — Captures the group in `$group`. `$(…)` runs a command and keeps its output.
- `awk -v g=` — Prints every CRD as `name group`, then awk keeps the names whose second column equals the group. `-v g="$group"` passes the shell variable into awk.
- `cat /tmp/cka/crd` — Prints both files so you can check them before moving on.

**Notes:** The trap is the fourth line. In this lab's Gateway API release, ReferenceGrant is served as both `v1` and `v1beta1`, but its objects are still stored as `v1beta1`. `kubectl api-resources` and `kubectl explain` show the preferred served version, not the stored one, so read `storage: true` from the CRD. To see the group's CRDs by eye, use `kubectl get crd | grep gateway.networking.k8s.io`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
a=/tmp/cka/crd/referencegrant.txt
g=/tmp/cka/crd/group-crds.txt
crd=$(kubectl get crd -o jsonpath='{range .items[?(@.spec.names.kind=="ReferenceGrant")]}{.metadata.name}{end}' 2>/dev/null)
group=$(kubectl get crd "$crd" -o jsonpath='{.spec.group}' 2>/dev/null)
scope=$(kubectl get crd "$crd" -o jsonpath='{.spec.scope}' 2>/dev/null)
stor=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[?(@.storage==true)].name}' 2>/dev/null)
line() { sed -n "$1p" $a 2>/dev/null | tr -d ' \r'; }

[ -n "$crd" ] && [ "$(line 1)" = "$crd" ] && p "line 1 is the CRD name ($crd)" || f "line 1 is the CRD name"
[ -n "$group" ] && [ "$(line 2)" = "$group" ] && p "line 2 is the group ($group)" || f "line 2 is the group"
[ -n "$scope" ] && [ "$(line 3 | tr 'A-Z' 'a-z')" = "$(echo $scope | tr 'A-Z' 'a-z')" ] && p "line 3 is the scope ($scope)" || f "line 3 is the scope"
[ -n "$stor" ] && [ "$(line 4)" = "$stor" ] && p "line 4 is the storage version ($stor)" || f "line 4 is the storage version"
want=$(kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.group}{"\n"}{end}' 2>/dev/null | awk -v g="$group" '$2 == g {print $1}' | LC_ALL=C sort)
have=$(tr -d ' \r' < $g 2>/dev/null | grep -v '^$' | LC_ALL=C sort)
[ -n "$want" ] && [ "$have" = "$want" ] && p "group-crds.txt lists all $(echo "$want" | wc -l | tr -d ' ') CRDs in $group" || f "group-crds.txt lists exactly the CRDs in $group"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
