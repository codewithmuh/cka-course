# Requests, limits, LimitRange and ResourceQuota

> **Module 2** · Lesson 2.4 · 40 minutes

What requests and limits do, how they set a Pod's QoS class, and how LimitRange and ResourceQuota set rules for a whole namespace.

## Learning Objectives

- You can set requests and limits in the right units, and predict the QoS class Kubernetes will give the Pod.
- You can say what happens when a container goes over its CPU limit, and when it goes over its memory limit.
- You can create a LimitRange that fills in and caps container resources, and a ResourceQuota that caps a namespace, and read both with kubectl describe.


Every container uses CPU and memory on its node. You tell Kubernetes how much each container needs, and the most it may use. Without that, one busy app can starve the other apps on the same node.

On the exam, expect a task that wants exact resource values on a Pod or a Deployment. Expect another where a namespace rule decides whether a Pod may be created at all. Both are quick if you know the field names and the units.

## Requests and limits: two different jobs

**Request versus limit**

*The scheduler only looks at requests. Limits only matter once the container runs.*

`Request` — what the container is promised
  - `Used by the scheduler` — to pick a node with room   `Limit` — the most it may use
  - `Over the CPU limit` — slowed down (throttled)
  - `Over the memory limit` — killed (OOMKilled)

- A **request** is what the scheduler reserves. A Pod fits on a node only if the requests of all Pods there stay within what the node can offer. Real usage plays no part in that choice.
- A **limit** is enforced while the container runs. Over its CPU limit, a container is *throttled*: it keeps running, just slower. Over its memory limit, it is *killed*, and the Pod shows `OOMKilled`.

Example: your Django app requests 100m CPU and 64Mi memory, with limits of 250m and 128Mi. The scheduler looks for a node with at least 100m CPU and 64Mi memory not yet reserved. Later, a memory leak takes the app past 128Mi, so it is killed and restarted.

Reading the signs of a killed container, such as exit code 137 and `CrashLoopBackOff`, is covered in [Application failures](/cka/troubleshooting/application-failures).

CPU and memory use different units, and the letters matter:

| Write | Means | Trap |
| --- | --- | --- |
| `cpu: 1` | One CPU core | `cpu: 0.5` is stored as `500m`. Both are fine |
| `cpu: 250m` | A quarter of a core. `m` means a thousandth (millicores) | `1000m` is one whole core |
| `memory: 128Mi` | 128 mebibytes (128 × 1,048,576 bytes) | `128M` is 128 × 1,000,000 bytes, about 5% less |
| `memory: 1Gi` | 1024 Mi | `memory: 128m` means 0.128 *bytes*. Lowercase m is a thousandth |

**Per-container resources**

```yaml
    spec:
      containers:
        - name: api
          image: nginx:1.27
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 128Mi
```

<details>
<summary>Line-by-line explanation</summary>

- `resources:` — Set per container, not per Pod. `requests` is what the scheduler reserves on a node; `limits` is the most the container may use.
- `cpu: 100m` — 100 millicores, a tenth of one CPU core.
- `memory: 64Mi` — 64 mebibytes. Write `Mi` or `Gi`; a lowercase `m` would mean thousandths of a byte.
- `limits:` — Above 250m of CPU the container is slowed down. Above 128Mi of memory it is killed as OOMKilled. Requests lower than limits make the Pod Burstable.

</details>

You can also set them without an editor, then check what the Pod got:

**Set and inspect without opening an editor**

```bash
kubectl -n wl-res set resources deploy/api -c api --requests=cpu=100m,memory=64Mi --limits=cpu=250m,memory=128Mi
kubectl -n wl-res get pod -l app=api -o jsonpath='{.items[0].spec.containers[0].resources}'; echo
kubectl -n wl-res get pod -l app=api -o jsonpath='{.items[0].status.qosClass}'; echo
```

<details>
<summary>Line-by-line explanation</summary>

- `set resources deploy/api` — Sets requests and limits on container `api` without an editor. Each flag takes comma-separated `resource=value` pairs. It edits the Pod template, so it starts a rollout.
- `containers[0].resources}` — Prints the resources a running Pod actually got. `items[0]` is the first Pod the label matches. Handy for checking that a LimitRange filled in defaults.
- `status.qosClass` — Prints the QoS class Kubernetes gave the Pod: Guaranteed, Burstable or BestEffort.

</details>

To see how much of a node is already reserved, or how much a Pod really uses, see [Monitoring resource usage](/cka/troubleshooting/monitoring-resource-usage).

Three rules about missing values and changes:

- A limit but no request: the request is set equal to the limit.
- A request but no limit: there is no limit, unless a LimitRange adds one.
- Changing resources on a Deployment edits its Pod template, so it starts a rollout.

## QoS classes

From your requests and limits, Kubernetes gives each Pod a **QoS class** (quality of service). The class decides which Pods a node removes first when it runs out of memory.

| Class | Rule | When the node runs short of memory |
| --- | --- | --- |
| `Guaranteed` | Every container has CPU and memory limits, and its requests equal its limits | Evicted last |
| `Burstable` | Not Guaranteed, but at least one container has a CPU or memory request or limit | Evicted after BestEffort |
| `BestEffort` | No container has any request or limit | Evicted first |

The class is set when the Pod is created, and stored in `status.qosClass`. Do not mix up the two ways memory can stop your app:

- **OOMKilled**: one container went over its *own* memory limit, so the kernel killed that container.
- **Evicted**: the whole *node* ran short of memory, so the kubelet removed whole Pods, BestEffort ones first. This is covered in [Worker node failures](/cka/troubleshooting/worker-node-failures).

## LimitRange: defaults and bounds for each container

A **LimitRange** sets rules for every container in one namespace. It fills in requests and limits for containers that set none. It also rejects containers that ask for too much or too little. Example: in your team's namespace, every container gets 100m CPU unless it asks for something else.

**Container defaults and a ceiling for one namespace**

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: wl-quota
spec:
  limits:
    - type: Container
      default:            # limit applied when a container sets none
        cpu: 200m
        memory: 256Mi
      defaultRequest:     # request applied when a container sets none
        cpu: 100m
        memory: 128Mi
      max:                # anything above is rejected at admission
        cpu: 500m
        memory: 512Mi
      min:
        cpu: 50m
        memory: 32Mi
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: LimitRange` — A namespaced object. The LimitRanger admission plugin applies it to every new Pod in its namespace.
- `- type: Container` — `limits` is a list of rules. An entry of type Container applies to each container on its own, not to the Pod's total.
- `default:` — Watch the names: `default` is the default *limit*, and `defaultRequest` the default request. There is no field called defaultLimit.
- `min:` — The lower bound: a container that asks for less than 50m CPU or 32Mi memory is rejected too.

</details>

- A LimitRange is applied when a Pod is *created*. Pods that are already running are never changed.
- There is no `kubectl create limitrange` command. You write the YAML yourself.

## ResourceQuota: a budget for the whole namespace

A **ResourceQuota** is a budget for a whole namespace. It caps the total that all Pods there may request, and how many objects may exist. Example: the team's namespace may run at most 4 Pods, and together they may request at most 1 CPU.

|  | LimitRange | ResourceQuota |
| --- | --- | --- |
| Applies to | Each container, one at a time | The namespace as a whole |
| What it does | Fills in defaults, sets a minimum and a maximum | Caps the total, and counts objects |
| Example | "Every container gets 100m CPU by default" | "All Pods together may request at most 1 CPU" |

**Create, then read used against hard**

```bash
kubectl -n wl-quota create quota team-quota --hard=pods=4,requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi
kubectl -n wl-quota create quota objects --hard=count/deployments.apps=3,services=5,configmaps=10,persistentvolumeclaims=2
kubectl -n wl-quota describe quota
kubectl describe ns wl-quota          # quotas and limit ranges together
```

<details>
<summary>Line-by-line explanation</summary>

- `create quota team-quota` — `quota` is short for resourcequota. `--hard` lists the caps: at most 4 Pods, and ceilings on the summed requests and limits of all Pods in the namespace.
- `create quota objects` — Caps on how many objects may exist. `count/deployments.apps` is the general `count/.` form; core types such as services and configmaps can be named directly.
- `describe quota` — Shows Used against Hard for every quota in the namespace. Used is what existing objects already take.
- `describe ns` — One command shows the namespace's status, its quotas and its LimitRanges.

</details>

- Once a quota covers `requests.cpu` or `limits.memory`, every new Pod in the namespace must set those values. Otherwise it is rejected with *must specify limits.cpu*.
- That is why a quota almost always comes with a LimitRange: the LimitRange fills those values in.
- A quota is checked when an object is created. Lowering it never removes what already exists; it only blocks new objects.

**What happens to a new Pod in a namespace with both**

*The LimitRange fills in the values first, so the quota has numbers to check.*

`New Pod` — no resources set → `LimitRange` — fills in requests and limits → `ResourceQuota` — checks the namespace budget → `Pod created` — or rejected if over budget

> [!IMPORTANT] **The quota trap, and what the grader reads**
> A Deployment shows `0/3`, and there are no Pods to describe? Then the Pods were never created. The reason is an event on the **ReplicaSet**: `kubectl describe rs -l app=` shows *FailedCreate … exceeded quota*. For resource tasks, the grader reads `spec.containers[].resources` as amounts, not as text. So `0.25` and `250m` are equal, but `128M` and `128Mi` are not. It also reads `status.qosClass` and the LimitRange or quota `spec`.

## 📝 Key Takeaways

- A request is reserved, and the scheduler uses it to pick a node. A limit is a ceiling, enforced while the container runs.
- Over the CPU limit, a container is slowed down. Over the memory limit, it is killed (OOMKilled).
- Use `m` for CPU (`250m`), and `Mi` or `Gi` for memory (`128Mi`).
- QoS class: requests equal to limits everywhere is Guaranteed, nothing set is BestEffort, and anything else is Burstable.
- A LimitRange sets defaults and bounds for each container. A ResourceQuota sets a budget for the whole namespace. Both act only when an object is created.

**📖 Official documentation:**

- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) *(search: "resource management for pods")*
- [Configure Quality of Service for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/) *(search: "quality of service")*
- [Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/) *(search: "limit range")*
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) *(search: "resource quotas")*

---

### 🎯 Task: Give a Pod exact requests and limits

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `wl-res` create a Pod `gateway` with one container named `httpd` (image `httpd:2.4`). The container requests `100m` CPU and `64Mi` memory and is limited to `250m` CPU and `128Mi` memory. When it is running, write the QoS class Kubernetes assigned to the Pod (the class name only) to `/tmp/cka/wl-res-qos.txt`.

<details>
<summary>💡 Hints</summary>

- Start with `kubectl run gateway --image=httpd:2.4 --dry-run=client -o yaml`. Rename the container, then add a `resources` block.
- Read the class from `status.qosClass` instead of working it out. Requests below limits is not Guaranteed.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gateway
  namespace: wl-res
spec:
  containers:
    - name: httpd
      image: httpd:2.4
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 250m
          memory: 128Mi
YAML
kubectl -n wl-res wait --for=condition=Ready pod/gateway --timeout=120s
mkdir -p /tmp/cka
kubectl -n wl-res get pod gateway -o jsonpath='{.status.qosClass}' > /tmp/cka/wl-res-qos.txt
```

**Explanation:**

- `cat <<'YAML'` — The Pod manifest in a heredoc, applied straight from the pipe.
- `- name: httpd` — The question names the container `httpd`. `kubectl run gateway` would have named it `gateway`, after the Pod.
- `requests:` — What the scheduler reserves: 100m CPU and 64Mi memory.
- `limits:` — The ceiling: 250m CPU and 128Mi memory. Requests below limits make the Pod Burstable.
- `wait --for=condition=Ready` — The question wants the class written once the Pod is running, so wait for that first.
- `mkdir -p /tmp/cka` — Makes sure the answer folder exists. `-p` means no error if it already does.
- `status.qosClass` — Writes Kubernetes' own answer, not your guess, to the file. jsonpath prints no trailing newline, so the file holds just the word.

**Notes:** `kubectl run` names the container after the Pod, so rename it to `httpd` in the YAML. You cannot change a running Pod's resources with a normal edit. If you get them wrong, fix the file and run `kubectl replace --force -f gateway.yaml`. The class is `Burstable`: requests are set, but they differ from the limits. Equal requests and limits on every container would make it `Guaranteed`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-res
g="kubectl -n $ns get pod gateway -o jsonpath"

kubectl -n $ns get pod gateway >/dev/null 2>&1 && p "pod gateway exists" || f "pod gateway exists"
[ "$($g='{.spec.containers[0].name}/{.spec.containers[0].image}' 2>/dev/null)" = "httpd/httpd:2.4" ] && p "container httpd runs httpd:2.4" || f "container httpd runs httpd:2.4"
[ "$($g='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)" = "100m" ] && p "requests.cpu = 100m" || f "requests.cpu = 100m"
[ "$($g='{.spec.containers[0].resources.requests.memory}' 2>/dev/null)" = "64Mi" ] && p "requests.memory = 64Mi" || f "requests.memory = 64Mi"
[ "$($g='{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)" = "250m" ] && p "limits.cpu = 250m" || f "limits.cpu = 250m"
[ "$($g='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)" = "128Mi" ] && p "limits.memory = 128Mi" || f "limits.memory = 128Mi"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
qos="$($g='{.status.qosClass}' 2>/dev/null)"
[ -n "$qos" ] && [ "$(tr -d ' \n' < /tmp/cka/wl-res-qos.txt 2>/dev/null)" = "$qos" ] && p "/tmp/cka/wl-res-qos.txt holds the QoS class" || f "/tmp/cka/wl-res-qos.txt holds the QoS class"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Put defaults and a budget on a namespace

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

In namespace `wl-quota`: create a LimitRange `container-defaults` so that containers that specify nothing get a request of `100m` CPU and `128Mi` memory and a limit of `200m` CPU and `256Mi` memory, and no container may be limited above `500m` CPU or `512Mi` memory. Create a ResourceQuota `team-quota` allowing at most 4 Pods, `1` CPU and `1Gi` memory of requests, and `2` CPU and `2Gi` memory of limits. Finally create a Pod `defaulted` (image `nginx:1.27`) with no `resources` section; it must be running.

<details>
<summary>💡 Hints</summary>

- There is no `kubectl create` command for a LimitRange. Write one item of type `Container` with `default`, `defaultRequest` and `max`.
- Use `kubectl create quota --hard=pods=4,requests.cpu=1,…`. Create the LimitRange first, or the quota will reject the Pod.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: wl-quota
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: 500m
        memory: 512Mi
YAML
kubectl -n wl-quota create quota team-quota --hard=pods=4,requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi
kubectl -n wl-quota run defaulted --image=nginx:1.27
kubectl -n wl-quota wait --for=condition=Ready pod/defaulted --timeout=120s
```

**Explanation:**

- `cat <<'YAML'` — The LimitRange goes in first, so the Pod created later picks up its defaults.
- `default:` — The default limit: 200m CPU and 256Mi memory.
- `defaultRequest:` — The default request: 100m CPU and 128Mi memory.
- `max:` — No container may set a limit above 500m CPU or 512Mi memory.
- `create quota team-quota` — The namespace budget in one command. From now on every new Pod must carry CPU and memory requests and limits, which the LimitRange supplies.
- `run defaulted` — A Pod with no resources section. Admission fills in the LimitRange defaults first, so the quota accepts it.
- `wait --for=condition=Ready` — Confirms the Pod was admitted and is running.

**Notes:** Order matters only for the Pod. With the quota in place and no LimitRange, `kubectl run` fails with *must specify limits.cpu*. Check the result with `kubectl describe quota -n wl-quota`: Used shows the values the Pod was given. Then check the Pod itself with `kubectl get pod defaulted -n wl-quota -o jsonpath='{.spec.containers[0].resources}'`. Neither object changes Pods that already existed.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-quota
lr="kubectl -n $ns get limitrange container-defaults -o jsonpath"
q="kubectl -n $ns get resourcequota team-quota -o jsonpath"
g="kubectl -n $ns get pod defaulted -o jsonpath"

[ "$($lr='{.spec.limits[?(@.type=="Container")].default.cpu}/{.spec.limits[?(@.type=="Container")].default.memory}' 2>/dev/null)" = "200m/256Mi" ] && p "default limit 200m/256Mi" || f "default limit 200m/256Mi"
[ "$($lr='{.spec.limits[?(@.type=="Container")].defaultRequest.cpu}/{.spec.limits[?(@.type=="Container")].defaultRequest.memory}' 2>/dev/null)" = "100m/128Mi" ] && p "default request 100m/128Mi" || f "default request 100m/128Mi"
[ "$($lr='{.spec.limits[?(@.type=="Container")].max.cpu}/{.spec.limits[?(@.type=="Container")].max.memory}' 2>/dev/null)" = "500m/512Mi" ] && p "max 500m/512Mi" || f "max 500m/512Mi"
[ "$($q='{.spec.hard.pods}' 2>/dev/null)" = "4" ] && p "quota pods = 4" || f "quota pods = 4"
[ "$($q='{.spec.hard.requests\.cpu}/{.spec.hard.requests\.memory}' 2>/dev/null)" = "1/1Gi" ] && p "quota requests 1 CPU / 1Gi" || f "quota requests 1 CPU / 1Gi"
[ "$($q='{.spec.hard.limits\.cpu}/{.spec.hard.limits\.memory}' 2>/dev/null)" = "2/2Gi" ] && p "quota limits 2 CPU / 2Gi" || f "quota limits 2 CPU / 2Gi"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod defaulted Running" || f "pod defaulted Running"
[ "$($g='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.requests.memory}' 2>/dev/null)" = "100m/128Mi" ] && p "pod got the default requests" || f "pod got the default requests"
[ "$($g='{.spec.containers[0].resources.limits.cpu}/{.spec.containers[0].resources.limits.memory}' 2>/dev/null)" = "200m/256Mi" ] && p "pod got the default limits" || f "pod got the default limits"
used="$($q='{.status.used.pods}' 2>/dev/null)"
[ -n "$used" ] && [ "$used" -ge 1 ] && p "quota counts the pod" || f "quota counts the pod"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
