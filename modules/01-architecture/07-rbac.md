# RBAC: roles, bindings and service accounts

> **Module 1** · Lesson 1.7 · 40 minutes

Who may do what in a cluster: Roles list allowed actions, bindings hand them out, and kubectl auth can-i proves it.

## Learning Objectives

- You can create a ServiceAccount, a Role and a RoleBinding with kubectl in under two minutes.
- You can choose between a Role and a ClusterRole, and between a RoleBinding and a ClusterRoleBinding.
- You can write rules with the right API group, plural resource names and subresources such as `pods/log`.
- You can check access with `kubectl auth can-i`, issue a short-lived token, and take back access that is too broad.


**RBAC** (role-based access control) decides who may do what in a cluster. May your Django app's Pod read Secrets? May the user `maya` delete Pods? RBAC answers these questions. On the exam it is one of the surest sources of points, because most tasks take three short commands.

The grader does not read your YAML. It asks the API server whether someone may do something, the same way `kubectl auth can-i` does. So a rule that looks right but names the wrong API group still fails.

## Four objects with look-alike names

RBAC uses four objects. Learn them in pairs: a **role** says *what* is allowed, and a **binding** says *who* gets it. A role does nothing until a binding hands it out.

| Object | What it is | Where its rules apply |
| --- | --- | --- |
| **Role** | A list of allowed actions | One namespace |
| **ClusterRole** | The same, but it belongs to no namespace | Wherever a binding uses it, including cluster-wide objects such as nodes |
| **RoleBinding** | Gives a Role or a ClusterRole to someone | Only in the binding's own namespace |
| **ClusterRoleBinding** | Gives a ClusterRole to someone | Every namespace, plus cluster-wide objects |

**How a binding grants access**

*The binding joins *who* (the subject) to *what* (the role). The role holds the rules: which actions on which objects.*

`Subject` — a user, a group or a service account (`maya`) → `RoleBinding` — gives the role to the subject → `Role` — a named list of rules (`config-editor`) → `Rules` — verbs on resources (`get, list on configmaps`)

- **Subjects** are who gets access. A *user* is a person, such as `maya`. A *group* is a set of users, such as `platform-oncall`. A *service account* is an identity for a program that runs in a Pod. Users and groups are not objects you create in the cluster.
- **Permissions only add up.** A subject gets the rules of every binding that names it. There are no deny rules, so to take access away you delete or narrow a binding.
- A RoleBinding may point at a ClusterRole. The rules then apply only in the binding's namespace, and rules about cluster-wide objects such as nodes give nothing. This lets you reuse one ClusterRole, such as `edit`, in many namespaces.
- A ClusterRoleBinding can only point at a ClusterRole, never at a Role.

## Writing a rule

A rule has three parts: the **API group**, the **resources** and the **verbs** (the actions). Here is a Role with two rules, and a RoleBinding that gives it to all three kinds of subject:

**A Role and a RoleBinding with all three subject kinds**

```yaml
# To try it: kubectl create namespace arx-rbac-demo first, then kubectl apply -f this file
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: config-editor
  namespace: arx-rbac-demo
rules:
  - apiGroups: [""]                   # "" is the core group: pods, services, configmaps, secrets
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/scale"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: config-editor
  namespace: arx-rbac-demo
roleRef:                              # cannot be changed: to point elsewhere, delete and recreate the binding
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: config-editor
subjects:
  - kind: ServiceAccount              # no apiGroup; always give its namespace
    name: settings-sync
    namespace: arx-rbac-demo
  - kind: User                        # the user name from their certificate or login
    apiGroup: rbac.authorization.k8s.io
    name: maya
  - kind: Group                       # a group from their certificate or login
    apiGroup: rbac.authorization.k8s.io
    name: platform-oncall
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: Role` — A **Role** is a named list of permissions inside one namespace, here `arx-rbac-demo`. Every RBAC object uses the API group `rbac.authorization.k8s.io/v1`. On its own a Role grants nothing; a binding hands it to someone.
- `rules:` — Each item under `rules` is one permission: which API groups, which resources, which verbs. A request is allowed when any one rule matches it.
- `apiGroups: [""]` — The brackets are a one-line YAML list. Its single item is an empty string: the core group, the objects whose `apiVersion` is plain `v1`.
- `verbs: ["get", "list", "watch"]` — Read-only verbs: `get` fetches one object by name, `list` fetches them all, and `watch` streams changes, which `kubectl get -w` needs.
- `apiGroups: ["apps"]` — Deployments are in the `apps` group, because their `apiVersion` is `apps/v1`. Listing them under `""` is a classic mistake: the rule looks right and grants nothing.
- `deployments/scale` — `deployments/scale` is a *subresource*, the part `kubectl scale` talks to. It must be listed on its own; access to `deployments` does not include it.
- `verbs: ["get", "patch"]` — `patch` changes part of an object; it is what `kubectl edit`, `apply` and `label` send. `update` would replace the whole object, as `kubectl replace` does.
- `---` — Three dashes separate two objects in one YAML file, so one `kubectl apply -f` creates both.
- `kind: RoleBinding` — A **RoleBinding** connects a role to subjects, the people or programs that get it. It lives in `arx-rbac-demo`, so the rules apply only there.
- `roleRef:` — Names the role this binding hands out: `kind` is `Role` for one in the same namespace, or `ClusterRole` to reuse a cluster-wide one inside this namespace.
- `subjects:` — Who receives the permissions. One binding can name any mix of service accounts, users and groups.
- `kind: ServiceAccount` — A ServiceAccount is an identity for software running in Pods. It lives in a namespace, so the subject names it, and unlike User and Group it has no `apiGroup`.
- `kind: User` — Kubernetes stores no User objects, so there is nothing to create for `maya`. A typo is not an error either: it just binds a name nobody has.
- `kind: Group` — Grants the role to every member of the group at once. Groups, like users, exist only in what the authenticator reports; you test them with `kubectl auth can-i --as-group`.

</details>

| Field | What goes in it | Example |
| --- | --- | --- |
| `apiGroups` | The part of the object's `apiVersion` before the slash. Core objects have no group, so they use `""`. | Pods (`v1`): `""`. Deployments (`apps/v1`): `apps`. Jobs: `batch`. |
| `resources` | Lowercase plural names. A subresource is its own entry: access to `pods` does not include `pods/log`. | `pods`, `pods/log`, `deployments/scale` |
| `verbs` | The actions allowed. `"*"` means every verb. | `get`, `list`, `watch`, `create`, `update`, `patch`, `delete` |
| `resourceNames` (optional) | Limits the rule to objects with these names. It cannot limit `create`. | `app-settings` |

Not sure of a group or a plural? `kubectl api-resources -o wide` lists every resource with its API group and its verbs.

## Create it with kubectl

On the exam you rarely write RBAC YAML. `kubectl create` makes each object in one line. The flags take comma-separated lists, and a resource outside the core group is written `.`, such as `deployments.apps`.

**Create a ServiceAccount, Roles and bindings**

```bash
kubectl create namespace arx-rbac-demo
kubectl -n arx-rbac-demo create serviceaccount settings-sync

# Role: comma-separated verbs, any number of resources; non-core resources as <resource>.<group>
kubectl -n arx-rbac-demo create role app-reader \
  --verb=get,list,watch --resource=pods,services,deployments.apps
kubectl -n arx-rbac-demo create role settings-writer \
  --verb=update,patch --resource=configmaps --resource-name=app-settings

# RoleBinding: --role or --clusterrole, then any mix of subjects (SA is <namespace>:<name>)
kubectl -n arx-rbac-demo create rolebinding app-reader --role=app-reader \
  --serviceaccount=arx-rbac-demo:settings-sync --user=maya --group=platform-oncall
kubectl -n arx-rbac-demo create rolebinding settings-writer --role=settings-writer --user=maya

# Cluster-wide rules and binding
kubectl create clusterrole pv-viewer --verb=get,list,watch \
  --resource=persistentvolumes,storageclasses.storage.k8s.io
kubectl create clusterrolebinding pv-viewer --clusterrole=pv-viewer --group=platform-oncall

# Generate YAML instead when you need to add something the flags cannot express
kubectl -n arx-rbac-demo create role app-reader --verb=get --resource=pods --dry-run=client -o yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl create namespace arx-rbac-demo` — Creates the namespace first: ServiceAccounts, Roles and RoleBindings are all namespaced objects.
- `create serviceaccount settings-sync` — Creates the identity. `-n` works the same before or after the verb; what matters is that every namespaced command has it.
- `create role app-reader` — Creates a Role named `app-reader`. The `\` at the end continues the command on the next line.
- `--resource=pods,services,deployments.apps` — One rule: three read verbs on three resources. `deployments.apps` spells out the API group, so the rule cannot land in the wrong one.
- `--resource-name=app-settings` — A second Role whose rule only covers the ConfigMap named `app-settings`, the flag form of `resourceNames`.
- `create rolebinding app-reader --role=app-reader` — Binds the Role `app-reader`. Use `--clusterrole` instead to bind a ClusterRole, still only inside this namespace.
- `--serviceaccount=arx-rbac-demo:settings-sync` — Three subjects in one binding. A service account is written `namespace:name`; giving only the name is an error.
- `create rolebinding settings-writer` — A second binding for the second Role. Bindings add up, so `maya` now has the rules of both Roles.
- `kubectl create clusterrole pv-viewer` — A ClusterRole is not namespaced, so there is no `-n`. You need one for cluster-scoped resources such as PersistentVolumes and StorageClasses.
- `storageclasses.storage.k8s.io` — StorageClasses live in the `storage.k8s.io` group; PersistentVolumes are in the core group, so they need no suffix.
- `kubectl create clusterrolebinding pv-viewer` — A ClusterRoleBinding grants the ClusterRole everywhere: in every namespace and on cluster-scoped objects.
- `--dry-run=client -o yaml` — Prints the Role as YAML instead of creating it. Save it to a file, add a second rule with different verbs, then `kubectl apply -f` it.

</details>

Look at how the binding names the service account: `namespace:name`. You write a service account three different ways, depending on where you use it:

| Where | How you write settings-sync from arx-rbac-demo |
| --- | --- |
| `kubectl create rolebinding` | `--serviceaccount=arx-rbac-demo:settings-sync` |
| A binding's YAML | `kind: ServiceAccount`, `name: settings-sync` and `namespace: arx-rbac-demo` |
| `kubectl auth can-i` | `--as=system:serviceaccount:arx-rbac-demo:settings-sync` |

## Prove it with auth can-i

Always check your work before you move on. `kubectl auth can-i` asks the API server whether a request would be allowed. It prints `yes` or `no` and changes nothing. Add `--as` to ask on behalf of someone else.

**Ask the API server as each subject**

```bash
# Ask the API server as the subject. "yes" exits 0, "no" exits 1.
kubectl auth can-i list deployments.apps -n arx-rbac-demo \
  --as=system:serviceaccount:arx-rbac-demo:settings-sync
kubectl auth can-i update configmaps/app-settings -n arx-rbac-demo --as=maya   # TYPE/NAME form
kubectl auth can-i get pods --subresource=log -n arx-rbac-demo --as=maya       # subresources need the flag
kubectl auth can-i list persistentvolumes --as=anyone --as-group=platform-oncall  # --as-group needs --as
kubectl auth can-i --list -n arx-rbac-demo --as=system:serviceaccount:arx-rbac-demo:settings-sync
kubectl auth whoami                                                            # who you are right now
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl auth can-i list deployments.apps` — Asks the API server whether this request would be allowed and prints yes or no. Nothing is changed.
- `--as=system:serviceaccount:arx-rbac-demo:settings-sync` — `--as` asks on someone else's behalf. A service account's user name is `system:serviceaccount::`, not the short form the create commands take.
- `update configmaps/app-settings` — Checks one named object with the `TYPE/NAME` form, which is how you test a `resourceNames` rule. This one says yes.
- `--subresource=log` — Asks about reading Pod logs (`pods/log`), which `kubectl logs` needs. The answer is no: none of maya's Roles lists that subresource.
- `--as=anyone --as-group=platform-oncall` — Tests a group. The user name is invented; the group is what matters. Yes here, through the ClusterRoleBinding.
- `can-i --list` — Lists everything the subject may do in the namespace, one row per resource with its verbs. Handy for spotting access that is too broad.
- `kubectl auth whoami` — Prints the user name and groups the API server sees for your own kubeconfig.

</details>

## Service accounts and tokens

A **ServiceAccount** is an identity for a program, not a person. Example: your Django app needs to list Pods through the API. You create a service account for it, bind a Role to that account, and run the app's Pods as that account.

- A Pod runs as the account named in `spec.serviceAccountName`. Leave it out and the Pod runs as `default`.
- The kubelet puts a short-lived token into the Pod, at `/var/run/secrets/kubernetes.io/serviceaccount/token`, and renews it for you.
- `kubectl create token` gives you a token on demand. Kubernetes no longer creates token Secrets by itself.
- Set `automountServiceAccountToken: false` on the Pod or the account when the app never calls the API.

**A token, and a Pod that runs as the account**

```bash
kubectl -n arx-rbac-demo create serviceaccount report-bot
kubectl -n arx-rbac-demo create token report-bot --duration=2h > /tmp/cka/report-bot.token
# The token is printed once and stored nowhere. A token that never expires needs a Secret of type kubernetes.io/service-account-token: avoid it unless asked.

# Run as the account: kubectl run has no SA flag, so override the spec (or set it in YAML)
kubectl -n arx-rbac-demo run reporter --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"report-bot"}}' -- sleep 3600
kubectl -n arx-rbac-demo set serviceaccount deployment/web report-bot   # an existing Deployment
```

<details>
<summary>Line-by-line explanation</summary>

- `create serviceaccount report-bot` — Creates the account the next lines issue tokens for.
- `create token report-bot --duration=2h` — Asks the API server for a signed token for `report-bot` that expires in 2 hours; `>` saves it to a file. Anyone holding it can act as the account until then.
- `run reporter --image=busybox:1.36 --restart=Never` — Starts a single Pod. `--restart=Never` sets its restart policy, so the container is not restarted when its command ends.
- `--overrides=` — Merges this JSON into the generated Pod, setting `spec.serviceAccountName`. Everything after `--` is the container's command; `sleep 3600` keeps it alive for an hour.
- `set serviceaccount deployment/web report-bot` — Changes the account in a Deployment's Pod template, which rolls out new Pods. A running Pod's account cannot be changed.

</details>

## Built-in ClusterRoles

Kubernetes comes with ready-made ClusterRoles. Bind one when it fits, instead of writing your own. For example, `kubectl -n shop create rolebinding maya-edit --clusterrole=edit --user=maya` lets `maya` change most things in `shop`, and nothing anywhere else.

| ClusterRole | Allows | Does not allow |
| --- | --- | --- |
| `cluster-admin` | Everything. Through a RoleBinding, everything in one namespace. | Nothing is held back |
| `admin` | Read and write on most objects in a namespace, including Roles and RoleBindings | Changing the Namespace itself or its ResourceQuotas |
| `edit` | Read and write on most objects in a namespace, including Pods and Secrets | Reading or changing Roles and RoleBindings |
| `view` | Read-only on most objects in a namespace | Secrets (they hold passwords), Roles and RoleBindings |

Your admin kubeconfig gets `cluster-admin` through the group `kubeadm:cluster-admins`. [Certificates and kubeconfig](/cka/architecture/certificates-and-kubeconfig) shows where users and groups come from.

> [!IMPORTANT] **What the grader checks, and the traps**
> The grader checks both ways: the subject *can* do what was asked, and *cannot* do more. So test one allowed and one forbidden action with `kubectl auth can-i`. Watch for the usual misses. Deployments go under `apps`, not `""`. A service account needs its namespace. A missing `-n` puts the binding in `default`. Resource names are plural. And `--as-group` works only together with `--as`.

## 📝 Key Takeaways

- A Role lists what is allowed. A binding gives it to a user, a group or a service account. Without a binding, a Role does nothing.
- Role and RoleBinding work in one namespace. ClusterRole and ClusterRoleBinding cover the whole cluster, including nodes and PersistentVolumes.
- Rules need the right API group (`apps` for Deployments, `""` for Pods) and plural names. Subresources such as `pods/log` are listed on their own.
- Permissions only add up. There are no deny rules, so to take access away you delete or narrow a binding.
- Check with `kubectl auth can-i … --as=…`. A service account is `system:serviceaccount::` there.

**📖 Official documentation:**

- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) *(search: "rbac authorization")*
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) *(search: "configure service accounts")*
- [kubectl auth can-i](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/) *(search: "kubectl auth can-i")*
- [Managing Service Accounts](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) *(search: "managing service accounts")*

---

### 🎯 Task: A service account that can deploy, and a token for it

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `arx-rbac`, create a ServiceAccount named `deployer` and a Role named `deployer` that allows `get`, `list`, `watch`, `create`, `update` and `patch` on Deployments, and `get`, `list`, `watch` on Pods, and nothing else. Bind the Role to the ServiceAccount with a RoleBinding named `deployer-binding`. Finally, create a token for `deployer` that is valid for 2 hours and write only the token to `/tmp/cka/rbac/deployer.token`.

<details>
<summary>💡 Hints</summary>

- Deployments are in the apps API group, so write `--resource=deployments.apps`.
- Two different verb lists need two rules. Generate a Role with `kubectl create role … --dry-run=client -o yaml`, add the second rule, then apply it. Or write the YAML yourself.
- `kubectl create token` prints the token on the screen. Send it to the file with `>`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n arx-rbac create serviceaccount deployer
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer
  namespace: arx-rbac
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
YAML
kubectl -n arx-rbac create rolebinding deployer-binding --role=deployer --serviceaccount=arx-rbac:deployer
kubectl -n arx-rbac create token deployer --duration=2h > /tmp/cka/rbac/deployer.token
kubectl auth can-i create deployments.apps -n arx-rbac --as=system:serviceaccount:arx-rbac:deployer
```

**Explanation:**

- `create serviceaccount deployer` — Creates the identity the Role will be bound to.
- `kubectl apply -f - <<'YAML'` — Two different verb lists need two rules, which the one-line `create role` cannot express, so the Role is written as YAML and piped straight into `apply`.
- `namespace: arx-rbac` — The namespace is set inside the YAML, so `apply` needs no `-n`.
- `apiGroups: ["apps"]` — Rule one: Deployments, in the `apps` group, with the read verbs plus `create`, `update` and `patch`. No `delete`, because the task did not ask for it.
- `apiGroups: [""]` — Rule two: read-only on Pods, which are in the core group.
- `create rolebinding deployer-binding` — Binds the Role to the account, written as `namespace:name`.
- `create token deployer --duration=2h` — Prints a 2-hour token and nothing else, so the file holds exactly the token.
- `kubectl auth can-i` — Checks the result as the account. Expect `yes`; run it again with `delete` and expect `no`.

**Notes:** Fastest exam route: generate the first rule with `kubectl -n arx-rbac create role deployer --verb=get,list,watch,create,update,patch --resource=deployments.apps --dry-run=client -o yaml > role.yaml`. Add a second rule for pods in vim, then apply the file. Each part is graded on its own, so write the token file even when time is short. Then check that `kubectl auth can-i delete deployments.apps -n arx-rbac --as=system:serviceaccount:arx-rbac:deployer` says `no`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-rbac
sa=system:serviceaccount:arx-rbac:deployer
can() { kubectl auth can-i "$@" --as=$sa 2>/dev/null | head -1 | awk '{print $1}'; }
tf=/tmp/cka/rbac/deployer.token

kubectl -n $ns get serviceaccount deployer >/dev/null 2>&1 && p "serviceaccount deployer exists" || f "serviceaccount deployer exists"
[ "$(kubectl -n $ns get rolebinding deployer-binding -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)" = "Role/deployer" ] && p "deployer-binding points at Role deployer" || f "deployer-binding points at Role deployer"
[ "$(can create deployments.apps -n $ns)" = "yes" ] && p "can create deployments" || f "can create deployments"
[ "$(can patch deployments.apps -n $ns)" = "yes" ] && p "can patch deployments" || f "can patch deployments"
[ "$(can watch pods -n $ns)" = "yes" ] && p "can watch pods" || f "can watch pods"
[ "$(can delete deployments.apps -n $ns)" = "no" ] && p "cannot delete deployments" || f "cannot delete deployments"
[ "$(can create pods -n $ns)" = "no" ] && p "cannot create pods" || f "cannot create pods"
[ "$(can get secrets -n $ns)" = "no" ] && p "cannot read secrets" || f "cannot read secrets"
[ "$(can list deployments.apps -n default)" = "no" ] && p "no access outside arx-rbac" || f "no access outside arx-rbac"

user=""
if [ -s $tf ]; then
  user=$(kubectl create -o jsonpath='{.status.user.username}' -f - 2>/dev/null <<EOF
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "$(tr -d '\n' < $tf)"
EOF
)
fi
[ "$user" = "$sa" ] && p "token authenticates as deployer" || f "token authenticates as deployer"
b=$(cut -d. -f2 < $tf 2>/dev/null | tr '_-' '/+')
case $(( $(printf %s "$b" | wc -c) % 4 )) in 2) b="$b==" ;; 3) b="$b=" ;; esac
claims=$(printf %s "$b" | base64 -d 2>/dev/null)
exp=$(printf %s "$claims" | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')
iat=$(printf %s "$claims" | sed -n 's/.*"iat":\([0-9]*\).*/\1/p')
[ -n "$exp" ] && [ -n "$iat" ] && [ $((exp - iat)) -eq 7200 ] && p "token lifetime is 2h" || f "token lifetime is 2h"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Read-only node access for a group

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Members of the group `arx-ops` need to inspect nodes and PersistentVolumes across the cluster without changing anything. Create a ClusterRole named `arx-node-reader` that allows `get`, `list` and `watch` on nodes and persistentvolumes, and grant it to the group `arx-ops` with a ClusterRoleBinding named `arx-node-reader-ops`. The group must not gain any other access.

<details>
<summary>💡 Hints</summary>

- Nodes and PersistentVolumes belong to no namespace, so a Role cannot grant them. You need a ClusterRole and a ClusterRoleBinding.
- Test as a made-up user in the group: `kubectl auth can-i list nodes --as=amara --as-group=arx-ops`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl create clusterrole arx-node-reader --verb=get,list,watch --resource=nodes,persistentvolumes
kubectl create clusterrolebinding arx-node-reader-ops --clusterrole=arx-node-reader --group=arx-ops
kubectl auth can-i list nodes --as=amara --as-group=arx-ops
```

**Explanation:**

- `create clusterrole` — A ClusterRole, because nodes and PersistentVolumes are cluster-scoped: they belong to no namespace, so a Role cannot name them.
- `create clusterrolebinding` — Grants it cluster-wide to the group `arx-ops`. `--group` covers every user in that group, whatever their name.
- `kubectl auth can-i list nodes` — Tests as a made-up user who is in the group. `yes` means the group binding works.

**Notes:** A RoleBinding to this ClusterRole would not work. A RoleBinding only grants access inside its own namespace, and nodes have no namespace. The grader tests by group, so any user name passes. Check with a made-up `--as` plus `--as-group=arx-ops`. Then check once without the group, to make sure the binding is not on a user.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
can() { kubectl auth can-i "$@" 2>/dev/null | head -1 | awk '{print $1}'; }
g="--as=amara --as-group=arx-ops"

[ "$(kubectl get clusterrolebinding arx-node-reader-ops -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)" = "ClusterRole/arx-node-reader" ] && p "binding points at ClusterRole arx-node-reader" || f "binding points at ClusterRole arx-node-reader"
kubectl get clusterrolebinding arx-node-reader-ops -o jsonpath='{range .subjects[*]}{.kind}/{.name}{" "}{end}' 2>/dev/null | grep -qw 'Group/arx-ops' && p "subject is Group arx-ops" || f "subject is Group arx-ops"
[ "$(can list nodes $g)" = "yes" ] && p "group can list nodes" || f "group can list nodes"
[ "$(can get nodes $g)" = "yes" ] && p "group can get nodes" || f "group can get nodes"
[ "$(can watch persistentvolumes $g)" = "yes" ] && p "group can watch persistentvolumes" || f "group can watch persistentvolumes"
[ "$(can delete nodes $g)" = "no" ] && p "group cannot delete nodes" || f "group cannot delete nodes"
[ "$(can patch nodes $g)" = "no" ] && p "group cannot patch nodes" || f "group cannot patch nodes"
[ "$(can list pods -A $g)" = "no" ] && p "group cannot list pods" || f "group cannot list pods"
[ "$(can list nodes --as=amara)" = "no" ] && p "access comes from the group, not the user" || f "access comes from the group, not the user"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Take back cluster-admin from a service account

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

The ServiceAccount `log-shipper` in namespace `arx-rbac-fix` was given cluster-admin to get a log collector working. It only needs to read Pods and their logs in its own namespace. Remove the excess access, then grant exactly `get`, `list`, `watch` on Pods and `get` on Pod logs in `arx-rbac-fix`, using a Role named `log-reader` and a RoleBinding named `log-shipper-read`. Do not delete the ServiceAccount.

<details>
<summary>💡 Hints</summary>

- Find every binding that names the account: `kubectl get clusterrolebindings,rolebindings -A -o wide | grep log-shipper`.
- Pod logs are the subresource `pods/log`. Test it with `kubectl auth can-i get pods --subresource=log`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get clusterrolebindings -o wide | grep log-shipper || true
kubectl delete clusterrolebinding arx-log-shipper-admin
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: log-reader
  namespace: arx-rbac-fix
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
YAML
kubectl -n arx-rbac-fix create rolebinding log-shipper-read --role=log-reader --serviceaccount=arx-rbac-fix:log-shipper
kubectl auth can-i delete pods -n arx-rbac-fix --as=system:serviceaccount:arx-rbac-fix:log-shipper || true
```

**Explanation:**

- `kubectl get clusterrolebindings -o wide` — Finds every cluster-wide binding that names the account; `-o wide` adds the USERS, GROUPS and SERVICEACCOUNTS columns. `|| true` keeps a script going when grep finds nothing.
- `kubectl delete clusterrolebinding` — Removes the excess access. RBAC has no deny rules, so deleting the binding is the only way to take cluster-admin back. The ServiceAccount itself stays.
- `resources: ["pods"]` — Rule one: read Pods.
- `resources: ["pods/log"]` — Rule two: `get` on the `pods/log` subresource, which is what `kubectl logs` needs. Access to `pods` alone would not include it.
- `create rolebinding log-shipper-read` — Binds the narrow Role in the account's own namespace only.
- `kubectl auth can-i delete pods` — Should print `no`. `can-i` exits 1 on no, so `|| true` keeps that from looking like a failure.

**Notes:** `kubectl get clusterrolebindings -o wide` has a SERVICEACCOUNTS column. It is the quickest way to see who is bound to `cluster-admin`. The one-line Role `kubectl -n arx-rbac-fix create role log-reader --verb=get,list,watch --resource=pods,pods/log` also passes. It adds list and watch on `pods/log`, which do nothing. Adding a narrow Role while the ClusterRoleBinding still exists changes nothing, because RBAC permissions only add up.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-rbac-fix
sa=system:serviceaccount:arx-rbac-fix:log-shipper
can() { kubectl auth can-i "$@" --as=$sa 2>/dev/null | head -1 | awk '{print $1}'; }

kubectl -n $ns get serviceaccount log-shipper >/dev/null 2>&1 && p "serviceaccount still exists" || f "serviceaccount still exists"
kubectl get clusterrolebindings -o jsonpath='{range .items[*]}{range .subjects[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}{end}' 2>/dev/null | grep -qx 'ServiceAccount/arx-rbac-fix/log-shipper' && f "no ClusterRoleBinding names log-shipper" || p "no ClusterRoleBinding names log-shipper"
[ "$(kubectl -n $ns get rolebinding log-shipper-read -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)" = "Role/log-reader" ] && p "log-shipper-read points at Role log-reader" || f "log-shipper-read points at Role log-reader"
[ "$(can list pods -n $ns)" = "yes" ] && p "can list pods" || f "can list pods"
[ "$(can watch pods -n $ns)" = "yes" ] && p "can watch pods" || f "can watch pods"
[ "$(can get pods --subresource=log -n $ns)" = "yes" ] && p "can read pod logs" || f "can read pod logs"
[ "$(can delete pods -n $ns)" = "no" ] && p "cannot delete pods" || f "cannot delete pods"
[ "$(can get secrets -n $ns)" = "no" ] && p "cannot read secrets" || f "cannot read secrets"
[ "$(can create deployments.apps -n $ns)" = "no" ] && p "cannot create deployments" || f "cannot create deployments"
[ "$(can list pods -n default)" = "no" ] && p "no access outside arx-rbac-fix" || f "no access outside arx-rbac-fix"
[ "$(can list nodes)" = "no" ] && p "no cluster-scoped access" || f "no cluster-scoped access"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
