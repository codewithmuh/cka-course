# Scheduling: selectors, affinity, taints and spread

> **Module 2** · Lesson 2.5 · 45 minutes

How the scheduler picks a node, and the ways you can steer a Pod: nodeSelector, node affinity, pod anti-affinity, topology spread, taints and tolerations, and nodeName.

## Learning Objectives

- You can read a FailedScheduling event and name the rule that rejected each node.
- You can pin Pods to labeled nodes with nodeSelector or node affinity, and keep replicas apart with pod anti-affinity or topology spread.
- You can taint a node, write the matching toleration, and explain why a toleration alone never pulls a Pod to a node.
- You can place a Pod by hand with nodeName when the scheduler is not running.


When you create a Pod, the **scheduler** picks the node it runs on. Most of the time you let it choose. Sometimes you need a say. Your Django app's Pods should run only on nodes with an SSD, or two copies of a database should never share one node.

On the exam, the grader can see exactly where your Pods landed. That cuts both ways: a Deployment running on the wrong node scores the same as one stuck in Pending. So always finish with `kubectl get pods -o wide`, which shows each Pod's node.

## How the scheduler chooses a node

The scheduler watches for new Pods that have no node yet: their `spec.nodeName` is empty. For each one, it works in three steps:

**Filter, score, bind**

`New Pod` — no node yet → `1. Filter` — drop nodes that cannot run it → `2. Score` — rank the nodes that are left → `3. Bind` — write the best node into nodeName

1. **Filter:** remove every node that cannot run the Pod. Examples are a node without enough CPU left to reserve, or a node with a taint the Pod does not tolerate.
2. **Score:** rank the nodes that are left. Preferred rules, spreading, and images already on the node all add points.
3. **Bind:** give the Pod to the best node by writing its name into `spec.nodeName`. The kubelet on that node then starts the Pod.

If no node passes the filter, the Pod stays `Pending` with a `FailedScheduling` event. The event names one reason per rejected node, for example: *0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod anti-affinity rules*.

Read it with `kubectl describe pod`. To see these events for every Pod, run `kubectl get events --field-selector reason=FailedScheduling`.

Here are the ways to steer a Pod. The names look alike, so keep them apart by what each one looks at:

| Rule | It looks at | Example |
| --- | --- | --- |
| `nodeSelector`, node affinity | Labels on the node | "Only on nodes labeled `disktype=ssd`" |
| Pod anti-affinity | Labels of Pods already on the node | "Never two api Pods on one node" |
| Topology spread | How many matching Pods each node has | "Keep api Pods even across nodes" |
| Taints and tolerations | A mark on the node that keeps Pods off | "Only batch Pods may use this node" |
| `nodeName` | Nothing: it skips the scheduler | "Run on cka-worker, the scheduler is down" |

## nodeSelector, node affinity and nodeName

Nodes carry labels, just like Pods. For example, you might label one node `disktype=ssd`. There are two ways to send a Pod only to nodes with a given label:

- `nodeSelector`: simple. Every label you list must match exactly.
- `nodeAffinity`: more flexible. It has operators such as `In` and `NotIn`, and both hard rules (*required*) and soft ones (*preferred*).

**Pod spec fragments: the simple and the expressive way to pick nodes**

```yaml
    spec:
      nodeSelector:                 # every label must match (AND)
        pool: frontend
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:      # terms are ORed ...
              - matchExpressions:   # ... expressions inside one term are ANDed
                  - key: kubernetes.io/arch
                    operator: In    # In, NotIn, Exists, DoesNotExist, Gt, Lt
                    values: ["amd64", "arm64"]
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 80            # 1-100, added to the node's score
              preference:
                matchExpressions:
                  - key: disktype
                    operator: In
                    values: ["ssd"]
```

<details>
<summary>Line-by-line explanation</summary>

- `nodeSelector:` — The simple way: the Pod may only go to nodes that carry the label `pool=frontend`. Exact matches only, no operators.
- `nodeAffinity:` — Affinity lives under `spec.affinity`, beside `nodeSelector`. `nodeAffinity` matches node labels; pod anti-affinity, later in this lesson, matches other Pods.
- `requiredDuringSchedulingIgnoredDuringExecution:` — A hard rule: nodes that fail it are filtered out. The name says it is checked only when scheduling. A running Pod is not moved if node labels change later.
- `- key: kubernetes.io/arch` — The kubelet sets this label on every node by itself, so this rule keeps the Pod on amd64 or arm64 machines.
- `values: ["amd64", "arm64"]` — `In` matches when the node's label equals any value in the list.
- `preferredDuringSchedulingIgnoredDuringExecution:` — A soft rule: matching nodes get extra score, but the Pod still goes elsewhere if none match.
- `preference:` — Note the different shape: each item is a `weight` plus one `preference`, with no `nodeSelectorTerms` wrapper.

</details>

- If a Pod has both `nodeSelector` and `nodeAffinity`, a node must pass both.
- *IgnoredDuringExecution* in the long field names means: if a node's labels change later, Pods already running there stay.
- `NotIn` and `DoesNotExist` keep a Pod *away* from nodes with a label. That is often simpler than tainting them.

`spec.nodeName` skips the scheduler completely. The kubelet on that node just starts the Pod. The scheduler's checks never run, so NoSchedule taints are ignored: the kubelet only enforces NoExecute taints.

That makes `nodeName` the tool for **manual scheduling**, when the scheduler is down and Pods sit in Pending. You cannot add `nodeName` to an existing Pod; the API refuses the change. Delete the Pod, then create it again with `nodeName` set.

## Pod anti-affinity and topology spread

Node rules look at node labels. Pod rules look at *other Pods*. Their most common use is to keep copies of one app apart, so that one broken node cannot take them all down.

**Pod anti-affinity** keeps a Pod off nodes that already run Pods with a given label. Here, each `app=api` Pod avoids nodes that already run one:

**Keep replicas on different nodes with anti-affinity**

```yaml
  template:
    metadata:
      labels:
        app: api
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: api
              topologyKey: kubernetes.io/hostname    # "same place" means same node
      containers:
        - name: api
          image: nginx:1.27
```

<details>
<summary>Line-by-line explanation</summary>

- `template:` — Only the Pod template of a Deployment is shown, so the lines start indented.
- `app: api` — The label every replica carries. The rule below selects Pods by label, these Pods' own included.
- `podAntiAffinity:` — Keeps this Pod away from other Pods that match the selector.
- `requiredDuringSchedulingIgnoredDuringExecution:` — Required: a node already running a matching Pod is filtered out.
- `- labelSelector:` — Which Pods to stay away from: those labeled `app=api`, so the replicas avoid each other.
- `topologyKey: kubernetes.io/hostname` — Every node has its own unique hostname label, so each node is one place: at most one api Pod per node.

</details>

The `topologyKey` is a node label that says what "the same place" means. With `kubernetes.io/hostname`, each node is its own place. With `topology.kubernetes.io/zone`, each zone is one place. The rule matches Pods in the Pod's own namespace.

**Topology spread** is the gentler tool. Instead of "never together", it says "keep the numbers even". It sits in the same Pod spec, beside `affinity`:

**Or spread them evenly with topology spread**

```yaml
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule      # or ScheduleAnyway (a preference)
          labelSelector:
            matchLabels:
              app: api
```

<details>
<summary>Line-by-line explanation</summary>

- `topologySpreadConstraints:` — Spread rules sit beside `affinity` in the Pod spec. Each entry spreads the Pods its `labelSelector` matches across the places named by its `topologyKey`.
- `maxSkew: 1` — The busiest and the emptiest node may differ by at most one matching Pod.
- `whenUnsatisfiable: DoNotSchedule` — DoNotSchedule makes it a hard rule: a Pod that would break the skew stays Pending.

</details>

With `maxSkew: 1`, 5 replicas on 2 nodes still all run, as 3 and 2. A required anti-affinity rule would leave 3 of them Pending.

There is also `podAffinity`, the opposite pull: run *near* Pods with a given label, for example in the same zone as a cache. It is written the same way, under `affinity.podAffinity`.

> [!WARNING] **Required anti-affinity can freeze a rollout**
> Say you have 2 replicas, 2 usable nodes, and required anti-affinity per node. A default rolling update first adds one extra Pod: 25% surge rounds up to 1, and 25% unavailable rounds down to 0. That new Pod has nowhere to go: both nodes already run a Pod with the same label. The rollout waits forever. When replicas equal nodes, use `maxUnavailable: 1` with `maxSurge: 0`, a preferred rule, or topology spread.

## Taints and tolerations

A **taint** is a mark on a node that keeps Pods away. A **toleration** on a Pod says "I accept that mark". Example: you taint a node that has a GPU, so that only machine-learning Pods, which tolerate the taint, can use it.

Every taint has an **effect**, which says how strongly it keeps Pods away:

| Effect | New Pods without a toleration | Pods already running |
| --- | --- | --- |
| `NoSchedule` | Not scheduled there | Stay |
| `PreferNoSchedule` | Avoided, unless nothing else fits | Stay |
| `NoExecute` | Not scheduled there | Evicted, at once or after the toleration's `tolerationSeconds` |

**Labels and taints on nodes**

```bash
kubectl label node cka-worker pool=frontend
kubectl get nodes -L pool                        # show one label as a column
kubectl label node cka-worker pool-              # remove it

kubectl taint node cka-worker2 dedicated=batch:NoSchedule
kubectl get node cka-worker2 -o jsonpath='{.spec.taints}'; echo
kubectl taint node cka-worker2 dedicated=batch:NoSchedule-   # remove it (trailing minus)
kubectl describe node cka-control-plane | grep Taints        # node-role.kubernetes.io/control-plane:NoSchedule
```

<details>
<summary>Line-by-line explanation</summary>

- `label node cka-worker pool=frontend` — Adds the label `pool=frontend` to the node. If the key already has another value, add `--overwrite`.
- `get nodes -L pool` — `-L`, capital L, adds a column with that label's value for each node. It is blank where the node lacks the label.
- `taint node cka-worker2 dedicated=batch:NoSchedule` — A taint is written `key=value:effect`. New Pods without a matching toleration are no longer scheduled on cka-worker2; Pods already there stay.
- `{.spec.taints}` — Prints the node's taints as JSON, so you can check the key, value and effect.
- `NoSchedule-` — To remove every taint with that key, whatever its effect, `kubectl taint node cka-worker2 dedicated-` works too.
- `grep Taints` — The control plane carries this taint, which is why ordinary Pods never land on it. `grep` shows only the first taint; a node with several lists the rest on the lines below.

</details>

**Tolerations**

```yaml
      tolerations:
        - key: dedicated              # matches dedicated=batch:NoSchedule exactly
          operator: Equal
          value: batch
          effect: NoSchedule
        - key: node-role.kubernetes.io/control-plane
          operator: Exists            # any value; no value field allowed
          effect: NoSchedule
```

<details>
<summary>Line-by-line explanation</summary>

- `tolerations:` — Tolerations sit in the Pod spec, at the same level as `containers`. Each entry allows one kind of taint. It never pulls the Pod toward that node.
- `operator: Equal` — Equal, the default, needs the key, value and effect to match the taint exactly.
- `- key: node-role.kubernetes.io/control-plane` — Tolerates the control-plane taint, so the Pod may also run there. DaemonSets that must cover every node use exactly this.

</details>

Kubernetes also taints nodes by itself, for example with `node.kubernetes.io/unreachable` when a node stops reporting. Those taints are covered in [Worker node failures](/cka/troubleshooting/worker-node-failures).

A taint keeps Pods away, but a toleration only *allows* a Pod in. It never sends the Pod there. A Pod that tolerates `dedicated=batch` can still land on any node without a taint. So to keep a node for some Pods only, you need both halves:

**Keeping a node for batch Pods**

*The taint and the toleration decide who may enter. The label and the nodeSelector decide where the Pod goes.*

`Taint` — on the node: keeps other Pods off   `Toleration` — on the Pod: allows it in   `Label + nodeSelector` — on node and Pod: sends it there

**On this shared lab, never use `NoExecute`.** It evicts every Pod on the node that does not tolerate it, including other lessons' Pods.

> [!IMPORTANT] **What the grader reads**
> The grader reads each Pod's `spec.nodeName`, the node's `metadata.labels` and `spec.taints`, and the scheduling fields in the Pod template. A taint with the wrong effect, or a label with a typo, fails the whole task. So print them back: `kubectl get nodes -L pool` and `kubectl describe node X | grep Taints`. Remove taints when a task says the node should be usable again. Leftover taints quietly break later tasks.

## 📝 Key Takeaways

- The scheduler filters out nodes that cannot run the Pod, scores the rest, and binds the Pod to the best one.
- `nodeSelector` and node affinity pick nodes by their labels. Pod anti-affinity and topology spread keep copies of an app apart.
- A taint keeps Pods off a node. A toleration only allows a Pod in; a nodeSelector is what sends it there.
- `nodeName` skips the scheduler. Use it to place a Pod by hand when the scheduler is down.
- Finish every scheduling task with `kubectl get pods -o wide`, and remove labels and taints you no longer need.

**📖 Official documentation:**

- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) *(search: "assign pods to nodes")*
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) *(search: "taints tolerations")*
- [Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) *(search: "topology spread constraints")*
- [Assign Pods to Nodes using Node Affinity](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/) *(search: "node affinity")*

---

### 🎯 Task: Pin a Deployment to a labeled node

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Add the label `pool=frontend` to node `cka-worker`. Then in namespace `wl-sched` create a Deployment `frontend` with 3 replicas of `nginx:1.27` whose Pods may only be scheduled onto nodes carrying that label. All 3 Pods must be running.

<details>
<summary>💡 Hints</summary>

- `kubectl label node cka-worker pool=frontend`
- Generate the Deployment with `--dry-run=client -o yaml`. Then add `nodeSelector` under `spec.template.spec`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl label node cka-worker pool=frontend --overwrite
cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: wl-sched
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      nodeSelector:
        pool: frontend
      containers:
        - name: nginx
          image: nginx:1.27
YAML
kubectl -n wl-sched rollout status deploy/frontend --timeout=120s
```

**Explanation:**

- `label node cka-worker pool=frontend --overwrite` — Labels the node. `--overwrite` lets the command succeed even if `pool` already has another value, so it is safe to rerun.
- `nodeSelector:` — Placed in the Pod template's spec, beside `containers`. Every replica may only go to nodes labeled `pool=frontend`, which here is cka-worker alone.
- `rollout status` — Waits for all 3 replicas. If the node label were missing, they would stay Pending and this would time out.

**Notes:** `nodeSelector` is the shortest correct answer. Required node affinity with `operator: In` works just as well. Without the label on the node, the Pods stay Pending with *didn't match Pod's node affinity/selector*. You can also add the field to an existing Deployment with `kubectl patch deploy frontend -n wl-sched -p '{"spec":{"template":{"spec":{"nodeSelector":{"pool":"frontend"}}}}}'`. When you are done practicing, remove the label with `kubectl label node cka-worker pool-`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-sched
d="kubectl -n $ns get deploy frontend -o jsonpath"

[ "$(kubectl get node cka-worker -o jsonpath='{.metadata.labels.pool}' 2>/dev/null)" = "frontend" ] && p "cka-worker labeled pool=frontend" || f "cka-worker labeled pool=frontend"
kubectl -n $ns get deploy frontend >/dev/null 2>&1 && p "deployment frontend exists" || f "deployment frontend exists"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "replicas = 3" || f "replicas = 3"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
{ [ "$($d='{.spec.template.spec.nodeSelector.pool}' 2>/dev/null)" = "frontend" ] || $d='{.spec.template.spec.affinity.nodeAffinity}' 2>/dev/null | grep -q '"pool"'; } && p "pod template selects pool=frontend" || f "pod template selects pool=frontend"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
sel="$($d='{.spec.selector.matchLabels}' 2>/dev/null | tr -d '{}"' | tr ':' '=')"
nodes="$([ -n "$sel" ] && kubectl -n $ns get pods -l "$sel" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}' 2>/dev/null)"
[ -n "$nodes" ] && [ -z "$(echo $nodes | xargs -n1 | grep -vx cka-worker)" ] && p "every pod runs on cka-worker" || f "every pod runs on cka-worker"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Taint a node and run a Pod that tolerates it

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Taint node `cka-worker2` with key `dedicated`, value `batch` and effect `NoSchedule`. Then in namespace `wl-sched` create a Pod `batch-runner` (image `busybox:1.36`, command `sleep 3600`) that tolerates this taint and runs on `cka-worker2`.

<details>
<summary>💡 Hints</summary>

- `kubectl taint node cka-worker2 dedicated=batch:NoSchedule`
- A toleration lets the Pod onto the node, but does not send it there. Add a `nodeSelector` with `kubernetes.io/hostname: cka-worker2` as well.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl taint node cka-worker2 dedicated=batch:NoSchedule --overwrite
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: batch-runner
  namespace: wl-sched
spec:
  nodeSelector:
    kubernetes.io/hostname: cka-worker2
  tolerations:
    - key: dedicated
      operator: Equal
      value: batch
      effect: NoSchedule
  containers:
    - name: batch-runner
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
kubectl -n wl-sched wait --for=condition=Ready pod/batch-runner --timeout=120s
```

**Explanation:**

- `taint node cka-worker2` — Taints cka-worker2. `--overwrite` replaces an existing taint with the same key and effect instead of failing.
- `nodeSelector:` — Sends the Pod to cka-worker2 through its built-in hostname label. The toleration alone would only allow it there, not send it there.
- `tolerations:` — Matches the taint exactly: key `dedicated`, value `batch`, effect NoSchedule.
- `command:` — Keeps the busybox container running so the Pod stays Running.
- `wait --for=condition=Ready` — Ready means the Pod was scheduled and started. `kubectl get pod -o wide` then shows which node it is on.

**Notes:** Start from `kubectl run batch-runner -n wl-sched --image=busybox:1.36 --dry-run=client -o yaml --command -- sleep 3600`, then add `tolerations` and `nodeSelector`. Without the selector, the Pod may land on `cka-worker`: the toleration alone is not enough. `nodeName: cka-worker2` would also place it, but it skips the scheduler. The Pod would then run even without a toleration, so it proves nothing about the taint. Remove the taint afterwards with `kubectl taint node cka-worker2 dedicated-`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-sched
g="kubectl -n $ns get pod batch-runner -o jsonpath"

[ "$(kubectl get node cka-worker2 -o jsonpath='{.spec.taints[?(@.key=="dedicated")].value}/{.spec.taints[?(@.key=="dedicated")].effect}' 2>/dev/null)" = "batch/NoSchedule" ] && p "cka-worker2 tainted dedicated=batch:NoSchedule" || f "cka-worker2 tainted dedicated=batch:NoSchedule"
kubectl -n $ns get pod batch-runner >/dev/null 2>&1 && p "pod batch-runner exists" || f "pod batch-runner exists"
[ "$($g='{.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image busybox:1.36" || f "image busybox:1.36"
[ "$($g='{.spec.tolerations[?(@.key=="dedicated")].key}' 2>/dev/null)" = "dedicated" ] && p "pod tolerates the dedicated taint" || f "pod tolerates the dedicated taint"
[ "$($g='{.spec.nodeName}' 2>/dev/null)" = "cka-worker2" ] && p "pod scheduled on cka-worker2" || f "pod scheduled on cka-worker2"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Spread replicas across nodes with anti-affinity

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

In namespace `wl-sched` create a Deployment `spread` with 2 replicas of `nginx:1.27`, Pod label `app=spread`. Add a *required* pod anti-affinity rule so that two Pods of this Deployment can never run on the same node. Both Pods must be running.

<details>
<summary>💡 Hints</summary>

- Use `podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution` with a `labelSelector` for `app=spread`.
- "Same node" is `topologyKey: kubernetes.io/hostname`.
- Both workers must accept the Pods. If one Pod stays Pending, look for a leftover taint with `kubectl describe nodes | grep Taints`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread
  namespace: wl-sched
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spread
  template:
    metadata:
      labels:
        app: spread
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: spread
              topologyKey: kubernetes.io/hostname
      containers:
        - name: nginx
          image: nginx:1.27
YAML
kubectl -n wl-sched rollout status deploy/spread --timeout=120s
```

**Explanation:**

- `replicas: 2` — Two replicas for the two workers that accept Pods; the control plane is tainted.
- `podAntiAffinity:` — Required anti-affinity against Pods with the same label, `app=spread`: each replica rejects any node that already runs one.
- `topologyKey: kubernetes.io/hostname` — Per node, because every node's hostname label is unique.
- `rollout status` — Waits for both Pods. `kubectl get pods -o wide` should then show two different nodes.

**Notes:** The control plane's NoSchedule taint leaves two usable nodes, so exactly two replicas fit. Scale to 3 and the third Pod stays Pending with *didn't match pod anti-affinity rules*. That is the rule working. As the warning above explains, a default rolling update of this Deployment would also get stuck. A real version would set `maxSurge: 0` and `maxUnavailable: 1`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-sched
d="kubectl -n $ns get deploy spread -o jsonpath"
aa="{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0]"

kubectl -n $ns get deploy spread >/dev/null 2>&1 && p "deployment spread exists" || f "deployment spread exists"
[ "$($d="$aa.topologyKey}" 2>/dev/null)" = "kubernetes.io/hostname" ] && p "required anti-affinity per hostname" || f "required anti-affinity per hostname"
$d="$aa.labelSelector}" 2>/dev/null | grep -q spread && p "anti-affinity selects app=spread" || f "anti-affinity selects app=spread"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
nodes="$(kubectl -n $ns get pods -l app=spread --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}' 2>/dev/null)"
[ "$(echo $nodes | xargs -n1 | sort -u | wc -l | tr -d ' ')" = "2" ] && p "pods run on two different nodes" || f "pods run on two different nodes"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
