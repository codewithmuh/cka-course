# Monitoring resource usage

> **Module 5** · Lesson 5.7 · 35 minutes

Where kubectl top gets its numbers, and how to tell usage apart from requests, limits and a node's allocatable size.

## Learning Objectives

- You can find the Pod, container or node using the most CPU or memory, and write the answer as the grader expects.
- You can tell usage, requests, limits and allocatable apart, and you know which command shows each one.
- You can check that metrics-server, the source of kubectl top, is working.


This exam skill is called **Monitor cluster and application resource usage**. The tasks are short: which Pod uses the most CPU, which node has the most memory. The commands take seconds. You lose points by reading the wrong number, or by writing `pod/name` when the grader wants just `name`.

## Where the numbers come from

`kubectl top` gets its numbers from **metrics-server**, which asks every kubelet for CPU and memory use, every 15 seconds on this lab. It keeps only the latest numbers, so there is no history, and a new Pod appears only after a scrape or two.

**Where kubectl top gets its numbers**

*The HorizontalPodAutoscaler reads the same numbers. If metrics-server is down, kubectl top answers Metrics API not available.*

`kubelet` — measures each container on its node → `metrics-server` — keeps only the latest numbers → `kubectl top and the HPA` — read them through the API server

## kubectl top

**kubectl top, and checking metrics-server behind it**

```bash
kubectl top nodes                                   # usage per node; % is of allocatable
kubectl top nodes --sort-by=memory                  # or --sort-by=cpu; highest first
kubectl top pods -n shop                            # one namespace
kubectl top pods -A --sort-by=cpu                   # every namespace, heaviest first
kubectl top pods -n shop --containers               # one line per container
kubectl top pods -n shop -l app=web --sort-by=memory
kubectl top pod web-7d9c -n shop --containers       # a single Pod (one name only)

# The answer as a bare name, without a header
kubectl top pods -n shop --sort-by=cpu --no-headers | awk 'NR==1 {print $1}' > /tmp/cka/busiest.txt

# Is metrics-server healthy?
kubectl get apiservice v1beta1.metrics.k8s.io       # AVAILABLE must be True
kubectl -n kube-system get deploy metrics-server
kubectl -n kube-system logs deploy/metrics-server --tail=20
```

<details>
<summary>Line-by-line explanation</summary>

- `# usage per node` — CPU and memory in use on each node, from metrics-server's latest sample. CPU is in millicores (`1000m` is one core), memory in Mi, and the percentages are of the node's allocatable.
- `top nodes --sort-by=memory` — Highest memory user first. `--sort-by` accepts only `cpu` or `memory`.
- `# one namespace` — Usage per Pod in one namespace, each the sum of its containers. A Pod started in the last minute may be missing until metrics-server has sampled it.
- `top pods -A --sort-by=cpu` — Every namespace (`-A`), heaviest CPU user first, with a NAMESPACE column so you know where the top Pod lives.
- `top pods -n shop --containers` — One line per container instead of per Pod, so you can tell whether the app or a sidecar is the heavy one.
- `-l app=web --sort-by=memory` — Only the Pods labeled `app=web`, biggest memory user first. Scope like this whenever the question names a label.
- `top pod web-7d9c` — One Pod by name, here split into its containers. `top pod` takes a single name, not a list.
- `awk 'NR==1 {print $1}'` — `--no-headers` drops the title row, and awk prints the first column of the first line: the busiest Pod's name. `>` saves exactly that bare name, the format graders expect.
- `get apiservice v1beta1.metrics.k8s.io` — This APIService tells the API server to pass `metrics.k8s.io` requests to metrics-server. AVAILABLE must be `True`. `False` with a reason such as `MissingEndpoints` means metrics-server cannot be reached.
- `get deploy metrics-server` — metrics-server is an ordinary Deployment in kube-system. READY `1/1` means its Pod is up.
- `logs deploy/metrics-server` — Its recent log. Scrape errors name the node that failed. Certificate errors are why the lab runs it with `--kubelet-insecure-tls`.

</details>

A Pod that just started has no numbers for up to a minute: `kubectl top` says *metrics not available yet*. Wait and try again.

| Column | What it is | Compare it with |
| --- | --- | --- |
| CPU(cores) | CPU in use, in millicores: `250m` is a quarter of one CPU core | The CPU request and limit. Above its limit, the container is slowed down. |
| MEMORY(bytes) | Memory in use (the *working set*). Files in a memory-backed volume count too. | The memory limit. Above it, the container is killed (OOMKilled). |
| CPU% / MEMORY% (nodes only) | Node usage as a share of the node's **allocatable** size | Not the Allocated resources in `kubectl describe node`: those are requests, not usage |

## Usage, requests, limits and allocatable

These four numbers sound alike and are easy to mix up under pressure. They mean different things:

- **Usage:** what a container uses right now. `kubectl top` shows it.
- **Request:** what the scheduler sets aside for the container. A node is full when its Pods' requests add up to its allocatable, even if `kubectl top` says it is idle.
- **Limit:** the most a container may use. Above its CPU limit it is slowed down. Above its memory limit it is killed (OOMKilled).
- **Allocatable:** the node's size, minus what is kept back for the system. It is a field on the Node: `status.allocatable`.

Example: a container requests `100Mi`, has a `200Mi` limit and uses `150Mi`. It is above its request, which is allowed. If it tries to go past `200Mi`, it is OOMKilled. [Requests, limits, LimitRange and ResourceQuota](/cka/workloads/resources-limits-quotas) teaches how to set these values.

**Requests and capacity next to usage**

```bash
# Requests and limits of every Pod in a namespace
kubectl -n shop get pods -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIM:.spec.containers[*].resources.limits.memory'

# What the scheduler has handed out on a node (requests and limits, as % of allocatable)
kubectl describe node cka-worker | sed -n '/Allocated resources/,/Events/p'

# Capacity and allocatable of every node, side by side
kubectl get nodes -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory,CAP_MEMORY:.status.capacity.memory'

# The node with the most allocatable memory (the kubelet reports it in Ki)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.memory}{"\n"}{end}' | sort -k2 -n -r
```

<details>
<summary>Line-by-line explanation</summary>

- `-o custom-columns='NAME:.metadata.name,CPU_REQ` — One row per Pod with its CPU request, memory request and memory limit. `[*]` lists every container's value, separated by commas, and `` means the field is not set.
- `sed -n '/Allocated resources/,/Events/p'` — Cuts `describe node` down to the Allocated resources table: the requests and limits of every Pod on the node, added up, as amounts and as a share of allocatable. This is what the scheduler counts, not live usage.
- `CPU:.status.allocatable.cpu` — Capacity is the whole machine. Allocatable is the part left for Pods. On kind every node is a container on the same host, so all three usually report the same numbers.
- `sort -k2 -n -r` — One `name value` line per node, sorted on the second column (`-k2`), as numbers (`-n`), largest first (`-r`). `-n` reads `8039348Ki` by its leading digits, which works only because every node reports Ki.

</details>

Full monitoring tools such as Prometheus keep history and send alerts, but the exam never needs them.

> [!IMPORTANT] **Read the question's key word twice**
> "Uses the most CPU" means `kubectl top --sort-by=cpu`. "Has the most allocatable memory" means `status.allocatable`, not usage. "Requests the most" means the Pod spec, or Allocated resources in `kubectl describe node`. Stay inside the namespace or label the question gives, because other Pods may be busier. Write the bare name. If a task asks for "the Pod" and the heavy container is a sidecar, the answer is still the Pod's name.

## 📝 Key Takeaways

- `kubectl top` shows usage right now. It needs metrics-server, and a new Pod has no numbers for about a minute.
- Usage is what a container uses. A request is what the scheduler sets aside. A limit is the most it may use. Allocatable is the part of a node left for Pods.
- Allocated resources in `kubectl describe node` adds up requests, not usage.
- Stay inside the namespace or label the question gives, and write only the bare name.

**📖 Official documentation:**

- [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) *(search: "resource metrics pipeline")*
- [kubectl top](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/) *(search: "kubectl top")*
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) *(search: "resource requests limits")*
- [Tools for Monitoring Resources](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-usage-monitoring/) *(search: "monitoring resources")*

---

### 🎯 Task: Find the Pod burning CPU

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Of the Pods with label `app=batch` in namespace `tsx-top`, find the one currently using the most CPU and write only its name to `/tmp/cka/top-cpu-pod.txt`. The Pods may be new; allow a minute for metrics to appear.

<details>
<summary>💡 Hints</summary>

- kubectl top pods supports -l and --sort-by=cpu.
- --no-headers and awk 'NR==1 {print $1}' give you just the name.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
for i in $(seq 1 30); do
  n=$(kubectl -n tsx-top top pods -l app=batch --no-headers 2>/dev/null | grep -c . || true)
  [ "$n" = "3" ] && break
  sleep 3
done
kubectl -n tsx-top top pods -l app=batch --sort-by=cpu
kubectl -n tsx-top top pods -l app=batch --sort-by=cpu --no-headers | awk 'NR==1 {print $1}' > /tmp/cka/top-cpu-pod.txt
cat /tmp/cka/top-cpu-pod.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answer folder.
- `for i in $(seq 1 30); do` — New Pods have no metrics for the first scrapes, so this waits up to about 90 seconds, 3 seconds per try, until `kubectl top` reports all three.
- `n=$(kubectl` — Counts the lines top prints for the `app=batch` Pods. While metrics are missing it prints an error instead, hidden by `2>/dev/null`, and the count is 0.
- `kubectl -n tsx-top top pods -l app=batch --sort-by=cpu` — Look at the table yourself: `job-bravo` runs a busy loop and sits near its 250m limit, while the other two idle near 0m.
- `--no-headers | awk` — The same list without its header; awk keeps the first name, the top CPU user, and `>` writes it to the answer file.
- `cat /tmp/cka/top-cpu-pod.txt` — The file should hold only `job-bravo`.

**Notes:** `job-bravo` runs a busy loop and sits at its 250m CPU limit. The other two idle near 0m. All three request only 20m, so the busy one uses far more than its request. `kubectl describe node` cannot show you that, because its Allocated resources table adds up requests, not usage. If `kubectl top` says metrics are not available, wait and try again. Do not guess from the Pod spec.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
out=/tmp/cka/top-cpu-pod.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
[ "$(tr -d '[:space:]' < $out 2>/dev/null)" = "job-bravo" ] && p "answer is job-bravo" || f "answer is the Pod with the highest CPU"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: The node with the most allocatable memory

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 2% |
| **Time** | 3 min |

**Question:**

Write the name of the node with the most **allocatable** memory to `/tmp/cka/top-mem-node.txt`. If several nodes share the highest value, write each of them on its own line, sorted by name.

<details>
<summary>💡 Hints</summary>

- Allocatable is a field on the Node object (status.allocatable.memory), not something kubectl top shows.
- On a kind lab every node reports the same host memory, so expect a tie.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl get nodes -o custom-columns='NAME:.metadata.name,MEMORY:.status.allocatable.memory'
# Normalize to Ki, keep every node that has the maximum, sort by name
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.memory}{"\n"}{end}' \
  | awk '{v=$2; m=1/1024; if (v ~ /Ki$/) m=1; else if (v ~ /Mi$/) m=1024; else if (v ~ /Gi$/) m=1048576; sub(/[KMG]i$/, "", v); printf "%s %.0f\n", $1, v*m}' \
  | awk '{n[NR]=$1; v[NR]=$2; if ($2 > max) max=$2} END {for (i=1; i<=NR; i++) if (v[i]==max) print n[i]}' \
  | sort > /tmp/cka/top-mem-node.txt
cat /tmp/cka/top-mem-node.txt
```

**Explanation:**

- `custom-columns='NAME:.metadata.name,MEMORY` — The quick answer: each node with its allocatable memory, read by eye. On kind the nodes usually share one value, so expect a tie.
- `kubectl get nodes -o jsonpath` — The scripted version starts with one `name value` line per node. The trailing `\` continues the pipeline on the next line.
- `| awk '{v=$2; m=1/1024;` — Converts every value to Ki so mixed units compare fairly: Ki stays, Mi is multiplied by 1024, Gi by 1048576, a plain byte count is divided by 1024. `sub()` strips the unit before the math.
- `| awk '{n[NR]=$1;` — Remembers each name and value, tracks the maximum, and at the end (`END`) prints every node whose value equals it, so ties are kept.
- `| sort >` — Sorts the names alphabetically, as the question asks, and writes them to the answer file.
- `cat /tmp/cka/top-mem-node.txt` — One node name per line.

**Notes:** On the exam, run `kubectl get nodes -o custom-columns=NAME:.metadata.name,MEMORY:.status.allocatable.memory` and compare the three or four values by eye. That is faster than any pipeline. `kubectl top nodes --sort-by=memory` is the wrong tool here. It sorts by memory *in use*. The control plane often uses the most, while its allocatable is the same as the workers'. `kubectl describe node` also shows an Allocatable block for each node, if you prefer it.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
out=/tmp/cka/top-mem-node.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
want=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.memory}{"\n"}{end}' 2>/dev/null \
  | awk '{v=$2; m=1/1024; if (v ~ /Ki$/) m=1; else if (v ~ /Mi$/) m=1024; else if (v ~ /Gi$/) m=1048576; sub(/[KMG]i$/, "", v); printf "%s %.0f\n", $1, v*m}' \
  | awk '{n[NR]=$1; v[NR]=$2; if ($2 > max) max=$2} END {for (i=1; i<=NR; i++) if (v[i]==max) print n[i]}' | sort)
[ -n "$want" ] && p "computed the expected node list" || f "computed the expected node list"
got=$(grep . $out 2>/dev/null | sed 's/[[:space:]]*$//' | sort)
[ -n "$want" ] && [ "$got" = "$want" ] && p "file lists the node(s) with the most allocatable memory" || f "file lists the node(s) with the most allocatable memory (want: $(echo $want))"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: The Pod using more memory than it requested

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `tsx-req`, one of the Pods labeled `app=cache` is using more memory than its container requests. Write only that Pod's name to `/tmp/cka/over-request.txt`. The Pods may be new; allow a minute for metrics to appear.

<details>
<summary>💡 Hints</summary>

- kubectl top pods gives the usage. The requests are in each Pod's spec.containers[].resources.
- The Pod using the most memory is not necessarily the one above its request.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
for i in $(seq 1 30); do
  n=$(kubectl -n tsx-req top pods -l app=cache --no-headers 2>/dev/null | grep -c . || true)
  [ "$n" = "3" ] && break
  sleep 3
done
kubectl -n tsx-req top pods -l app=cache
kubectl -n tsx-req get pods -l app=cache -o custom-columns='NAME:.metadata.name,MEM_REQ:.spec.containers[0].resources.requests.memory'
: > /tmp/cka/over-request.txt
for p in $(kubectl -n tsx-req get pods -l app=cache -o jsonpath='{.items[*].metadata.name}'); do
  used=$(kubectl -n tsx-req top pod "$p" --no-headers | awk '{print $3}' | sed 's/Mi$//')
  req=$(kubectl -n tsx-req get pod "$p" -o jsonpath='{.spec.containers[0].resources.requests.memory}' | sed 's/Mi$//')
  echo "$p used=$used Mi request=$req Mi"
  if [ "$used" -gt "$req" ]; then echo "$p" >> /tmp/cka/over-request.txt; fi
done
cat /tmp/cka/over-request.txt
```

**Explanation:**

- `for i in $(seq 1 30); do` — The same wait as in the CPU task: up to 30 tries, 3 seconds apart, until all three Pods have metrics.
- `grep -c . || true` — Counts the Pods that already have numbers.
- `kubectl -n tsx-req top pods -l app=cache` — Usage first: `cache-a` uses the most, about 64Mi, `cache-b` about 48Mi and `cache-c` almost nothing. The biggest user is not automatically the one over its request.
- `MEM_REQ:.spec.containers[0]` — Then the requests: 128Mi, 16Mi and 64Mi. Side by side, only `cache-b` uses more than it asked for.
- `: > /tmp/cka/over-request.txt` — `:` is a command that does nothing, so `: > file` creates the file empty, or empties it, before the loop appends to it.
- `for p in $(kubectl` — Loops over the three Pod names, which the jsonpath prints on one line separated by spaces.
- `used=$(` — Takes the Pod's MEMORY column (`$3`, for example `48Mi`) and strips `Mi` with sed, leaving a number the shell can compare.
- `req=$(` — Reads the first container's memory request the same way: `16Mi` becomes `16`. This works only because every value here is in Mi.
- `echo "$p used=` — Prints both numbers for each Pod so you can see the comparison.
- `if [ "$used" -gt "$req" ]` — `-gt` means greater than, for whole numbers. A Pod above its request is appended (`>>`) to the answer file.
- `cat /tmp/cka/over-request.txt` — Should show only `cache-b`.

**Notes:** `cache-a` uses the most memory, about 64Mi, but it requested 128Mi, so it stays within its request. `cache-b` uses about 48Mi against a 16Mi request. Why do these Pods use memory without running a real program? They write files to a `medium: Memory` emptyDir, which lives in RAM (tmpfs), and those files count as the container's memory. On the exam, put `kubectl top pods` next to the custom-columns view of the requests and compare by eye.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
out=/tmp/cka/over-request.txt

[ -s $out ] && p "answer file exists" || f "answer file exists"
[ "$(tr -d '[:space:]' < $out 2>/dev/null)" = "cache-b" ] && p "answer is cache-b" || f "answer is the Pod above its memory request"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
