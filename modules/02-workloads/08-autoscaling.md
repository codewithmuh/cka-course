# Autoscaling with the HPA

> **Module 2** · Lesson 2.8 · 35 minutes

How the HorizontalPodAutoscaler turns CPU or memory use into a replica count, what it needs to work, how to slow it down with behavior, and where the other autoscalers fit.

## Learning Objectives

- You can create an autoscaling/v2 HPA with one command or in YAML, with min, max and a CPU or memory target.
- You can explain why an HPA shows its targets as unknown, and fix it by adding requests.
- You can control how fast an HPA scales up and down with behavior: stabilization windows and policies.
- You can say what the Vertical Pod Autoscaler and the Cluster Autoscaler change, and why neither runs on this lab.


Your Django app is quiet at night and busy at lunch. You do not want to pick its replica count by hand. A **HorizontalPodAutoscaler** (HPA) watches how much CPU or memory the Pods use, and adds or removes Pods to match. *Horizontal* means more or fewer Pods, not bigger ones.

On the exam, that means an HPA with exact numbers. Sometimes it also needs a `behavior` block, which `kubectl autoscale` cannot write. The grader reads the HPA object; it does not create load and wait for scaling. It can also check whether your Pods request the resource the HPA measures. That is the step most people miss.

## How the HPA decides

**The HPA loop**

*The HPA checks every 15 seconds. It only changes the replica count; the Deployment does the rest.*

`metrics-server` — measures each Pod's CPU and memory → `HPA` — compares the usage with your target → `Deployment` — its replica count goes up or down

1. The HPA reads each Pod's usage from metrics-server, which this lab has installed.
2. It divides the usage by the Pod's **request**. That gives a percentage, called *utilization*.
3. It averages that over all the Pods and compares it with your target.
4. It sets a new replica count, kept between `minReplicas` and `maxReplicas`.

The formula is `desired = ceil(current replicas × current value / target value)`, where `ceil` means round up. Example: 4 replicas average 90% CPU, and the target is 60%. Then `ceil(4 × 90 / 60) = 6` replicas.

- Utilization is measured against requests. So if a container has no CPU request, the HPA cannot compute anything, and it reports *missing request for cpu*.
- Once an HPA manages a Deployment, leave `spec.replicas` out of manifests you apply again. Otherwise every apply fights the autoscaler.

So before you create an HPA, check the two things it needs: working metrics, and requests on the containers.

**Check the prerequisites first**

```bash
kubectl get apiservice v1beta1.metrics.k8s.io           # Available True means metrics-server answers
kubectl -n wl-hpa top pods                                 # usage per Pod
kubectl -n wl-hpa get deploy api -o jsonpath='{.spec.template.spec.containers[*].resources}'; echo
kubectl -n wl-hpa set resources deploy/api -c nginx --requests=cpu=100m   # add the missing request (starts a rollout)
```

<details>
<summary>Line-by-line explanation</summary>

- `get apiservice v1beta1.metrics.k8s.io` — metrics-server plugs into the API server as an extra API. This shows whether that API is registered and answering; the HPA reads Pod usage through it.
- `top pods` — Live CPU and memory per Pod. If this fails, the HPA cannot get metrics either.
- `containers[*].resources}` — Prints each container's requests and limits. Without a CPU request, a CPU-utilization HPA has nothing to measure against.
- `set resources deploy/api` — Adds a 100m CPU request to container `nginx`. Utilization is measured against this number, so a 60% target means 60m per Pod on average.

</details>

## Create one

**kubectl autoscale writes an autoscaling/v2 object**

```bash
# Current kubectl (the exam's v1.37 included)
kubectl -n wl-hpa autoscale deployment api --min=2 --max=8 --cpu=60%
# Older kubectl only knows this form; newer releases still accept it with a deprecation warning
kubectl -n wl-hpa autoscale deployment api --min=2 --max=8 --cpu-percent=60

kubectl -n wl-hpa autoscale deployment api --min=2 --max=8 --cpu=60% --dry-run=client -o yaml > hpa.yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `--cpu=60%` — Creates an HPA, named after the Deployment, that keeps between 2 and 8 replicas and aims for 60% average CPU utilization.
- `--cpu-percent=60` — The same HPA with the older flag. If one form is rejected, `kubectl autoscale --help` shows the one your kubectl knows.
- `--dry-run=client -o yaml > hpa.yaml` — Writes the HPA as YAML instead: a skeleton for adding a second metric or a behavior block.

</details>

Recent kubectl uses `--cpu` and `--memory` instead of the older `--cpu-percent`. Anything beyond min, max and one CPU or memory target needs YAML. A target comes in two types, and they are easy to mix up:

| Target type | Means | Example |
| --- | --- | --- |
| `Utilization` | A percentage of the Pod's request | `averageUtilization: 75`, or `--cpu=75%` |
| `AverageValue` | An amount per Pod, whatever the request | `averageValue: 100Mi`, or `--cpu=500m` |

Here is a full HPA with two metrics and a `behavior` block:

**autoscaling/v2 with two metrics and a behavior block**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: worker
  namespace: wl-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization          # percent of the request
          averageUtilization: 75
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue         # absolute usage per Pod
          averageValue: 100Mi
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60 # act on the highest recommendation of the last 60s
      policies:
        - type: Pods
          value: 1                   # remove at most 1 Pod ...
          periodSeconds: 30          # ... per 30 seconds
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: autoscaling/v2` — Use `autoscaling/v2`: it supports several metrics and `behavior`. The older `autoscaling/v1` knows only a single CPU percentage.
- `scaleTargetRef:` — Which object to scale, by apiVersion, kind and name. The HPA changes that object's replica count.
- `minReplicas: 1` — The HPA never goes below 1 or above 5 replicas, whatever the metrics say.
- `metrics:` — A list. The HPA works out a replica count for each metric and uses the highest.
- `- type: Resource` — Resource metrics are CPU and memory from metrics-server, averaged across the target's Pods.
- `averageUtilization: 75` — 75% of the Pods' CPU request, on average.
- `averageValue: 100Mi` — An absolute amount: 100Mi of memory per Pod on average, whatever the requests are.
- `behavior:` — Shapes how fast the count may change, separately for `scaleDown` and `scaleUp`. It sits under `spec`, beside `metrics`.
- `- type: Pods` — A policy of type Pods limits the change by a number of Pods. A policy of type Percent would limit it by a share of the current count.

</details>

With several metrics, the HPA works out a replica count for each one and uses the largest. Other metric types exist for custom metrics, but they need an extra metrics adapter.

When one direction has several policies, `selectPolicy` decides which one wins:

- `Max` (the default): the policy that allows the biggest change.
- `Min`: the policy that allows the smallest change.
- `Disabled`: no scaling in that direction at all.

If you leave `behavior` out, these defaults apply. Note the 300-second window on scale-down: an HPA waits 5 minutes before it removes Pods.

| behavior default | scaleUp | scaleDown |
| --- | --- | --- |
| `stabilizationWindowSeconds` | 0 | 300 |
| `policies` | 4 Pods or 100% per 15s, whichever is more | 100% per 15s |
| `selectPolicy` | Max | Max |

## Reading an HPA

**Targets, conditions and events**

```bash
kubectl -n wl-hpa get hpa
# NAME   REFERENCE        TARGETS              MINPODS   MAXPODS   REPLICAS
# api    Deployment/api   cpu: <unknown>/60%   2         8         2        <- no metrics or no requests
kubectl -n wl-hpa describe hpa api | sed -n '/Conditions/,$p'
#   ScalingActive  False  FailedGetResourceMetric  ... missing request for cpu in container nginx ...
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl -n wl-hpa get hpa` — TARGETS shows the current value against the target. The comment lines below are sample output.
- `cpu: <unknown>/60%` — `` means no value could be computed yet: metrics-server is not ready, the Pods are too new to have metrics, or containers have no CPU request.
- `describe hpa api` — `$` in sed means the last line, so this prints from Conditions to the end: the three conditions, then the events.
- `FailedGetResourceMetric` — Sample condition: the message names the exact container that is missing a request.

</details>

| Condition | What it tells you |
| --- | --- |
| `AbleToScale` | Whether the HPA can change the target's replica count |
| `ScalingActive` | Whether a metric could be computed. False means no metrics, Pods too new, or missing requests |
| `ScalingLimited` | True when min, max or a policy held the count back |

A new HPA shows `` for up to a minute, while metrics-server collects its first numbers. If it stays that way, read the condition message.

## Other autoscalers

Two other autoscalers change different things. Keep the three apart:

| Autoscaler | It changes | Example |
| --- | --- | --- |
| HorizontalPodAutoscaler | The number of Pods | 2 to 6 nginx Pods at lunchtime |
| Vertical Pod Autoscaler | Each Pod's *requests* | 100m to 300m CPU per Pod |
| Cluster Autoscaler | The number of *nodes* | Adds a node when Pods are Pending for lack of room |

Neither of the last two runs on kind, and the exam treats both as concepts.

> [!IMPORTANT] **What the grader reads**
> The grader reads the HPA's `scaleTargetRef`, `minReplicas`, `maxReplicas`, and each metric's `target.type` with its value. It also reads the `behavior` fields when the task names them. Utilization and AverageValue are different target types, so *70% CPU* and *700m CPU* are not the same answer. If the task mentions requests, the grader also reads the Deployment's containers. Do not wait to watch scaling happen: check `kubectl get hpa` and move on.

## 📝 Key Takeaways

- An HPA changes the replica count to keep the average CPU or memory near a target, between `minReplicas` and `maxReplicas`.
- It needs metrics-server and, for a percentage target, a request on every container.
- `` in TARGETS usually means missing requests. `kubectl describe hpa` names the container.
- Utilization is a percentage of the request. AverageValue is an amount per Pod.
- `kubectl autoscale` writes min, max and one target. A second metric or a `behavior` block needs YAML.

**📖 Official documentation:**

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/) *(search: "horizontal pod autoscaling")*
- [HorizontalPodAutoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) *(search: "hpa walkthrough")*
- [Autoscaling Workloads](https://kubernetes.io/docs/concepts/workloads/autoscaling/) *(search: "autoscaling workloads")*

---

### 🎯 Task: Autoscale a Deployment on CPU

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

The Deployment `api` in namespace `wl-hpa` must scale automatically between 2 and 8 replicas, keeping the average CPU utilization of its Pods at 60%. Create a HorizontalPodAutoscaler named `api` for it. The autoscaler can only compute utilization if the Pods request CPU, so also give the Deployment's `nginx` container a CPU request of `100m`.

<details>
<summary>💡 Hints</summary>

- `kubectl set resources deploy/api -c nginx --requests=cpu=100m`
- `kubectl autoscale deployment api --min=2 --max=8 --cpu=60%`. Older kubectl uses `--cpu-percent=60` instead.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-hpa set resources deploy/api -c nginx --requests=cpu=100m
kubectl -n wl-hpa rollout status deploy/api --timeout=120s
cat <<'YAML' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api
  namespace: wl-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
YAML
```

**Explanation:**

- `set resources deploy/api` — Gives the nginx container the 100m CPU request the HPA needs to compute utilization.
- `rollout status` — The request changes the Pod template, so wait for the new Pods.
- `cat <<'YAML'` — The HPA as YAML, so it works on any kubectl version. On the exam, `kubectl autoscale deployment api --min=2 --max=8 --cpu=60%` does the same in one line.
- `scaleTargetRef:` — Points at Deployment `api` in the HPA's own namespace.
- `averageUtilization: 60` — 60% of the CPU request on average: 60m per Pod with a 100m request.

**Notes:** On the exam, this is two commands: `kubectl set resources`, then `kubectl autoscale`. The solution writes YAML only so that it runs on any kubectl version. Within a minute, `kubectl get hpa api -n wl-hpa` should show a real percentage instead of ``. If it stays unknown, `kubectl describe hpa` names the container that is missing a request.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-hpa
h="kubectl -n $ns get hpa api -o jsonpath"

kubectl -n $ns get hpa api >/dev/null 2>&1 && p "hpa api exists" || f "hpa api exists"
[ "$($h='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}' 2>/dev/null)" = "Deployment/api" ] && p "targets Deployment api" || f "targets Deployment api"
[ "$($h='{.spec.minReplicas}/{.spec.maxReplicas}' 2>/dev/null)" = "2/8" ] && p "min 2, max 8" || f "min 2, max 8"
[ "$($h='{.spec.metrics[?(@.resource.name=="cpu")].resource.target.type}/{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}' 2>/dev/null)" = "Utilization/60" ] && p "cpu utilization target 60%" || f "cpu utilization target 60%"
[ "$(kubectl -n $ns get deploy api -o jsonpath='{.spec.template.spec.containers[?(@.name=="nginx")].resources.requests.cpu}' 2>/dev/null)" = "100m" ] && p "nginx requests 100m cpu" || f "nginx requests 100m cpu"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: An HPA with two metrics and a slow scale-down

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `wl-hpa`, create an `autoscaling/v2` HorizontalPodAutoscaler `worker` for the Deployment `worker`. It keeps between 1 and 5 replicas and scales on two metrics: an average CPU utilization of 75%, and an average memory usage of `100Mi` per Pod. Scale-downs must use a 60-second stabilization window and remove at most 1 Pod every 30 seconds.

<details>
<summary>💡 Hints</summary>

- `kubectl autoscale` cannot write the second metric or the behavior block. Generate a skeleton with `--dry-run=client -o yaml`, then extend it.
- Memory per Pod is `target.type: AverageValue` with `averageValue: 100Mi`. The scale-down rule is one policy of type `Pods`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: worker
  namespace: wl-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 75
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue
          averageValue: 100Mi
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 1
          periodSeconds: 30
YAML
```

**Explanation:**

- `minReplicas: 1` — Between 1 and 5 replicas, as the question says.
- `averageUtilization: 75` — First metric: CPU at 75% of the request.
- `averageValue: 100Mi` — Second metric: 100Mi of memory per Pod. An absolute amount, so the target type is AverageValue.
- `behavior:` — Only `scaleDown` is set; `scaleUp` keeps its defaults.
- `stabilizationWindowSeconds: 60` — Before scaling down, the HPA looks back 60 seconds and uses the highest recommendation, so a short dip does not remove Pods.
- `- type: Pods` — Exactly one policy: at most 1 Pod removed per 30-second period.

**Notes:** `behavior` sits under `spec`, beside `metrics`. Leaving `scaleUp` out keeps its defaults. A `Percent` policy would not match *at most 1 Pod*. A second scale-down policy would let the default `selectPolicy: Max` pick the faster one, so keep exactly one. The Kubernetes docs page *Horizontal Pod Autoscaling* has a behavior example you can copy during the exam.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-hpa
h="kubectl -n $ns get hpa worker -o jsonpath"

kubectl -n $ns get hpa worker >/dev/null 2>&1 && p "hpa worker exists" || f "hpa worker exists"
[ "$($h='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}' 2>/dev/null)" = "Deployment/worker" ] && p "targets Deployment worker" || f "targets Deployment worker"
[ "$($h='{.spec.minReplicas}/{.spec.maxReplicas}' 2>/dev/null)" = "1/5" ] && p "min 1, max 5" || f "min 1, max 5"
[ "$($h='{.spec.metrics[?(@.resource.name=="cpu")].resource.target.type}/{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}' 2>/dev/null)" = "Utilization/75" ] && p "cpu utilization target 75%" || f "cpu utilization target 75%"
[ "$($h='{.spec.metrics[?(@.resource.name=="memory")].resource.target.type}/{.spec.metrics[?(@.resource.name=="memory")].resource.target.averageValue}' 2>/dev/null)" = "AverageValue/100Mi" ] && p "memory average value 100Mi" || f "memory average value 100Mi"
[ "$($h='{.spec.behavior.scaleDown.stabilizationWindowSeconds}' 2>/dev/null)" = "60" ] && p "scale-down stabilization 60s" || f "scale-down stabilization 60s"
[ "$($h='{.spec.behavior.scaleDown.policies[*].type}' 2>/dev/null)" = "Pods" ] && p "one scale-down policy, of type Pods" || f "one scale-down policy, of type Pods"
[ "$($h='{.spec.behavior.scaleDown.policies[0].value}/{.spec.behavior.scaleDown.policies[0].periodSeconds}' 2>/dev/null)" = "1/30" ] && p "at most 1 pod per 30s" || f "at most 1 pod per 30s"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
