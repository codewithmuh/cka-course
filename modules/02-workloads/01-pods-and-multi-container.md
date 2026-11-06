# Pods, init containers and sidecars

> **Module 2** · Lesson 2.1 · 35 minutes

How to write a Pod fast, how command and args decide what a container runs, and how init containers and sidecars work beside your app.

## Learning Objectives

- You can make a Pod manifest with kubectl run --dry-run=client, then add command, args, env, ports and restartPolicy to it.
- You can say what a container will run when you set command, args, or both.
- You can build a Pod whose init container prepares a shared volume, and turn a helper container into a native sidecar.
- You can read the logs of, and open a shell in, one chosen container of a Pod.


A **Pod** is the smallest thing Kubernetes runs. It holds one or more containers that share one network address and can share folders. Every Deployment, Job and DaemonSet in this module ends up as Pods, so you need to write one quickly.

Exam tasks rarely want a plain Pod with one container. They want a second container, a setup step, a shared folder or an exact command. The grader then reads each container's name and image, and also *where* it sits in the spec. If the task wanted `initContainers` and you used `containers`, you score zero, even if the Pod runs.

## Start from kubectl run, never from a blank file

Typing YAML from memory is slow and easy to get wrong. Let `kubectl run` write the first version for you, then edit it.

**kubectl run patterns worth memorizing**

```bash
# A manifest to edit, not a running Pod
kubectl run web --image=nginx:1.27 --port=80 --labels=app=web,tier=front --env=MODE=production --dry-run=client -o yaml > web.yaml

# A one-shot Pod that is not restarted when its command exits
kubectl run once --image=busybox:1.36 --restart=Never -- sh -c 'echo hello; sleep 5'

# Everything after -- becomes args ...
kubectl run box1 --image=busybox:1.36 -- sleep 3600
# ... unless you add --command, then it becomes command
kubectl run box2 --image=busybox:1.36 --command -- sleep 3600
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl run web` — Builds a Pod manifest with a container port, two labels and an environment variable, and saves it to `web.yaml`. `--dry-run=client -o yaml` means nothing is created: you edit the file, then run `kubectl apply -f web.yaml`.
- `kubectl run once` — `--restart=Never` sets the Pod's `restartPolicy` to Never. When the command exits, the Pod ends as Completed instead of being restarted. `sh -c '…'` runs the quoted text as a small shell script.
- `kubectl run box1` — Everything after `--` goes to the container. Without `--command` it lands in `args`, so the image's ENTRYPOINT, if it has one, still runs, with `sleep 3600` as its arguments.
- `kubectl run box2` — With `--command` the same words go into `command` and replace the image's ENTRYPOINT. Use it when a task says the container must run something.

</details>

`kubectl run` always makes exactly one Pod. For other objects, use `kubectl create deployment`, `kubectl create job` or `kubectl create cronjob`. It has no `--requests` or `--limits` flag either. You add CPU and memory settings in the YAML, as the [requests and limits lesson](/cka/workloads/resources-limits-quotas) shows.

The generated file is only a start. These are the fields you will most often add by hand:

**The fields you will add by hand**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: wl-pods
  labels:
    app: web
spec:
  restartPolicy: Always          # Always (default) | OnFailure | Never; applies to the whole Pod
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80      # documents the port and lets probes/Services use the name
          name: http
      env:
        - name: MODE
          value: production
    - name: clock
      image: busybox:1.36
      command: ["sh", "-c"]                         # replaces the image ENTRYPOINT
      args: ["while true; do date; sleep 10; done"] # replaces the image CMD
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: v1` — Every manifest starts with `apiVersion` and `kind`: which API version defines the object, and what type of object it is. Core types such as Pods use plain `v1`.
- `labels:` — Labels are key-value tags. Services, Deployments and `-l` filters find Pods through them, so a typo here quietly breaks those links.
- `restartPolicy: Always` — It sits in the Pod `spec`, beside `containers`, which is why it covers every container. A Job's Pods accept only OnFailure or Never.
- `containers:` — A list: each entry that starts with `-` is one container. Containers in the same Pod share its network, so they reach each other on `localhost`.
- `- name: nginx` — Every container needs a name that is unique within the Pod. `kubectl logs -c`, `kubectl exec -c` and the grader all use it.
- `name: http` — A port name (lowercase, at most 15 characters). A Service's `targetPort` or a probe can use it instead of the number.
- `env:` — Environment variables, as a list of `name`/`value` pairs. Values must be strings, so quote numbers: `value: "8080"`.
- `- name: clock` — A second container in the same Pod. It starts alongside nginx, with no fixed order. This is the old way to add a helper; native sidecars come later in this lesson.
- `command: ["sh", "-c"]` — Square brackets are YAML's one-line list form. `sh -c` takes the next argument as a script, and here that argument comes from `args`.
- `args:` — The script itself: a loop that prints the date every 10 seconds. The next section shows how `command` and `args` combine with the image's own defaults.

</details>

## command and args versus ENTRYPOINT and CMD

Every container image has a default program to run. The image's Dockerfile names that program in **ENTRYPOINT** and its default arguments in **CMD**. A Pod can replace either one. The names differ, so keep the pairs apart:

| In the image (Dockerfile) | In the Pod spec | What it holds |
| --- | --- | --- |
| `ENTRYPOINT` | `command` | The program to run |
| `CMD` | `args` | The arguments passed to that program |

So `command` replaces ENTRYPOINT, and `args` replaces CMD. Here is what runs in each case:

| You set | The container runs | Example with nginx:1.27 |
| --- | --- | --- |
| Neither | The image's ENTRYPOINT with the image's CMD | `/docker-entrypoint.sh nginx -g 'daemon off;'` |
| `args` only | The image's ENTRYPOINT with your args | `/docker-entrypoint.sh sleep 3600` |
| `command` only | Your command. The image's CMD is ignored | `sleep 3600` |
| Both | Your command with your args | `sh -c 'nginx -t'` |

- busybox has no ENTRYPOINT, and its CMD is `sh`. That is why `args` alone happens to work with busybox.
- Many app images are different: their ENTRYPOINT is the app itself. Say your Django image has ENTRYPOINT `gunicorn`. With only `args: ["sleep", "3600"]`, the container runs `gunicorn sleep 3600`, which is not what you wanted.
- So when a task says the container must *run* something, set `command`.
- Both fields are lists. To run a shell one-liner, use `["sh", "-c", "…"]`.

## Init containers

An **init container** is a setup step. It runs to the end and exits before your app starts. For example, before nginx starts, an init container can write the web page that nginx will serve.

- Init containers run one at a time, in the order you list them.
- Each one must succeed (exit with code 0) before the next one starts.
- Your app containers start only after the last init container succeeds.
- If one fails, the kubelet retries it according to the Pod's `restartPolicy`. With `Never`, the whole Pod fails instead.

While they run, the STATUS column of `kubectl get pods` shows their progress. `Init:0/2` means none of two has finished yet. `Init:Error` and `Init:CrashLoopBackOff` mean one of them keeps failing.

How does an init container hand its work to the app? Through a shared volume. An `emptyDir` is an empty folder that Kubernetes creates when the Pod starts. Every container in the Pod can mount it, each at its own path, and they all see the same files. It lives as long as the Pod: it survives a container restart, but it is deleted with the Pod.

**An init container prepares a file for nginx**

*The init container runs first and exits. Its file stays in the emptyDir, where nginx finds it and serves it.*

`Init container` — runs first, writes index.html, exits → `emptyDir volume` — a folder the Pod's containers share → `nginx container` — starts next and serves the file

**An init container rendering content into a shared emptyDir**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: site
  namespace: wl-pods
spec:
  initContainers:
    - name: render
      image: busybox:1.36
      command: ["sh", "-c", "echo \"built on $(hostname) at $(date)\" > /data/index.html"]
      volumeMounts:
        - name: html
          mountPath: /data
  containers:
    - name: nginx
      image: nginx:1.27
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
  volumes:
    - name: html
      emptyDir: {}
```

<details>
<summary>Line-by-line explanation</summary>

- `initContainers:` — A list beside `containers`, at the same indent. Each entry runs to the end, one after another, before any app container starts.
- `> /data/index.html` — Writes one line into `index.html` on the shared volume. The shell fills in `$(hostname)` and `$(date)` when the container runs. The escaped quotes keep the text in one piece inside the YAML string.
- `volumeMounts:` — Mounts a volume from the Pod's `volumes` list into this container. `name` must match a volume exactly, and `mountPath` is where it appears inside the container.
- `mountPath: /usr/share/nginx/html` — The same `html` volume, mounted where nginx looks for web pages. Each container can use its own path; the files are the same.
- `volumes:` — Volumes are declared once for the whole Pod, at the same level as `containers`. Each container then picks the ones it wants with `volumeMounts`.
- `emptyDir: {}` — An empty folder, created when the Pod starts and deleted with the Pod. `{}` means no options.

</details>

## Native sidecar containers

A **sidecar** is a helper container that runs next to your app for the app's whole life. Examples are a log shipper, a proxy, or a tool that reloads config files.

The old way was to add the helper as a second entry under `containers`. That causes two problems:

- There is no start order, so the helper may start after your app.
- In a Job, the helper never exits. So the Pod never finishes, and the Job never completes.

A **native sidecar** fixes both. It is an entry under `initContainers` with one extra line: `restartPolicy: Always`. The kubelet then handles it like this:

- It starts the sidecar in init order, but it waits only for the sidecar to start, not to exit.
- It keeps the sidecar running beside your app, and restarts it if it stops.
- It stops the sidecar after your app containers finish.

**The life of a Pod with a native sidecar**

*This matters most in a Job, because a Job's Pod must finish before the Job can complete.*

`1. Sidecar starts` — listed under initContainers → `2. App runs` — the sidecar runs beside it → `3. App exits` — its work is done → `4. Sidecar is stopped` — so the Pod can finish

|  | Init container | Native sidecar | App container |
| --- | --- | --- | --- |
| Where it goes | `initContainers` | `initContainers`, with `restartPolicy: Always` | `containers` |
| When it runs | First, then it exits | Starts first, then runs beside the app | After the init containers finish and the sidecars start |
| Example | Writes `index.html` | Ships the app's logs | nginx, or your Django app |

**A log tailer as a native sidecar**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: wl-pods
spec:
  initContainers:
    - name: log-tail
      image: busybox:1.36
      restartPolicy: Always      # this one line makes it a sidecar
      command: ["sh", "-c", "touch /var/log/app/app.log; tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 2; done"]
      volumeMounts:
        - name: logs
          mountPath: /var/log/app
  volumes:
    - name: logs
      emptyDir: {}
```

<details>
<summary>Line-by-line explanation</summary>

- `initContainers:` — The sidecar is declared under `initContainers`, not `containers`.
- `restartPolicy: Always` — A `restartPolicy` on one container, allowed only on init containers. The kubelet starts this one, does not wait for it to exit, and keeps it running next to the app.
- `tail -F` — `touch` creates the log file if it is missing. `tail -F` then follows it forever, even if the file is replaced. It stands in for a real log shipper.
- `- name: app` — The main container adds the date to the shared log every 2 seconds.
- `emptyDir: {}` — One emptyDir shared by both containers and mounted at the same path in each, so the tailer reads what the app writes.

</details>

Task 2 below puts a sidecar inside a **Job**, an object that runs a Pod until its work is done. Jobs have their own lesson: [DaemonSets, Jobs and CronJobs](/cka/workloads/daemonsets-jobs-cronjobs).

## Working with one container

In a Pod with several containers, kubectl needs to know which one you mean. Give the container's name with `-c`, for example `-c log-tail`.

**Working with one container at a time**

```bash
kubectl -n wl-pods get pod app                      # READY 2/2: the sidecar is counted
kubectl -n wl-pods logs app -c log-tail             # one container
kubectl -n wl-pods exec app -c app -- cat /var/log/app/app.log
kubectl -n wl-pods exec -it app -c app -- sh
kubectl -n wl-pods describe pod app | sed -n '/Init Containers/,/Conditions/p'
```

<details>
<summary>Line-by-line explanation</summary>

- `get pod app` — `-n wl-pods` can come before the verb; kubectl accepts flags anywhere. READY counts ready containers out of all containers, native sidecars included.
- `logs app -c log-tail` — `-c` picks the container. Without it, kubectl picks a default one and prints a note saying which.
- `exec app -c app -- cat` — Runs one command inside the `app` container and prints its output. Everything after `--` is that command.
- `exec -it app` — `-it` gives you an interactive shell inside the container. Type `exit` to leave.
- `sed -n` — `sed -n '/A/,/B/p'` prints only the lines from a match of A to the next match of B. Here that is the Init Containers and Containers parts of describe, with each container's state and restart count.

</details>

Without `-c`, kubectl picks a container for you and prints a *Defaulted container* note. It picks the one named in the Pod annotation `kubectl.kubernetes.io/default-container`, or else the first entry under `containers`. Read that note. It is how people end up reading the wrong container's logs.

More ways to read logs, such as the logs of a container that crashed, are in [Logs, events and container output streams](/cka/troubleshooting/logs-and-output-streams).

> [!IMPORTANT] **What the grader reads**
> For every container, the grader reads its `name` and `image`, and whether it sits under `initContainers` or `containers`. It also checks `restartPolicy: Always` on a sidecar, the volume type, and the Pod's status or READY count. Names are case-sensitive, so copy them from the task. Before you move on, print the names and compare: `kubectl get pod  -o jsonpath='{.spec.initContainers[*].name} | {.spec.containers[*].name}'`.

## 📝 Key Takeaways

- A Pod holds one or more containers that share a network and can share volumes. Start every Pod from `kubectl run … --dry-run=client -o yaml`.
- `command` replaces the image's ENTRYPOINT, and `args` replaces its CMD. To make a container run something, set `command`.
- Init containers run one by one and must exit before the app starts. An `emptyDir` volume passes their work to the app.
- A native sidecar is an init container with `restartPolicy: Always`. It runs beside the app and is stopped when the app is done.
- Use `-c ` to pick the container for `logs` and `exec`.

**📖 Official documentation:**

- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) *(search: "init containers")*
- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) *(search: "sidecar containers")*
- [Define a Command and Arguments for a Container](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/) *(search: "command and arguments")*
- [Communicate Between Containers in the Same Pod Using a Shared Volume](https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/) *(search: "shared volume")*

---

### 🎯 Task: Serve a file prepared by an init container

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

In namespace `wl-pods` create a Pod named `web`. An init container named `prepare` (image `busybox:1.36`) writes the single line `prepared by init` to a file `index.html` on an `emptyDir` volume named `content`. A container named `nginx` (image `nginx:1.27`) mounts the same volume at `/usr/share/nginx/html` and serves that file on port 80.

<details>
<summary>💡 Hints</summary>

- Start with `kubectl run web --image=nginx:1.27 --dry-run=client -o yaml`. Then add `initContainers` and `volumes` at the same indent as `containers`.
- The init container can mount the volume anywhere, for example at `/work`. Its command can be `sh -c "echo 'prepared by init' > /work/index.html"`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: wl-pods
spec:
  initContainers:
    - name: prepare
      image: busybox:1.36
      command: ["sh", "-c", "echo 'prepared by init' > /work/index.html"]
      volumeMounts:
        - name: content
          mountPath: /work
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
      volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
  volumes:
    - name: content
      emptyDir: {}
YAML
kubectl -n wl-pods wait --for=condition=Ready pod/web --timeout=120s
```

**Explanation:**

- `cat <<'YAML' | kubectl apply -f -` — A heredoc fed straight to kubectl: every line up to `YAML` becomes the manifest, and `-f -` reads it from the pipe. Quoting `'YAML'` stops the shell from expanding `$` inside.
- `- name: prepare` — The init container the question names. It must exit 0 before nginx starts.
- `command:` — Writes the required line to `index.html` on the volume, which this container mounts at `/work`. The single quotes keep the phrase together as one argument for `echo`.
- `containerPort: 80` — Records that nginx listens on port 80. Traffic would reach it without this line, but it documents the port the question names.
- `mountPath: /usr/share/nginx/html` — The same `content` volume, mounted where nginx serves files from, so it serves the file the init container wrote.
- `emptyDir: {}` — The `content` volume both mounts refer to, an emptyDir as the question asks.
- `wait --for=condition=Ready` — Ready means the init container finished and nginx started. Waits up to 120 seconds.

**Notes:** On the exam, generate the file first: `kubectl run web -n wl-pods --image=nginx:1.27 --port=80 --dry-run=client -o yaml > web.yaml`. Then add the `initContainers` block, the two `volumeMounts` and the `volumes` list in vim. Check the result with `kubectl exec web -n wl-pods -c nginx -- curl -s localhost`. If the Pod is stuck in `Init:Error`, run `kubectl logs web -n wl-pods -c prepare` to see the shell error. It is usually a quoting mistake.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-pods
g="kubectl -n $ns get pod web -o jsonpath"

kubectl -n $ns get pod web >/dev/null 2>&1 && p "pod web exists" || f "pod web exists"
[ "$($g='{.spec.initContainers[0].name}' 2>/dev/null)" = "prepare" ] && p "init container prepare" || f "init container prepare"
[ "$($g='{.spec.initContainers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "init image busybox:1.36" || f "init image busybox:1.36"
[ "$($g='{.spec.containers[0].name}/{.spec.containers[0].image}' 2>/dev/null)" = "nginx/nginx:1.27" ] && p "container nginx runs nginx:1.27" || f "container nginx runs nginx:1.27"
[ -n "$($g='{.spec.volumes[?(@.name=="content")].emptyDir}' 2>/dev/null)" ] && p "emptyDir volume content" || f "emptyDir volume content"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod Running" || f "pod Running"
kubectl -n $ns exec web -c nginx -- curl -s localhost/ 2>/dev/null | grep -qx "prepared by init" && p "nginx serves the prepared file" || f "nginx serves the prepared file"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Let a Job finish despite its log shipper

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

The Job `report` in namespace `wl-pods` never completes. Its `main` container finishes its work, but the `log-shipper` container keeps the Pod running. Change the Job so that `log-shipper` runs as a native sidecar: it starts before `main`, runs while `main` works, and is stopped automatically when `main` exits. Keep both containers' names, images and commands and the shared volume. The Job must reach the `Complete` condition.

<details>
<summary>💡 Hints</summary>

- You cannot change a Job's Pod template in place. Save the manifest, delete the Job, then create it again.
- Move the `log-shipper` entry from `containers` to `initContainers`. Then add `restartPolicy: Always` to that container.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-pods delete job report --wait=true
cat <<'YAML' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: report
  namespace: wl-pods
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: log-shipper
          image: busybox:1.36
          restartPolicy: Always
          command: ["sh", "-c", "touch /out/report.log; tail -F /out/report.log"]
          volumeMounts:
            - name: out
              mountPath: /out
      containers:
        - name: main
          image: busybox:1.36
          command: ["sh", "-c", "for i in 1 2 3 4 5; do echo report line $i >> /out/report.log; sleep 2; done"]
          volumeMounts:
            - name: out
              mountPath: /out
      volumes:
        - name: out
          emptyDir: {}
YAML
kubectl -n wl-pods wait --for=condition=complete job/report --timeout=120s
```

**Explanation:**

- `delete job report --wait=true` — A Job's Pod template cannot be changed, so delete the Job first. `--wait=true` returns only once it is really gone, so the new one cannot collide with it.
- `cat <<'YAML'` — The corrected Job, sent through a heredoc as before.
- `backoffLimit: 0` — No retries: one failed Pod fails the Job. Kept exactly as in the original.
- `restartPolicy: Never` — The Pod-level policy. A Job's Pod template accepts only Never or OnFailure here.
- `initContainers:` — `log-shipper` moves here from `containers`, with its name, image, command and mount unchanged.
- `restartPolicy: Always` — The line that makes it a native sidecar: it starts before `main`, keeps running beside it, and is stopped after `main` exits, so the Job can complete.
- `containers:` — `main` is now the only regular container, so its exit code alone decides whether the Pod succeeded.
- `wait --for=condition=complete` — Waits for the Job's Complete condition. kubectl matches condition names regardless of case, so lowercase `complete` works.

**Notes:** `kubectl edit job report` is refused, because a Job's `spec.template` cannot be changed. On the exam, save the Job with `kubectl get job report -n wl-pods -o yaml > report.yaml` and move the block. Then delete `spec.selector` from the file, and the `controller-uid` and `batch.kubernetes.io/controller-uid` labels from the template. The API rejects a new Job that carries the old, generated selector. Do this cleanup *before* you run `kubectl replace --force -f report.yaml`. replace deletes the old Job first, and only then finds out the new one is invalid. Expect the Job to complete about 30 seconds after `main` exits. Why the wait? The shipper's process is PID 1 and has no handler for the stop signal (SIGTERM), so it ignores it. The kubelet kills it when the 30-second grace period ends. You can still read the sidecar's logs afterwards with `kubectl logs job/report -n wl-pods -c log-shipper`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-pods
g="kubectl -n $ns get job report -o jsonpath"

kubectl -n $ns get job report >/dev/null 2>&1 && p "job report exists" || f "job report exists"
[ "$($g='{.spec.template.spec.initContainers[?(@.name=="log-shipper")].restartPolicy}' 2>/dev/null)" = "Always" ] && p "log-shipper is an init container with restartPolicy Always" || f "log-shipper is an init container with restartPolicy Always"
[ "$($g='{.spec.template.spec.initContainers[?(@.name=="log-shipper")].image}' 2>/dev/null)" = "busybox:1.36" ] && p "log-shipper image busybox:1.36" || f "log-shipper image busybox:1.36"
[ "$($g='{.spec.template.spec.containers[*].name}' 2>/dev/null)" = "main" ] && p "main is the only regular container" || f "main is the only regular container"
[ "$($g='{.status.succeeded}' 2>/dev/null)" = "1" ] && p "job succeeded" || f "job succeeded"
kubectl -n $ns logs job/report -c log-shipper 2>/dev/null | grep -q "report line 5" && p "sidecar shipped all five lines" || f "sidecar shipped all five lines"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
