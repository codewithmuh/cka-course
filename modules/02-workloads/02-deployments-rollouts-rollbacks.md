# Deployments, rolling updates and rollbacks

> **Module 2** · Lesson 2.2 · 35 minutes

How a Deployment runs your Pods through ReplicaSets, how to control a rolling update, and how to undo one that went wrong.

## Learning Objectives

- You can create a Deployment with one command, save it as YAML, and change its update strategy before you apply it.
- You can change an image, watch the rollout, read its history and roll back to a chosen revision.
- You can spot a stuck rollout from the Deployment's conditions and fix it in under two minutes.


A **Deployment** keeps a set number of copies of your app running, and lets you update them without downtime. Say you run a Django app as 3 Pods. To ship version 2, you change the image, and the Deployment swaps the Pods a few at a time.

Deployments show up in almost every CKA exam. Sometimes the task is direct: *create, scale, update, roll back*. Sometimes it is a troubleshooting task where an update got stuck. The commands are short. What costs time is not knowing which field the grader reads, so this lesson names those fields as it goes.

## What a Deployment actually manages

A Deployment does not manage Pods directly. It works through a middle layer, the **ReplicaSet**. A ReplicaSet keeps an exact number of identical Pods running.

**Deployment, ReplicaSets and Pods**

*You create and edit the Deployment. It creates one ReplicaSet per version of the Pod template, and each ReplicaSet runs the Pods.*

`Deployment` — what you create and edit → `ReplicaSets` — one per version
  - `Version 2` — current: 3 Pods
  - `Version 1` — old: 0 Pods, kept for rollback → `Pods` — 3 running copies of version 2

- Every change to the Pod template (`spec.template`), such as a new image, creates a new ReplicaSet.
- The Deployment then scales the new ReplicaSet up and the old one down, following its strategy.
- Old ReplicaSets are kept, scaled to zero. They are your rollback points. A Deployment keeps 10 by default, and `spec.revisionHistoryLimit` changes that number.

**Create one, then look at what it created**

```bash
kubectl create deployment web --image=nginx:1.27 --replicas=3
kubectl get deploy,rs,pods -l app=web
# The ReplicaSet name is <deployment>-<pod-template-hash>; the hash also lands on every Pod.
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl create deployment web` — Creates a Deployment named `web` that runs 3 copies of an nginx Pod. kubectl names the container after the image, `nginx`, and labels the Pods `app=web`.
- `get deploy,rs,pods` — Three resource types in one command: separate them with commas and no spaces. You see one Deployment, the ReplicaSet it created, and that ReplicaSet's three Pods.

</details>

Changing something *outside* the template, such as `spec.replicas`, does not create a new ReplicaSet. The current one just grows or shrinks, and no new revision is made. This matters when a task says "roll back to the previous version": scaling up is not a version.

## Shaping the rollout

A **rolling update** replaces old Pods with new ones a few at a time, so the app keeps serving. It is the default strategy, `RollingUpdate`. Two settings control its pace:

- `maxSurge`: how many *extra* Pods may exist above `replicas` during the update.
- `maxUnavailable`: how many Pods may be *missing* below `replicas` during the update.

Both take a number or a percentage, and both default to 25%. Example: with 4 replicas, `maxSurge: 1` and `maxUnavailable: 0`, you never have fewer than 4 ready Pods and never more than 5 Pods in total.

The other strategy is `Recreate`. It stops every old Pod first, and only then starts the new ones. Use it when two versions must never run at the same time, for example an app whose old and new versions cannot share one database.

| Setting | What happens during an update | Typical exam wording |
| --- | --- | --- |
| `maxSurge: 1`, `maxUnavailable: 0` | Always at full size. One extra Pod is added at a time | "no downtime", "never fewer than N Pods" |
| `maxSurge: 0`, `maxUnavailable: 1` | Never above full size. One Pod is replaced at a time | "the cluster has no spare resources" |
| `maxSurge: 25%`, `maxUnavailable: 25%` | The defaults. Surge rounds up, unavailable rounds down | Nothing said about the strategy |
| `type: Recreate` | All old Pods stop before any new Pod starts | "versions must not overlap" |

*[Interactive visual: rolling-update]*

**A Deployment with an explicit strategy**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: wl-rollout
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: apps/v1` — Deployments live in the `apps` API group, so the version is `apps/v1`, not the plain `v1` a Pod uses.
- `replicas: 3` — How many Pods to keep running. Changing only this number scales the Deployment; it does not create a revision.
- `revisionHistoryLimit: 5` — Keep at most 5 old ReplicaSets as rollback points, instead of the default 10.
- `strategy:` — How Pods are replaced when the template changes. It sits directly under `spec`, at the same indent as `replicas`.
- `maxSurge: 1` — Together with `maxUnavailable: 0` on the next line: start one extra new Pod, wait until it is ready, then remove an old one. Capacity never drops below 3.
- `selector:` — How the Deployment finds its Pods. `matchLabels` must match the labels under `template.metadata.labels`, or the API rejects the Deployment. The selector cannot be changed after creation.
- `template:` — The Pod blueprint: a Pod's `metadata` and `spec`, without apiVersion and kind. Any change under it creates a new ReplicaSet and a rollout.
- `labels:` — Every Pod gets these labels. They are what the selector above matches.
- `- name: nginx` — The container name. `kubectl set image deploy/api nginx=…` in the next block refers to it.

</details>

> [!TIP] **The fastest way to write that on the exam**
> Generate the skeleton first: `kubectl create deployment api --image=nginx:1.27 --replicas=3 -n wl-rollout --dry-run=client -o yaml > api.yaml`. Then add the strategy lines in vim. The `strategy` block sits at the same indent as `replicas`. Apply it with `kubectl apply -f api.yaml`.

## Driving a rollout

These are the commands you will use most. Each one names the Deployment as `deploy/api`: the type, a slash, then the name.

**The commands you will actually type**

```bash
# Change the image (container name is "nginx" when created with kubectl create deployment --image=nginx:…)
kubectl -n wl-rollout set image deploy/api nginx=nginx:1.26

# Block until the rollout finishes or fails. Always run this before moving to the next question.
kubectl -n wl-rollout rollout status deploy/api --timeout=120s

# Revisions, and the template of one revision
kubectl -n wl-rollout rollout history deploy/api
kubectl -n wl-rollout rollout history deploy/api --revision=2

# Undo to the previous revision, or to a specific one
kubectl -n wl-rollout rollout undo deploy/api
kubectl -n wl-rollout rollout undo deploy/api --to-revision=1

# Pause so several edits become one revision, then resume
kubectl -n wl-rollout rollout pause deploy/api
kubectl -n wl-rollout set image deploy/api nginx=nginx:1.27
kubectl -n wl-rollout rollout resume deploy/api

# Scale (not a revision)
kubectl -n wl-rollout scale deploy/api --replicas=5
```

<details>
<summary>Line-by-line explanation</summary>

- `set image deploy/api` — Changes the image of the container named `nginx` to `nginx:1.26`. That edits the template, so it starts a rollout and a new revision. `deploy/api` is the `type/name` form.
- `rollout status` — Prints progress and returns once every new Pod is available. After 120 seconds it gives up with an error. A timeout here is your sign that the rollout is stuck.
- `rollout history deploy/api` — Lists the revisions, oldest first, with the CHANGE-CAUSE column.
- `--revision=2` — Shows the Pod template stored in revision 2, so you can see which image it ran before you roll back to it.
- `rollout undo deploy/api` — Goes back to the previous revision. The undo itself gets a new revision number that carries the old template.
- `--to-revision=1` — Rolls back to a chosen revision from the history list, instead of one step back.
- `rollout pause` — Pauses rollouts. Template changes are still saved, but no new Pods roll out until you resume.
- `nginx=nginx:1.27` — Changes the image while the Deployment is paused, so nothing rolls out yet. Any other edits you make now join the same revision.
- `rollout resume` — Rolls out everything changed during the pause as a single new revision.
- `scale deploy/api` — Changes only `spec.replicas`. The current ReplicaSet grows to 5 Pods, and no revision is created.

</details>

The `CHANGE-CAUSE` column in `rollout history` comes from the annotation `kubernetes.io/change-cause` on the Deployment. If a task wants a cause recorded, set it yourself right after the change: `kubectl annotate deploy/api kubernetes.io/change-cause="image to 1.26"`.

## When a rollout gets stuck

A rollout is **stuck** when the new Pods never become ready. The usual causes are a wrong image tag, a missing Secret, a readiness probe that never passes, or no node with room.

Kubernetes does not roll back by itself. It waits for `spec.progressDeadlineSeconds` (600 seconds by default). Then it sets the `Progressing` condition to `False`, with reason `ProgressDeadlineExceeded`, and keeps waiting.

1. Read the Deployment's conditions with `kubectl describe deploy`.
2. Find the new ReplicaSet and its Pods.
3. Read those Pods' events. They usually name the cause.
4. Decide: fix the problem, or undo to the version that worked.

**Diagnose, then decide: fix forward or undo**

```bash
kubectl -n wl-rollout describe deploy api | sed -n '/Conditions/,/OldReplicaSets/p'
kubectl -n wl-rollout get rs -l app=api
kubectl -n wl-rollout get pods -l app=api
kubectl -n wl-rollout describe pod <new-pod> | tail -20

# Undo is almost always the exam answer when the question says "the previous version worked".
kubectl -n wl-rollout rollout undo deploy/api
kubectl -n wl-rollout rollout status deploy/api --timeout=120s
```

<details>
<summary>Line-by-line explanation</summary>

- `describe deploy api` — Prints only the part of describe from Conditions to OldReplicaSets. Once the 600-second deadline has passed, a stuck rollout shows `Progressing` False with reason `ProgressDeadlineExceeded`.
- `get rs -l app=api` — Old and new ReplicaSets side by side. A new one whose READY stays below DESIRED is the half-finished rollout.
- `get pods -l app=api` — The new ReplicaSet's Pods are the ones in ImagePullBackOff, Pending or not Ready. Their names start with the new ReplicaSet's name.
- `| tail -20` — Put a real Pod name in place of ``. `tail -20` keeps the last 20 lines, the Events list, where the cause is usually spelled out.
- `rollout undo` — Brings back the previous revision's template. The old ReplicaSet scales up again, and the broken one scales to zero.
- `rollout status` — Confirms the undo finished before you move on.

</details>

> [!IMPORTANT] **What the grader reads**
> The grader reads the live Deployment: `spec.replicas`, the image in `spec.template.spec.containers[].image`, `spec.strategy`, and often `status.availableReplicas`. It cannot see whether you used `set image`, `edit` or `apply`. So after every rollout task, run `kubectl get deploy  -o wide`. Compare its IMAGES and READY columns with the task before you move on.

## 📝 Key Takeaways

- A Deployment runs Pods through ReplicaSets: one ReplicaSet per version of the Pod template.
- Changing the template, for example the image, starts a rollout and a new revision. Scaling does not.
- `maxSurge` is how many extra Pods are allowed, and `maxUnavailable` how many may be missing. `Recreate` stops all old Pods first.
- `rollout status` waits, `rollout history` lists revisions, and `rollout undo` goes back one, or to `--to-revision=N`.
- A stuck rollout is never undone for you. Read the new Pods' events, then fix or undo.

**📖 Official documentation:**

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) *(search: "deployment rolling update")*
- [kubectl rollout](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/) *(search: "kubectl rollout")*
- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/quick-reference/) *(search: "cheat sheet")*

---

### 🎯 Task: Create a Deployment with a zero-downtime strategy

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

In namespace `wl-rollout` create a Deployment named `api` with 3 replicas using image `nginx:1.27`. The Deployment must use a `RollingUpdate` strategy that never reduces capacity below 3 Pods and adds at most one extra Pod during an update. Keep no more than 5 old ReplicaSets.

<details>
<summary>💡 Hints</summary>

- Generate the YAML with `--dry-run=client -o yaml`. Then add `strategy` and `revisionHistoryLimit` beside `replicas`.
- "Never below 3" means `maxUnavailable: 0`. "At most one extra" means `maxSurge: 1`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-rollout create deployment api --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > /tmp/cka/api.yaml
cat > /tmp/cka/api.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: wl-rollout
  labels:
    app: api
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
YAML
kubectl apply -f /tmp/cka/api.yaml
kubectl -n wl-rollout rollout status deploy/api --timeout=120s
```

**Explanation:**

- `create deployment api` — Generates the skeleton into a file. In the exam you would open it in vim and add the strategy lines; the next command stands in for that edit.
- `cat > /tmp/cka/api.yaml <<'YAML'` — Overwrites the file with the finished version, written as a heredoc up to the line `YAML`. A single `>` replaces the file's contents.
- `revisionHistoryLimit: 5` — "Keep no more than 5 old ReplicaSets" in the question maps to this field.
- `maxSurge: 1` — "Adds at most one extra Pod during an update."
- `maxUnavailable: 0` — "Never reduces capacity below 3": no Pod may be missing while new ones roll in.
- `matchLabels:` — Must equal the template labels further down; kubectl create generated both as `app: api`.
- `kubectl apply -f` — Creates the Deployment. The namespace comes from `metadata.namespace` in the file, so no `-n` is needed.
- `rollout status` — Waits until all 3 replicas are available, which the grader checks too.

**Notes:** On the exam, open the generated file in vim and add the `strategy` and `revisionHistoryLimit` lines by hand. Already applied the Deployment without them? `kubectl edit deploy api -n wl-rollout` works too. Strategy changes do not create a new revision.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-rollout
d="kubectl -n $ns get deploy api -o jsonpath"

kubectl -n $ns get deploy api >/dev/null 2>&1 && p "deployment api exists" || f "deployment api exists"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "3" ] && p "replicas = 3" || f "replicas = 3"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image nginx:1.27" || f "image nginx:1.27"
[ "$($d='{.spec.strategy.type}' 2>/dev/null)" = "RollingUpdate" ] && p "strategy RollingUpdate" || f "strategy RollingUpdate"
[ "$($d='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)" = "1" ] && p "maxSurge = 1" || f "maxSurge = 1"
[ "$($d='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)" = "0" ] && p "maxUnavailable = 0" || f "maxUnavailable = 0"
[ "$($d='{.spec.revisionHistoryLimit}' 2>/dev/null)" = "5" ] && p "revisionHistoryLimit = 5" || f "revisionHistoryLimit = 5"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Recover a stuck rollout and scale

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

The Deployment `web` in namespace `wl-rollout` was updated a few minutes ago and the new Pods are not starting. Roll the Deployment back to the last working version, then scale it to 4 replicas. All 4 Pods must be available when you are done.

<details>
<summary>💡 Hints</summary>

- `kubectl rollout history` shows the revisions. `kubectl rollout undo` goes back one.
- Scaling does not create a revision, so the order of undo and scale does not matter to the grader. Finish with `kubectl rollout status`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-rollout rollout history deploy/web
kubectl -n wl-rollout rollout undo deploy/web
kubectl -n wl-rollout scale deploy/web --replicas=4
kubectl -n wl-rollout rollout status deploy/web --timeout=180s
```

**Explanation:**

- `rollout history` — Look before you act: revision 1 is the working nginx:1.27 and revision 2 the broken upgrade, as the CHANGE-CAUSE column shows.
- `rollout undo` — Goes back one revision, to nginx:1.27. The ReplicaSet with the bad image scales to zero.
- `scale deploy/web` — Sets 4 replicas. Scaling does not create a revision, so doing it after the undo is safe.
- `rollout status` — Waits until all 4 Pods are available, the state the grader reads.

**Notes:** Look at the Pods first with `kubectl get pods -n wl-rollout`. One Pod in `ImagePullBackOff` next to two running ones is the classic stuck rollout. `rollout undo` brings back the previous template as a new revision: here revision 3, with the content of revision 1. If the task had named a revision, you would use `--to-revision=N`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-rollout
d="kubectl -n $ns get deploy web -o jsonpath"

kubectl -n $ns get deploy web >/dev/null 2>&1 && p "deployment web exists" || f "deployment web exists"
[ "$($d='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image rolled back to nginx:1.27" || f "image rolled back to nginx:1.27"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "4" ] && p "replicas = 4" || f "replicas = 4"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "4" ] && p "4 pods available" || f "4 pods available"
[ -z "$(kubectl -n $ns get pods -l app=web --no-headers 2>/dev/null | grep -v Running)" ] && p "no pods stuck" || f "no pods stuck"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
