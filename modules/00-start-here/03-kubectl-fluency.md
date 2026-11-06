# kubectl fluency

> **Module 0** · Lesson 0.3 · 45 minutes

The imperative commands that generate most exam YAML, the output formats and jsonpath recipes that read any cluster in one line, and the shell setup that makes all of it faster.

## Learning Objectives

- You can produce a correct manifest for a Pod, Deployment, Service, ConfigMap or Secret with a kubectl generator and --dry-run=client -o yaml, and find the generator for any other kind with --help.
- You can extract exactly the fields a question asks for with -o jsonpath, custom-columns, --sort-by and selectors.
- You can choose between edit, apply, replace --force and delete --force based on whether the field is mutable.


Two hours, up to twenty tasks: that is six minutes per task including reading, doing and checking. The difference between passing comfortably and running out of time is almost never Kubernetes knowledge; it is how many keystrokes stand between you and a correct object. This lesson is the keystroke budget. Everything here runs on the lab exactly as written.

## Shell setup: sixty seconds that pay back all exam

**Type this first on every exam host (k, completion and bash are already there; the rest is yours)**

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# Then the two commands you will use most:
k create deploy web --image=nginx:1.27 --replicas=2 $do > web.yaml
k delete pod stuck $now
```

<details>
<summary>Line-by-line explanation</summary>

- `alias k=kubectl` — From now on `k` means `kubectl`, so `k get pods` is `kubectl get pods`. The exam hosts already have it; typing it again is harmless.
- `export do=` — Saves flags in a variable named `do`. Writing `$do` later expands to `--dry-run=client -o yaml`: build the object and print it as YAML, but **create nothing**. Like any variable it lasts only in this shell, so set it again after each `ssh`.
- `export now=` — `$now` expands to `--force --grace-period=0`: delete right away instead of giving the Pod about 30 seconds to shut down. kubectl prints a warning when you use it; that is normal.
- `kubectl completion bash` — Turns on Tab completion: type `kubectl get po`, press Tab, and it fills in resource and Pod names for you.
- `complete -o default` — Completion is tied to the word `kubectl`. This line makes Tab work for the alias `k` too.
- `k create deploy web` — Really `kubectl create deployment web --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml`. Nothing is created: kubectl writes correct YAML, and `> web.yaml` saves it to a file you edit and then `k apply -f`.
- `k delete pod stuck $now` — Really `kubectl delete pod stuck --force --grace-period=0`. The Pod is gone at once, so you do not wait 30 seconds every time you redo one.

</details>

## Learn the patterns, not the commands

You do not need to memorize seventy commands. Almost every way of making or changing an object follows one of five shapes, and one sentence holds them all: **run** a Pod, **expose** a Service, **create** everything else, **set** or **scale** to change it, and add `$do` to see the YAML instead.

| You want | Pattern | Example |
| --- | --- | --- |
| A Pod | `k run NAME --image=IMAGE` | `k run web --image=nginx:1.27` |
| A Service for an existing object | `k expose KIND NAME --port=PORT` | `k expose deploy web --port=80` |
| Anything else | `k create KIND NAME --flags` | `k create deploy web --image=nginx:1.27` |
| A change | `k set`, `k scale`, `k label` | `k scale deploy web --replicas=5` |
| YAML, not the object | add `$do > file.yaml` to any of these | `k run web --image=nginx:1.27 $do > web.yaml` |

*[Interactive visual: command-anatomy]*

> [!TIP] **Forgot a flag? Ask kubectl**
> `k create KIND --help` starts with ready-to-copy examples, and `k explain` describes any field. Both work on the exam. So memorize the patterns and the commands you type every day, and look the rest up in seconds.

## Imperative generators

The generators you will use from the first week, grouped by topic. Skim each block once and press **Explain** on anything new; the practice cards after them are where it sticks.

**Pods and Deployments**

```bash
# A Pod
k run web --image=nginx:1.27 --port=80 --labels=app=web
k run once --image=busybox:1.36 --restart=Never -- sh -c 'date'
k run web2 --image=nginx:1.27 --command -- sh -c 'sleep 3600'
k run tmp --image=busybox:1.36 -it --rm --restart=Never -- sh

# A Deployment
k create deploy web --image=nginx:1.27 --replicas=3 --port=80
```

<details>
<summary>Line-by-line explanation</summary>

- `k run web --image=nginx:1.27 --port=80` — One Pod named `web`. `--port` records the container port and `--labels` sets `app=web`, so a Service can find it.
- `k run once` — A one-off Pod: `--restart=Never` runs it once, with no restarts. Everything after `--` is passed to the container as its arguments.
- `k run web2` — `--command` makes the words after `--` replace the image's own command, instead of being passed to it as arguments.
- `k run tmp` — A throwaway shell: `-it` attaches your terminal and `--rm` deletes the Pod when you exit. Handy for testing DNS or a Service from inside the cluster.
- `k create deploy web --image=nginx:1.27 --replicas=3` — A Deployment with 3 replicas. kubectl labels its Pods `app=web`, after the name.

</details>

**Services**

```bash
# A Service for an existing object (--type can also be NodePort or LoadBalancer)
k expose deploy web --name=web-svc --port=80 --target-port=8080 --type=ClusterIP

# A Service on its own (the selector becomes app=web, from the name)
k create svc clusterip web --tcp=80:8080
```

<details>
<summary>Line-by-line explanation</summary>

- `k expose deploy web` — A Service that copies the Deployment's selector, so it finds the right Pods without you typing labels. `--port` is the Service's port, `--target-port` the container's.
- `k create svc clusterip web` — A Service with no existing object behind the command. `--tcp=80:8080` means port 80 on the Service and 8080 on the Pods.

</details>

**Configuration and namespaces**

```bash
# A ConfigMap
k create cm app-cfg --from-literal=KEY=value --from-file=app.properties
k create cm app-env --from-env-file=.env

# A Secret
k create secret generic db --from-literal=password=s3cret

# A Namespace
k create ns team-a
```

<details>
<summary>Line-by-line explanation</summary>

- `k create cm app-cfg` — A ConfigMap from a literal key and a file; the file name becomes the key.
- `k create cm app-env` — An env file gives one key per `KEY=VALUE` line. kubectl refuses to combine it with the other sources, so it gets its own ConfigMap.
- `k create secret generic db` — The everyday Secret: keys from literals or files, like a ConfigMap. kubectl base64-encodes the values for you.
- `k create ns team-a` — A Namespace.

</details>

**Changing what already exists**

```bash
# Scale, or change the image
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.26

# Labels (a trailing - removes one)
k label pod web tier=frontend --overwrite
k label pod web tier-
```

<details>
<summary>Line-by-line explanation</summary>

- `k scale deploy web --replicas=5` — Changes the replica count right away.
- `k set image deploy/web` — Changes the image of the container named `nginx`, which starts a rolling update.
- `k label pod web tier=frontend --overwrite` — Adds a label, or changes it: `--overwrite` is required when the key already exists.
- `k label pod web tier-` — A key followed by `-` removes that label.

</details>

Every other kind of object has a generator too, and you will meet each one in the lesson about that object: Jobs and CronJobs in [Workloads](/cka/workloads/daemonsets-jobs-cronjobs), Roles and ServiceAccounts in [RBAC](/cka/architecture/rbac), Ingress in [Networking](/cka/networking/ingress), taints in [Scheduling](/cka/workloads/scheduling-constraints) and drain in [Upgrades](/cka/architecture/cluster-upgrades). The [exam cheat sheet](/cka/exam/cheat-sheet) puts them all on one page. Until then, `k create --help` lists every kind it can make.

**Generate, inspect, edit, apply: the loop behind most tasks**

```bash
# 1. Generate a manifest without touching the cluster
k -n team-a create deploy api --image=nginx:1.27 --replicas=3 $do > api.yaml

# 2. Find the field you need to add, with the exact spelling and type
k explain deploy.spec.strategy
k explain pod.spec.containers.livenessProbe --recursive | less
k explain pod.spec.tolerations

# 3. Edit the file in vim, then apply it
k apply -f api.yaml

# Multi-resource trick: generate a pod, pipe straight into a label change, apply in one line
k run tmp --image=busybox:1.36 --restart=Never $do -- sleep 3600 | k label --local -f - tier=debug -o yaml | k apply -f -

# --help is faster than the docs for flags
k create deploy --help | less
k run --help | grep -A2 -- --command
```

<details>
<summary>Line-by-line explanation</summary>

- `create deploy api` — Writes a Deployment named `api` in namespace `team-a` with 3 replicas to `api.yaml`. Because of `$do` it is only printed, not created.
- `k explain deploy.spec.strategy` — Shows the documentation for one field, straight from the cluster: what it is, its type and the fields inside it. No browser needed.
- `--recursive | less` — `--recursive` lists every nested field at once, so you see the whole shape of a liveness probe. In `less`, press `/` to search and `q` to quit.
- `k explain pod.spec.tolerations` — Same idea for tolerations. Use explain whenever you are unsure of a field's exact spelling or where it sits.
- `k apply -f api.yaml` — Sends the file to the cluster. `apply` creates the object if it is missing and updates it if it exists, so you can edit and re-apply as often as you like.
- `k run tmp` — Generates a Pod that runs `sleep 3600` (everything after `--` is the container's command), adds the label `tier=debug` without contacting the cluster (`--local`), then creates it. `-f -` means read the YAML from the pipe.
- `k create deploy --help` — Every command lists its flags and ready-made examples. Scrolling `--help` is often faster than searching the docs.
- `grep -A2 -- --command` — Searches the help text for `--command` and shows 2 lines after each match. The first `--` tells grep that what follows is the search text, not one of its own options.

</details>

### 🃏 Drill: Practice: make it from memory

Read the task, type the command without looking up, then check. Cards you miss come back at the end of the round. Your progress stays in this browser.

<details>
<summary>A Pod named `web` running `nginx:1.27`.</summary>

```bash
k run web --image=nginx:1.27
```

*Pods are the one kind you make with `run`.*

</details>

<details>
<summary>The YAML for that same Pod, saved to `pod.yaml`, without creating it.</summary>

```bash
k run web --image=nginx:1.27 $do > pod.yaml
```

*`$do` is `--dry-run=client -o yaml`, from the shell setup.*

</details>

<details>
<summary>A throwaway `busybox:1.36` shell that is deleted when you exit.</summary>

```bash
k run tmp --image=busybox:1.36 -it --rm --restart=Never -- sh
```

*`-it` attaches you, `--rm` cleans up, and everything after `--` is the command.*

</details>

<details>
<summary>A Deployment named `api`, image `nginx:1.27`, 3 replicas.</summary>

```bash
k create deploy api --image=nginx:1.27 --replicas=3
```

</details>

<details>
<summary>A Service `web-svc` for Deployment `web`: port 80, sending traffic to container port 8080.</summary>

```bash
k expose deploy web --name=web-svc --port=80 --target-port=8080
```

*`expose` copies the Deployment's selector, so you never type labels.*

</details>

<details>
<summary>A ConfigMap `app-cfg` with the key `MODE=prod`.</summary>

```bash
k create cm app-cfg --from-literal=MODE=prod
```

</details>

<details>
<summary>A Secret `db` holding `password=s3cret`.</summary>

```bash
k create secret generic db --from-literal=password=s3cret
```

*`generic` is the everyday type; `tls` and `docker-registry` are the other two.*

</details>

<details>
<summary>Change the image of container `nginx` in Deployment `web` to `nginx:1.26`.</summary>

```bash
k set image deploy/web nginx=nginx:1.26
```

</details>

<details>
<summary>Scale Deployment `web` to 5 replicas.</summary>

```bash
k scale deploy web --replicas=5
```

</details>

<details>
<summary>You need a CronJob, a kind this lesson does not cover. How do you find its flags fast?</summary>

```bash
k create cronjob --help
```

*The examples at the top of every `--help` are ready to copy, and `--help` works on the exam.*

</details>


## Reading the cluster

**Output formats and filters**

```bash
k get pods -o wide                      # node, IP, nominated node, readiness gates
k get deploy web -o yaml                # the whole object; pipe to grep or less
k get pod web -o json | less
k get pods -o name                      # pod/web, pod/api... handy for xargs and loops
k get pods -A                           # every namespace
k get pods -l app=web,tier!=cache       # label selectors; also 'env in (prod,staging)'
k get pods --show-labels
k get pods --field-selector=status.phase!=Running -A
k get pods --sort-by=.metadata.creationTimestamp
k get events --sort-by=.lastTimestamp -n team-a
k get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
k get pods -w                           # watch; Ctrl+C to stop
k api-resources | grep -i policy        # short names, api groups, namespaced or not
k api-versions | grep autoscaling
```

<details>
<summary>Line-by-line explanation</summary>

- `k get pods -o wide` — Adds extra columns, most usefully the node each Pod runs on and its IP.
- `k get deploy web -o yaml` — Prints the whole object as the cluster stores it, including fields you never set. The quickest way to see exactly what is there.
- `k get pod web -o json` — The same object as JSON. jsonpath expressions (next block) are easier to write once you can see this structure.
- `k get pods -o name` — Prints only `pod/` lines, ready to feed into a loop or `xargs`.
- `k get pods -A` — `-A` is short for `--all-namespaces`: Pods everywhere, not only in the current namespace.
- `-l app=web,tier!=cache` — `-l` filters by labels: Pods with `app=web` **and** a `tier` other than `cache`. Labels are how Kubernetes groups objects, so you will filter like this all the time.
- `--show-labels` — Adds a column with each Pod's labels, so you can see what a selector would match.
- `--field-selector` — Filters on object fields instead of labels. Here: every Pod whose phase is not Running, in all namespaces. A fast way to find broken Pods.
- `--sort-by=.metadata.creationTimestamp` — Sorts by any field, here oldest first.
- `k get events` — Events record what happened to objects: scheduled, image pulled, failed. Sorted by time, the latest are at the bottom, which is where you look first.
- `custom-columns=NAME` — Builds your own table: each `HEADING:path` pair is a column title and the field it shows.
- `k get pods -w` — Keeps running and prints a new line every time a Pod changes. Press Ctrl+C to stop.
- `k api-resources` — Lists every resource type the cluster knows, with its short name (`deploy`, `svc`), its API group and whether it lives in a namespace.
- `k api-versions` — Lists the API versions the cluster serves, so you can check the right `apiVersion` for a manifest.

</details>

**jsonpath recipes (single quotes outside, double quotes inside)**

```bash
# One field
k get deploy web -o jsonpath='{.spec.replicas}'

# A list, space separated
k get pods -o jsonpath='{.items[*].metadata.name}'

# One item per line, several fields: range ... end
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'

# Filter inside a list: the address whose type is InternalIP
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Filter whole items: pods on one node
k get pods -A -o jsonpath='{range .items[?(@.spec.nodeName=="cka-worker")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'

# Container images in a Deployment, taints on nodes, the InternalIP of one node
k get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}'
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.taints[*].key}{"\n"}{end}'
k get node cka-worker -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'

# Tabular output sorted by a jsonpath (sorted on the server response, works with custom-columns)
k -n kube-system get pods --sort-by=.metadata.name -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName

# When jsonpath gets ugly, yq is on the exam hosts
k get deploy web -o yaml | yq '.spec.template.spec.containers[].image'
```

<details>
<summary>Line-by-line explanation</summary>

- `'{.spec.replicas}'` — Prints one field. Read the path like a folder path into the object: `spec`, then `replicas`.
- `'{.items[*].metadata.name}'` — A list command returns `items`, and `[*]` means every item. You get all the names on one line, separated by spaces.
- `{.status.nodeInfo.kubeletVersion}` — `range … end` is a loop. For each node it prints the name, a space, the kubelet version and `{"\n"}`, a newline, so you get one node per line.
- `status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'` — `?(…)` is a filter: of all the node's addresses, keep the one whose `type` is `InternalIP`. `@` means "the element being checked".
- `items[?(@.spec.nodeName=="cka-worker")]` — Filters whole Pods: only those whose `spec.nodeName` is `cka-worker`, printed as `namespace/name`.
- `containers[*].image}'` — The image of every container in the Deployment. Pods get their spec from `spec.template`, which is why the path goes through it.
- `{.spec.taints[*].key}` — Each node's name followed by the keys of its taints. A node with no taints prints only its name.
- `k get node cka-worker -o jsonpath` — For a single object there is no `items` list, so the path starts directly at `.status`.
- `--sort-by=.metadata.name -o custom-columns` — Sorting and custom columns together: a clean two-column table of kube-system Pods and their nodes. Add `> file` when a task wants it saved.
- `yq '` — `yq` reads YAML with a simpler path syntax, and `containers[]` walks every container. Reach for it when a jsonpath gets hard to get right.

</details>

### 🃏 Drill: Practice: read the cluster

Same idea for reading: type the command, then check.

<details>
<summary>Every Pod in every namespace, with the node it runs on.</summary>

```bash
k get pods -A -o wide
```

</details>

<details>
<summary>Only the replica count of Deployment `web`.</summary>

```bash
k get deploy web -o jsonpath='{.spec.replicas}'
```

*Single quotes outside, the path inside braces, starting with a dot.*

</details>

<details>
<summary>Only the Pods labeled `app=web`.</summary>

```bash
k get pods -l app=web
```

</details>

<details>
<summary>The events in namespace `team-a`, newest at the bottom.</summary>

```bash
k get events -n team-a --sort-by=.lastTimestamp
```

</details>

<details>
<summary>A two-column table of every Pod's name and node.</summary>

```bash
k get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName'
```

</details>

<details>
<summary>The fields you can set in a container's `livenessProbe`.</summary>

```bash
k explain pod.spec.containers.livenessProbe
```

</details>

<details>
<summary>Make `team-a` the default namespace for every later command.</summary>

```bash
k config set-context --current --namespace=team-a
```

</details>


## Changing objects: which tool

| You want to | Use | Good to know |
| --- | --- | --- |
| Change a field that can change (image, replicas, labels, env) | `k edit`, `k set`, `k scale`, `k label` | `k edit` opens the live object in vim. Save something invalid and it reopens with the error at the top. |
| Apply a file you generated or wrote | `k apply -f file.yaml` | Creates the object, or updates it if it exists. The usual step after `$do`. |
| Change a field that cannot change | `k replace --force -f file.yaml` | Deletes and recreates the object: the only way to change an immutable field. |
| Remove a Pod stuck in Terminating | `k delete pod X $now` | Skips the grace period. Use it on Pods only, never on nodes or namespaces. |
| Fix Pods that a Deployment owns | Change the Deployment, not the Pods | The rollout replaces the Pods for you. |

Which fields are immutable? A Pod's image can change. Its containers' names, its volumes, its `nodeName`, resources on a running Pod (without the in-place resize feature) and most of a Service's or a Job's spec cannot. When `k edit` refuses to save, it writes your version to a file under `/tmp` and prints the path: run `k replace --force -f` on that file.

## Contexts and namespaces

**Contexts and namespaces**

```bash
k config get-contexts                            # the * marks the current one
k config use-context kind-cka
k config current-context
k config set-context --current --namespace=team-a  # every later command defaults to team-a
k config view --minify                             # the active cluster, user and namespace only
k config view --minify -o jsonpath='{..namespace}'

# When a kubeconfig is given as a file in the task
k --kubeconfig=/root/other.kubeconfig get nodes
export KUBECONFIG=/root/other.kubeconfig
```

<details>
<summary>Line-by-line explanation</summary>

- `k config get-contexts` — A **context** is a saved combination of cluster, user and namespace. This lists them; the `*` marks the one in use.
- `k config use-context kind-cka` — Switches to the `kind-cka` context. On the exam, run the command the task gives you first: a right answer on the wrong cluster scores zero.
- `k config current-context` — Prints the context you are on, for a quick check.
- `set-context --current --namespace=team-a` — Makes `team-a` the default namespace, so later commands can drop `-n team-a`. It is easy to forget you did this, so check before each task.
- `k config view --minify  ` — Shows the kubeconfig for the current context only: which cluster, which user and which namespace.
- `{..namespace}` — `..` searches at any depth, so this prints just the current namespace. Empty output means `default`.
- `--kubeconfig=/root/other.kubeconfig` — Uses a different kubeconfig file for this one command. Tasks sometimes hand you a file like this for another cluster.
- `export KUBECONFIG` — Makes that file the default for every kubectl command in this shell, until you close it or unset the variable.

</details>

> [!IMPORTANT] **The grader reads the object, not your history**
> Whether a Deployment came from `kubectl create`, a file you wrote in vim, or `kubectl edit` makes no difference to the result. What does make a difference is the namespace, the exact name, the exact image tag, the labels the question listed, and the replica count once the rollout finished. After each task, run `k get   -n  -o yaml | grep -E 'image:|replicas:|name:'` or a targeted `-o jsonpath` and compare against the question text. Thirty seconds of checking is cheaper than a lost task.

**📖 Official documentation:**

- [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) *(search: "cheat sheet")*
- [JSONPath support](https://kubernetes.io/docs/reference/kubectl/jsonpath/) *(search: "jsonpath")*
- [kubectl create (generated reference)](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/) *(search: "kubectl create")*
- [Configure access to multiple clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/) *(search: "configure access multiple clusters")*

---

### 🎯 Task: Generate a manifest, then apply it

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Using kubectl and without creating anything on the cluster yet, generate a Deployment manifest and save it to `/tmp/cka/fluency/web.yaml`: name `web`, namespace `fd-fluency`, image `nginx:1.27`, 2 replicas. Add the label `tier=frontend` to the Deployment's own metadata in that file, then create the Deployment from the file. Both the file and the live Deployment must carry the label and have 2 replicas.

<details>
<summary>💡 Hints</summary>

- kubectl create deployment ... --dry-run=client -o yaml > file. The -n flag puts the namespace into the manifest.
- The generated metadata.labels block already has app: web; add tier: frontend under it (or pipe through kubectl label --local -f - ... -o yaml).

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n fd-fluency create deployment web --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml \
  | kubectl label --local -f - tier=frontend -o yaml > /tmp/cka/fluency/web.yaml
kubectl apply -f /tmp/cka/fluency/web.yaml
kubectl -n fd-fluency rollout status deploy/web --timeout=120s
```

**Explanation:**

- `create deployment web` — Generates the Deployment's YAML without creating it. The `\` at the end continues the command on the next line.
- `kubectl label --local` — Adds the label `tier=frontend` to that YAML without contacting the cluster, then `>` saves the result to the file the task asked for.
- `kubectl apply -f` — Creates the Deployment from the saved file.
- `rollout status` — Waits until both replicas are running, or fails after 120 seconds.

**Notes:** On the exam you would redirect the generated YAML to the file, open it in vim, add `tier: frontend` under `metadata.labels` (two-space indent, same level as `app: web`) and apply. The `kubectl label --local -f -` pipeline is the non-interactive equivalent and worth knowing: `--local` edits the manifest on stdin without contacting the API server. Note that the label goes on the Deployment, not on its Pods; the Pod template labels are a different field, and the question did not ask for them.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=fd-fluency
file=/tmp/cka/fluency/web.yaml
d="kubectl -n $ns get deploy web -o jsonpath"

[ -f "$file" ] && p "file exists" || f "file exists"
grep -qE '^kind: Deployment' "$file" 2>/dev/null && p "file kind: Deployment" || f "file kind: Deployment"
grep -qE '^  name: web$' "$file" 2>/dev/null && p "file name: web" || f "file name: web"
grep -qE '^  replicas: 2$' "$file" 2>/dev/null && p "file replicas: 2" || f "file replicas: 2"
grep -qE '^    tier: frontend$' "$file" 2>/dev/null && p "file label tier: frontend" || f "file label tier: frontend"
kubectl -n $ns get deploy web >/dev/null 2>&1 && p "deployment web exists in $ns" || f "deployment web exists in $ns"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "live replicas = 2" || f "live replicas = 2"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "live image nginx:1.27" || f "live image nginx:1.27"
[ "$($d='{.metadata.labels.tier}' 2>/dev/null)" = "frontend" ] && p "live label tier=frontend" || f "live label tier=frontend"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Node names and InternalIPs with jsonpath

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Using a single `kubectl get nodes` command with a jsonpath expression, write the name and the InternalIP of every node in the cluster to `/tmp/cka/fluency/nodes.txt`. One node per line, in the form ` ` separated by one space, nothing else in the file.

<details>
<summary>💡 Hints</summary>

- {range .items[*]} ... {end} loops over nodes; {"\n"} ends each line.
- The InternalIP lives in .status.addresses, a list; filter it with [?(@.type=="InternalIP")].address.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' > /tmp/cka/fluency/nodes.txt
cat /tmp/cka/fluency/nodes.txt
```

**Explanation:**

- `kubectl get nodes -o jsonpath` — Loops over the nodes and prints each name and InternalIP on its own line; `>` saves that to the file the task names.
- `cat /tmp/cka/fluency/nodes.txt` — Shows the file so you can compare it with what the task asked for.

**Notes:** `kubectl get nodes -o wide` shows the same two columns, so `kubectl get nodes -o wide --no-headers | awk '{print $1, $6}'` is a legitimate fallback if jsonpath fights you. On the exam, if the question says "using jsonpath" the grader still only sees the file, but practicing the jsonpath form is the point of this task: the `[?(@.type=="InternalIP")]` filter is the single most reused jsonpath pattern in the whole exam.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/fluency/nodes.txt

[ -s "$file" ] && p "file exists and is not empty" || f "file exists and is not empty"
want="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | sort)"
got="$(awk 'NF{print $1" "$2}' "$file" 2>/dev/null | sort)"
[ "$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "$(grep -c . "$file" 2>/dev/null)" ] && p "one line per node" || f "one line per node"
[ -n "$got" ] && [ "$got" = "$want" ] && p "names and InternalIPs match the cluster" || f "names and InternalIPs match the cluster"
[ -z "$(awk 'NF>2' "$file" 2>/dev/null)" ] && p "no extra columns" || f "no extra columns"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A sorted custom-columns listing

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Write a listing of all Pods in the `kube-system` namespace to `/tmp/cka/fluency/kube-system-pods.txt`. Use kubectl custom columns with exactly two columns, headed `POD` (the Pod name) and `NODE` (the node the Pod runs on), sorted by Pod name. Keep the header line.

<details>
<summary>💡 Hints</summary>

- -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
- --sort-by=.metadata.name works together with custom-columns.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n kube-system get pods --sort-by=.metadata.name -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName > /tmp/cka/fluency/kube-system-pods.txt
cat /tmp/cka/fluency/kube-system-pods.txt
```

**Explanation:**

- `custom-columns=POD` — A two-column table of kube-system Pods and their nodes, sorted by Pod name, saved to the file.
- `cat /tmp/cka/fluency/kube-system-pods.txt` — Check the file before you move on: the grader compares it with the live cluster.

**Notes:** Custom columns take any jsonpath without the braces. `--sort-by` takes a jsonpath too and sorts before printing, so it combines with any output format. If you ever need the file without the header, add `--no-headers`; here the question wanted it kept, which is exactly the kind of detail a second read catches.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/fluency/kube-system-pods.txt

[ -s "$file" ] && p "file exists and is not empty" || f "file exists and is not empty"
[ "$(head -1 "$file" 2>/dev/null | awk '{print $1" "$2}')" = "POD NODE" ] && p "header POD NODE" || f "header POD NODE"
[ -z "$(awk 'NF!=2' "$file" 2>/dev/null)" ] && p "exactly two columns on every line" || f "exactly two columns on every line"
want="$(kubectl -n kube-system get pods --sort-by=.metadata.name -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --no-headers 2>/dev/null | awk '{print $1" "$2}')"
got="$(tail -n +2 "$file" 2>/dev/null | awk 'NF{print $1" "$2}')"
[ -n "$got" ] && [ "$got" = "$want" ] && p "rows match kube-system pods, sorted by name" || f "rows match kube-system pods, sorted by name"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 0: Start here*
