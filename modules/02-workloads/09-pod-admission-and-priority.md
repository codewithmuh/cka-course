# Pod admission, Pod Security and priority

> **Module 2** · Lesson 2.9 · 40 minutes

Where admission sits in the API server and which plugins are on, how Pod Security labels block unsafe Pods, and how PriorityClasses decide which Pods go first.

## Learning Objectives

- You can find the admission plugins a kube-apiserver enables in its static Pod manifest, and say what the common ones do.
- You can enforce a Pod Security Standard on a namespace with labels, and write a Pod that the restricted level admits.
- You can create a PriorityClass, use it from a Pod, and predict when the scheduler will preempt other Pods.


Before the API server saves a new Pod, it sends the request through **admission**. Admission is a set of plugins that can fill in values, change the request, or reject it. You have already met two of them. LimitRange and ResourceQuota from the [requests and limits lesson](/cka/workloads/resources-limits-quotas) are admission plugins.

Example: your team's namespace must never run Pods as root. A Pod Security label on the namespace makes the API server refuse such Pods before they ever start. This lesson covers how plugins are switched on, Pod Security Admission, and the Priority plugin, which decides which Pods the scheduler serves first.

## Where admission sits

Every change you send to the API server goes through the same steps, in order:

**The path of a request**

*Any step can reject the request, and kubectl prints the reason.*

`Authentication` — who are you? → `Authorization` — are you allowed? (RBAC) → `Admission` — change, then check the object → `etcd` — the object is saved

- Admission works in two passes. First, **mutating** plugins may change the object, for example to fill in defaults. Then **validating** plugins may only accept or reject it.
- Built-in plugins are part of kube-apiserver. The flag `--enable-admission-plugins` switches more of them on; it *adds* to a default set.
- The flag `--disable-admission-plugins` turns off plugins from the default set.

**Which plugins does this API server run?**

```bash
# Explicitly enabled plugins (exam: ssh to the control plane node, then sudo grep)
docker exec cka-control-plane grep -- --enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml
#    - --enable-admission-plugins=NodeRestriction

# The same flag from the API, without a node shell
kubectl -n kube-system describe pod -l component=kube-apiserver | grep admission
```

<details>
<summary>Line-by-line explanation</summary>

- `docker exec cka-control-plane` — In the lab the control plane node is a Docker container, so `docker exec` runs grep inside it. The `--` tells grep that the next word is the search text, even though it starts with dashes.
- `=NodeRestriction` — Sample output: kubeadm enables only NodeRestriction explicitly. Everything else comes from the built-in defaults.
- `describe pod -l component=kube-apiserver` — The API server runs as a static Pod labeled `component=kube-apiserver`. describe prints its command line, flags included.

</details>

These are the plugins worth knowing for this exam:

| Plugin | On by default | What it does |
| --- | --- | --- |
| `NamespaceLifecycle` | Yes | Rejects objects in a namespace that does not exist or is being deleted. Also stops anyone from deleting default, kube-system and kube-public |
| `LimitRanger` | Yes | Applies LimitRange defaults, minimums and maximums |
| `ResourceQuota` | Yes | Rejects objects that would go over a quota |
| `PodSecurity` | Yes | Enforces Pod Security Standards from namespace labels |
| `Priority` | Yes | Turns `priorityClassName` into a number in `spec.priority` |
| `NodeRestriction` | No, but kubeadm turns it on | Lets a kubelet change only its own Node and the Pods on it |

Other default plugins do jobs you meet in other lessons:

- The default ServiceAccount for every Pod, in [RBAC](/cka/architecture/rbac).
- The default StorageClass for new claims, in [StorageClasses](/cka/storage/storage-classes-dynamic-provisioning).
- The 5-minute tolerations every Pod gets, in [Worker node failures](/cka/troubleshooting/worker-node-failures).

To change the flag, you edit the API server's static Pod file. How that works, and how to do it safely, is in [Control plane and node components](/cka/architecture/control-plane-and-nodes).

## Pod Security Admission

Some Pod settings are dangerous: running as root, using the node's network, or mounting the node's disk. Kubernetes defines three **Pod Security Standards**, from loose to strict:

| Level | Allows |
| --- | --- |
| `privileged` | Everything. No checks at all |
| `baseline` | Most apps. It blocks privileged containers, the node's own namespaces (network, PID, IPC), hostPath volumes, host ports, and dangerous added capabilities |
| `restricted` | Baseline, plus: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, a `RuntimeDefault` or `Localhost` seccomp profile, and only safe volume types (configMap, secret, emptyDir, projected, downwardAPI, PVC and CSI) |

A namespace picks a level with a label of the form `pod-security.kubernetes.io/: `. There are three modes:

| Mode | What happens to a Pod that breaks the level |
| --- | --- |
| `enforce` | It is rejected |
| `warn` | It is created, and whoever created it sees a warning |
| `audit` | It is created, and a note is added to the API server's audit log |

One trap: `warn` and `audit` also check the Pod templates inside Deployments and other workloads, but `enforce` checks only Pods. So a Deployment whose Pods are rejected looks fine. You only see the problem in its ReplicaSet's events.

**Label a namespace, but look first**

```bash
# Dry run on the server: lists existing Pods that would violate, changes nothing
kubectl label --dry-run=server --overwrite ns wl-psa pod-security.kubernetes.io/enforce=restricted

kubectl label --overwrite ns wl-psa pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
kubectl get ns wl-psa --show-labels

# A rejected Pod names every missing field:
#   violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (...), unrestricted capabilities (...),
#   runAsNonRoot != true (...), seccompProfile (...)
```

<details>
<summary>Line-by-line explanation</summary>

- `--dry-run=server` — `server`, unlike `client`, means the API server really evaluates the change, which is how it can warn about existing Pods. `--overwrite` lets you replace a value the label already has.
- `pod-security.kubernetes.io/warn=restricted` — Two labels in one command: `enforce` rejects violating Pods, and `warn` prints a warning to whoever creates one.
- `get ns wl-psa --show-labels` — Prints the namespace's labels, so you can check both keys letter by letter.
- `violates PodSecurity` — Sample rejection: each item is one setting to add to the Pod, as the next block shows.

</details>

Here is a Pod with every setting the restricted level asks for:

**A Pod the restricted level admits**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tidy
  namespace: wl-psa
spec:
  securityContext:              # Pod level: applies to every container
    runAsNonRoot: true
    runAsUser: 1000             # needed when the image would run as root
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:          # container level: these two only exist here
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

<details>
<summary>Line-by-line explanation</summary>

- `securityContext:` — securityContext exists at two levels. Pod-level settings apply to every container; a container's own securityContext overrides them for that container.
- `runAsNonRoot: true` — The kubelet refuses to start any container that would run as user 0, root.
- `runAsUser: 1000` — Runs the processes as user ID 1000. busybox has no user with that ID in its files, which is fine: Linux only needs the number.
- `seccompProfile:` — seccomp filters which Linux system calls the container may make. `RuntimeDefault` uses the container runtime's standard filter.
- `allowPrivilegeEscalation: false` — Stops a process from gaining more privileges than its parent, for example through setuid programs.
- `drop: ["ALL"]` — Removes every Linux capability, the separate pieces of root's power. Restricted lets you add back only NET_BIND_SERVICE.

</details>

- `runAsNonRoot: true` alone is not enough for images that run as root by default, such as busybox and nginx. The API admits the Pod, but then the kubelet refuses to start the container: *container has runAsNonRoot and image will run as root*. Set a numeric `runAsUser`, or use an image built to run as a normal user.
- Labeling a namespace never removes Pods that are already running. That is why the server-side dry run above is the honest check.

## PriorityClass and preemption

When the cluster is full, which Pods go first? A **PriorityClass** gives Pods a number: the higher the number, the more important the Pod. Example: your checkout Pods get a higher priority than a nightly report, so checkout always gets room first.

**A class and a Pod that uses it**

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: business-critical
value: 1000000                   # higher wins; user classes go up to 1,000,000,000
globalDefault: false             # true makes it the default for Pods without a class
preemptionPolicy: PreemptLowerPriority   # or Never
description: "Customer-facing services"
---
apiVersion: v1
kind: Pod
metadata:
  name: checkout
  namespace: wl-prio
spec:
  priorityClassName: business-critical
  containers:
    - name: nginx
      image: nginx:1.27
# Imperative: kubectl create priorityclass business-critical --value=1000000 --description="Customer-facing services"
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: scheduling.k8s.io/v1` — PriorityClass is in the `scheduling.k8s.io` group and is cluster-wide, which is why its metadata has no namespace.
- `value: 1000000` — A PriorityClass has no `spec`: `value` and the fields below sit at the top level, beside `metadata`.
- `---` — Separates two objects in one YAML file. `kubectl apply -f` creates both, in order.
- `priorityClassName: business-critical` — The Pod names the class. At creation, admission copies the class's value into `spec.priority`.
- `# Imperative:` — The same class in one command. Add `--preemption-policy=Never` or `--global-default` when a task asks for them.

</details>

**How a Pod gets its priority**

- The Pod names a class in `priorityClassName`.
- When the Pod is created, the Priority plugin copies the class's `value` into `spec.priority`.
- A Pod that names a class that does not exist is rejected. A Pod with no class gets the global default class, or 0.
- A class's `value` cannot be edited: delete the class and create it again. Pods that already exist keep the priority they were given.

**Preemption**

- The scheduler serves higher-priority Pods first.
- If such a Pod fits on no node, the scheduler looks for a node where removing lower-priority Pods would make room. It then stops those Pods gracefully. This is called **preemption**.
- `preemptionPolicy: Never` keeps the Pod's place at the front of the queue, but it never removes anyone.

**Preemption, step by step**

`High-priority Pod` — Pending: no node has room → `Scheduler` — finds lower-priority Pods to remove → `Lower-priority Pods` — stopped to make room → `High-priority Pod` — scheduled on that node

> [!IMPORTANT] **What the grader reads**
> For Pod Security, the grader reads the exact namespace label keys and values. One typo in `pod-security.kubernetes.io/enforce` and nothing is enforced, without any error. It also checks that the Pod is Running with the required `securityContext`. For priority, it reads the PriorityClass `value` and the Pod's `spec.priority`. That is only filled in if the class existed when the Pod was created, so create the class first. For flag questions, it compares your answer file with the live kube-apiserver flags.

## 📝 Key Takeaways

- Every request passes authentication, then authorization, then admission, before it is saved in etcd.
- `--enable-admission-plugins` adds to a default set of plugins. kubeadm adds only NodeRestriction.
- The namespace label `pod-security.kubernetes.io/enforce=restricted` rejects unsafe Pods. `warn` only warns.
- A restricted Pod needs `runAsNonRoot` (plus a `runAsUser` for root images), a seccomp profile, no privilege escalation, and all capabilities dropped.
- A PriorityClass gives Pods a number. Higher Pods are scheduled first and may preempt lower ones, unless `preemptionPolicy: Never`.

**📖 Official documentation:**

- [Admission Control in Kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) *(search: "admission controllers")*
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) *(search: "pod security admission")*
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) *(search: "pod security standards restricted")*
- [Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/) *(search: "priority preemption")*

---

### 🎯 Task: Enforce the restricted standard and make a Pod comply

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

Configure namespace `wl-psa` so that the API server rejects Pods that violate the `restricted` Pod Security Standard and also warns about such violations. Then create the Pod defined in `/tmp/cka/wl-psa/secure.yaml`. As written it will be rejected: change only its security settings until it is admitted and running. Keep its name, image and command.

<details>
<summary>💡 Hints</summary>

- Put two labels on the namespace: `pod-security.kubernetes.io/enforce=restricted` and `pod-security.kubernetes.io/warn=restricted`.
- Try to apply the file first: the error lists every field you must set. busybox runs as root unless you also set `runAsUser`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl label --overwrite ns wl-psa pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
cat > /tmp/cka/wl-psa/secure.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: secure
  namespace: wl-psa
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "id; sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
YAML
kubectl apply -f /tmp/cka/wl-psa/secure.yaml
kubectl -n wl-psa wait --for=condition=Ready pod/secure --timeout=120s
```

**Explanation:**

- `kubectl label --overwrite ns wl-psa` — Two labels: `enforce=restricted` rejects violating Pods and `warn=restricted` also warns about them. `--overwrite` replaces any value already set.
- `cat > /tmp/cka/wl-psa/secure.yaml` — Rewrites the task's file with the security settings added. In the exam you would edit it in vim; name, image and command stay as they were.
- `runAsNonRoot: true` — Required by restricted. It needs `runAsUser: 1000` beside it, because busybox would otherwise run as root and be refused at start.
- `seccompProfile:` — The RuntimeDefault seccomp profile that restricted asks for.
- `allowPrivilegeEscalation: false` — Container-level settings: no privilege escalation and every capability dropped, the last two restricted requirements.
- `kubectl apply -f` — Applies the fixed file; this time admission lets the Pod through.
- `wait --for=condition=Ready` — Ready proves the kubelet started the container too, which runAsNonRoot can still block after admission.

**Notes:** Label the namespace first. Then apply the original file once, to read the rejection: it names all four restricted requirements. Fix them in vim and apply again. Is the Pod admitted, but showing `CreateContainerConfigError`? Then `kubectl describe pod secure -n wl-psa` will say the image runs as root: that is the missing `runAsUser`. `kubectl logs secure -n wl-psa` prints the `id` output, `uid=1000`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-psa
g="kubectl -n $ns get pod secure -o jsonpath"

kubectl get ns -l pod-security.kubernetes.io/enforce=restricted -o name 2>/dev/null | grep -qx namespace/wl-psa && p "wl-psa enforces restricted" || f "wl-psa enforces restricted"
kubectl get ns -l pod-security.kubernetes.io/warn=restricted -o name 2>/dev/null | grep -qx namespace/wl-psa && p "wl-psa warns on restricted" || f "wl-psa warns on restricted"
kubectl -n $ns get pod secure >/dev/null 2>&1 && p "pod secure exists" || f "pod secure exists"
[ "$($g='{.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image busybox:1.36" || f "image busybox:1.36"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
[ "$($g='{.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null)" = "false" ] && p "allowPrivilegeEscalation false" || f "allowPrivilegeEscalation false"
$g='{.spec.containers[0].securityContext.capabilities.drop}' 2>/dev/null | grep -q '"ALL"' && p "drops ALL capabilities" || f "drops ALL capabilities"
echo "$($g='{.spec.securityContext.runAsNonRoot} {.spec.containers[0].securityContext.runAsNonRoot}' 2>/dev/null)" | grep -q true && p "runAsNonRoot true" || f "runAsNonRoot true"
echo "$($g='{.spec.securityContext.seccompProfile.type} {.spec.containers[0].securityContext.seccompProfile.type}' 2>/dev/null)" | grep -qE 'RuntimeDefault|Localhost' && p "seccomp profile set" || f "seccomp profile set"
uid="$(kubectl -n $ns exec secure -- id -u 2>/dev/null)"
[ -n "$uid" ] && [ "$uid" != "0" ] && p "container runs as a non-root uid" || f "container runs as a non-root uid"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A non-preempting PriorityClass

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Create a PriorityClass `wl-batch-high` with value `100000`. It must not be the cluster-wide default, and Pods using it must never preempt other Pods. Then create a Pod `important` in namespace `wl-prio` (image `nginx:1.27`) that uses this class.

<details>
<summary>💡 Hints</summary>

- `kubectl create priorityclass wl-batch-high --value=100000 --preemption-policy=Never`
- The Pod needs `spec.priorityClassName`. `spec.priority` is filled in for you.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: wl-batch-high
value: 100000
globalDefault: false
preemptionPolicy: Never
description: "High priority without preemption"
---
apiVersion: v1
kind: Pod
metadata:
  name: important
  namespace: wl-prio
spec:
  priorityClassName: wl-batch-high
  containers:
    - name: nginx
      image: nginx:1.27
YAML
kubectl -n wl-prio wait --for=condition=Ready pod/important --timeout=120s
```

**Explanation:**

- `value: 100000` — The class's priority. Pods with higher numbers are scheduled first.
- `globalDefault: false` — Not the default for Pods that name no class.
- `preemptionPolicy: Never` — Pods of this class move ahead in the scheduling queue but never evict other Pods to make room.
- `priorityClassName: wl-batch-high` — The class must exist when the Pod is created. It comes first in this file, and kubectl creates the objects in order.
- `wait --for=condition=Ready` — Waits for the Pod. Its `spec.priority` should now read 100000.

**Notes:** With commands, create the class first: `kubectl create priorityclass wl-batch-high --value=100000 --preemption-policy=Never`. Then generate the Pod with `kubectl run important -n wl-prio --image=nginx:1.27 --dry-run=client -o yaml`, and add `priorityClassName` under `spec`. Check it with `kubectl get pod important -n wl-prio -o jsonpath='{.spec.priority} {.spec.preemptionPolicy}'`, which should print `100000 Never`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-prio
pc="kubectl get priorityclass wl-batch-high -o jsonpath"
g="kubectl -n $ns get pod important -o jsonpath"

kubectl get priorityclass wl-batch-high >/dev/null 2>&1 && p "priorityclass wl-batch-high exists" || f "priorityclass wl-batch-high exists"
[ "$($pc='{.value}' 2>/dev/null)" = "100000" ] && p "value 100000" || f "value 100000"
[ "$($pc='{.preemptionPolicy}' 2>/dev/null)" = "Never" ] && p "preemptionPolicy Never" || f "preemptionPolicy Never"
[ "$($pc='{.globalDefault}' 2>/dev/null)" != "true" ] && p "not the global default" || f "not the global default"
[ "$($g='{.spec.priorityClassName}' 2>/dev/null)" = "wl-batch-high" ] && p "pod uses wl-batch-high" || f "pod uses wl-batch-high"
[ "$($g='{.spec.priority}' 2>/dev/null)" = "100000" ] && p "pod priority 100000" || f "pod priority 100000"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Report the enabled admission plugins

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Find the admission plugins that this cluster's kube-apiserver enables explicitly, in addition to its built-in defaults, as configured in its static Pod manifest on the control plane node. Write the plugin names to `/tmp/cka/admission-plugins.txt`, one per line. (Lab: `docker exec cka-control-plane …`; exam: `ssh` to the control plane node.)

<details>
<summary>💡 Hints</summary>

- The manifest is `/etc/kubernetes/manifests/kube-apiserver.yaml`, and the flag is `--enable-admission-plugins`.
- The value is a comma-separated list. `tr ',' '\n'` puts one name per line.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
docker exec cka-control-plane grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/.*--enable-admission-plugins=//' | tr ',' '\n' > /tmp/cka/admission-plugins.txt
cat /tmp/cka/admission-plugins.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Makes sure the answer folder exists.
- `docker exec cka-control-plane grep` — grep finds the flag line in the manifest, `sed` deletes everything up to and including the `=`, and `tr ',' '\n'` turns each comma into a newline: one plugin per line, saved to the file.
- `cat /tmp/cka/admission-plugins.txt` — Check the file. On this kubeadm lab it should hold the single line NodeRestriction.

**Notes:** On the exam, `ssh` to the control plane, run `sudo grep enable-admission /etc/kubernetes/manifests/kube-apiserver.yaml`, and write the file on the machine the task names. Without a node shell, `kubectl -n kube-system describe pod -l component=kube-apiserver | grep admission` shows the same flag. On a kubeadm cluster the answer is usually just `NodeRestriction`. Defaults such as `NamespaceLifecycle` or `PodSecurity` are not in the flag, and that is exactly what the task asked you to leave out.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

live="$(kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{range .items[0].spec.containers[0].command[*]}{@}{" "}{end}' 2>/dev/null | xargs -n1 | grep -- '^--enable-admission-plugins=' | cut -d= -f2 | tr ',' ' ' | xargs -n1 | sort | xargs)"
got="$(tr ',' ' ' < /tmp/cka/admission-plugins.txt 2>/dev/null | xargs -n1 | sort | xargs)"
[ -n "$live" ] && p "read --enable-admission-plugins from the live kube-apiserver" || f "read --enable-admission-plugins from the live kube-apiserver"
[ -s /tmp/cka/admission-plugins.txt ] && p "/tmp/cka/admission-plugins.txt exists" || f "/tmp/cka/admission-plugins.txt exists"
[ -n "$got" ] && [ "$got" = "$live" ] && p "file lists exactly: $live" || f "file lists exactly the enabled plugins"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
