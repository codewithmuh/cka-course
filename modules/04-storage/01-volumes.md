# Volumes and volume types

> **Module 4** · Lesson 4.1 · 30 minutes

What a volume is, which volume types to know by heart, and how two containers in one Pod share a folder.

## Learning Objectives

- You can write a Pod with emptyDir, hostPath and projected volumes, and put volumes and volumeMounts in the right place.
- You can share one volume between two containers and prove from inside the Pod that it works.
- You can say why hostPath is risky, where the control plane still uses it, and check its files on the node.


When a container restarts, every file it wrote is lost. A **volume** is a folder that lives outside the container, so its files stay. Containers in the same Pod can also share it.

Storage is 10% of the exam, the smallest part. Volume questions are quick points if you can type the YAML from memory. Typical ones: an `emptyDir` shared by two containers, or a `hostPath` folder on one node. They cost minutes if you have to look up where `volumeMounts` goes.

## Why a container needs a volume

A container keeps its files only while it runs. Say your app saves uploaded photos in `/data`. The container crashes and Kubernetes restarts it. Without a volume, `/data` is empty again.

There is a second problem. Each container in a Pod has its own filesystem, so two containers cannot pass files through a normal folder. A volume solves both problems. It has two parts in the Pod YAML:

- `spec.volumes`: you define the volume once, for the whole Pod. You give it a name and a type.
- `volumeMounts`: each container that wants the volume lists its name and a `mountPath`, the folder where it appears inside that container.

**One volume, mounted by two containers**

*The volume is defined once for the Pod. Each container mounts it by name, at its own path. This is the shape of the first task.*

`writer container` — writes index.html (`mountPath: /out`) → `Volume: content` — defined once in spec.volumes (`emptyDir`) → `web container` — serves the file, read-only (`mountPath: /usr/share/nginx/html`)

Whether the data also outlives the *Pod* depends on the volume type:

| Volume type | Where the data lives | How long it lasts | Typical use |
| --- | --- | --- | --- |
| emptyDir | On the node's disk, or in RAM | Until the Pod is deleted. It survives container restarts. | Scratch files, a cache, files shared between containers |
| configMap, secret, projected | In API objects. The kubelet copies them into files. | As long as the ConfigMap or Secret exists | Config files, certificates |
| hostPath | In a folder on one node | Until someone removes it from that node | Control plane static Pods, node agents |
| persistentVolumeClaim | In a PersistentVolume (next lesson) | Longer than the Pod | Databases, anything that must outlive the Pod |

## emptyDir

An `emptyDir` is an empty folder. The kubelet creates it when the Pod starts on a node, and deletes it when the Pod is removed. It survives container restarts, but not Pod deletion. Example: a web app that renders thumbnails into a scratch folder.

- `emptyDir: {}` is the whole definition for the plain case. The folder is on the node's disk.
- `sizeLimit` caps the size. If the volume grows past it, the kubelet evicts the Pod.
- `medium: Memory` keeps the files in RAM. It is faster, but the files count as the container's memory use.

**Two emptyDir volumes: one on disk with a cap, one in memory**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: scratch
  namespace: st-vol
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: scratch
          mountPath: /scratch
        - name: fast
          mountPath: /fast
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 256Mi
    - name: fast
      emptyDir:
        medium: Memory
        sizeLimit: 64Mi
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: v1` — Every manifest starts with `apiVersion` and `kind`: which API the object belongs to and what type it is. Pods are in the core API, written simply as `v1`.
- `namespace: st-vol` — The namespace the Pod is created in. With it in the file, you do not need `-n st-vol` when you apply.
- `command: [` — Replaces the image's default command. `sleep 3600` keeps the container running for an hour, so you have time to `kubectl exec` in and look at the mounts.
- `volumeMounts:` — Belongs to the container: where each volume appears inside *this* container's filesystem. Each entry is a volume name plus a `mountPath`.
- `- name: scratch` — Must equal a name under `spec.volumes` further down. The name is the only link between the two lists; a mount that names a missing volume is rejected when you apply.
- `mountPath: /fast` — The second volume shows up at `/fast`. One container can mount as many volumes as it needs, each at its own path.
- `volumes:` — Declared once for the whole Pod, at the same indentation as `containers`, not inside it. A volume listed here but mounted nowhere is never seen by any container.
- `emptyDir:` — An empty directory the kubelet creates on the node when the Pod starts there and deletes when the Pod is removed. It survives container restarts, not Pod deletion.
- `sizeLimit: 256Mi` — Caps the volume at 256 MiB (`Mi` means mebibytes, counted in powers of 1024). If the kubelet finds it larger, it evicts the Pod.
- `medium: Memory` — Backs the volume with RAM (a tmpfs) instead of disk: faster, but lost on a node reboot, and what you write counts against the container's memory limit.

</details>

## hostPath

A `hostPath` volume mounts a folder (or a file) from the node into the container. The files live on the node's own disk. The optional `type` says what the kubelet checks before it mounts the path:

| type | What the kubelet does |
| --- | --- |
| (not set) | No check. It mounts whatever is at the path. |
| `DirectoryOrCreate` | Creates the folder if it is missing. The usual choice for a folder your Pod writes to. |
| `Directory` | The folder must already exist. If it does not, the Pod is stuck in `ContainerCreating`. |

A few more types check for a file or a socket instead. You rarely need them.

hostPath data is *node-local*: it exists only on the node that wrote it. Say your Pod writes logs to `/opt/logs` on `cka-worker`. Tomorrow it starts on `cka-worker2` and finds an empty folder. So pin such a Pod to one node, with `nodeName` or a `nodeSelector`.

To check the files, open a shell on that node. On the lab that is `docker exec cka-worker ls /opt/node-writer`. On the exam it is `ssh cka-worker`, then the same `ls`.

**A Pod pinned to cka-worker that writes into a node directory**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-writer
  namespace: st-vol
spec:
  nodeName: cka-worker
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "date > /data/started; sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      hostPath:
        path: /opt/node-writer
        type: DirectoryOrCreate
```

<details>
<summary>Line-by-line explanation</summary>

- `nodeName: cka-worker` — Puts the Pod straight on `cka-worker`, skipping the scheduler. hostPath data lives on one node, so pinning the Pod is how it sees the same directory every time.
- `date > /data/started` — Writes the current date into `/data/started`, then sleeps so the container stays up. The file lands on the node, because `/data` is the mounted node directory.
- `mountPath: /data` — Inside the container, `/data` *is* the node's `/opt/node-writer`: the same files, seen from two places.
- `hostPath:` — Mounts a path from the node's own filesystem. Powerful and risky: a Pod that mounts the wrong path can read or change the node itself.
- `path: /opt/node-writer` — A path on the node, not in the image. Check it from a node shell: `docker exec cka-worker ls /opt/node-writer` on the lab, after `ssh cka-worker` on the exam.
- `type: DirectoryOrCreate` — Creates the directory if it does not exist yet. With `Directory` instead, a missing path leaves the Pod stuck in ContainerCreating with a mount error.

</details>

> [!WARNING] **hostPath is powerful and risky**
> A Pod that mounts `/` or `/etc` from the node can read the node's secrets or change the node itself. That is why the `baseline` and `restricted` Pod Security levels forbid hostPath (see [Pod admission](/cka/workloads/pod-admission-and-priority)). It is still the right tool for the control plane. The [static Pods](/cka/architecture/control-plane-and-nodes) of etcd and the API server use it to reach their certificates in `/etc/kubernetes/pki`. etcd also keeps its data in `/var/lib/etcd` that way.

## Volumes made from ConfigMaps and Secrets

A `configMap` or `secret` volume turns each key of that object into a file. Both are taught in [ConfigMaps and Secrets](/cka/workloads/configmaps-and-secrets).

A `projected` volume puts several sources into one folder. Example: your app wants its config file and its TLS certificate side by side in `/etc/app`. One projected volume gives it both:

**The volumes block of a Pod with a projected volume**

```yaml
volumes:
  - name: bundle
    projected:
      sources:
        - configMap:
            name: app-settings
        - secret:
            name: app-tls
```

<details>
<summary>Line-by-line explanation</summary>

- `volumes:` — Only the Pod-level list is shown here. A container still needs a `volumeMounts` entry for `bundle`, for example at `/etc/app`, before any file appears.
- `projected:` — Merges several sources into one folder, so a single mount gives the container the files from both the ConfigMap and the Secret.
- `name: app-settings` — The ConfigMap to read. It must exist in the Pod's namespace, or the Pod waits in `ContainerCreating`.
- `name: app-tls` — Inside `projected`, a secret source uses `name`. A plain `secret` volume uses `secretName` instead. Mixing them up is a common apply error.

</details>

## volumeMounts and sharing a volume

Four rules decide what a container sees:

- Each mount names a volume from `spec.volumes` and gives a `mountPath`: the folder inside the container.
- A mount hides whatever the image had at that path. In the first task, the volume hides nginx's default page in `/usr/share/nginx/html`. To add one file without hiding the folder, use `subPath`, shown in [ConfigMaps and Secrets](/cka/workloads/configmaps-and-secrets).
- `readOnly: true` goes on the mount, not on the volume. So one container can write while another only reads.
- Two containers share a volume when both mount the same name. Each one can use its own `mountPath`.

Containers in a Pod also share one network. So in the first task, the writer container can test nginx at `http://localhost/`. A helper container that works next to the main one is called a sidecar: see [Pods, init containers and sidecars](/cka/workloads/pods-and-multi-container).

> [!IMPORTANT] **What the grader reads**
> The grader reads the live Pod, not what you typed. It checks `spec.volumes` (type and fields) and each container's `volumeMounts` (name, mountPath, readOnly). For hostPath it also reads the file on the node. Two traps cost points: a volume that one container forgets to mount, and `volumes:` indented under `containers:` instead of beside it. Check both lists with `kubectl get pod  -o yaml`.

## 📝 Key Takeaways

- A container loses its files when it restarts. A volume keeps them, and lets the containers in one Pod share them.
- Define a volume once in `spec.volumes`. Mount it in each container with `volumeMounts`, using the same name.
- `emptyDir` lasts as long as the Pod. `hostPath` is a folder on one node, so pin the Pod to that node.
- `readOnly: true` goes on the mount, not on the volume.
- Check hostPath files from the node: `docker exec` on the lab, `ssh` on the exam.

**📖 Official documentation:**

- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/) *(search: "volumes")*
- [Projected Volumes](https://kubernetes.io/docs/concepts/storage/projected-volumes/) *(search: "projected volumes")*
- [Configure a Pod to Use a Volume for Storage](https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/) *(search: "configure volume storage")*
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) *(search: "pod security standards")*

---

### 🎯 Task: Two containers sharing an emptyDir

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 4% |
| **Time** | 7 min |

**Question:**

In namespace `st-vol` create a Pod named `shared-web` with two containers that share an `emptyDir` volume named `content` limited to `64Mi`. Container `writer` uses image `busybox:1.36`, mounts the volume at `/out` and runs `sh -c 'echo hello from writer > /out/index.html; while true; do sleep 3600; done'`. Container `web` uses image `nginx:1.27` and mounts the same volume read-only at `/usr/share/nginx/html`. When the Pod is running, a request to `http://localhost/` from inside the `writer` container must return the line that `writer` wrote.

<details>
<summary>💡 Hints</summary>

- Define one volume in `spec.volumes`. Mount it in both containers by its name, at a different `mountPath` in each.
- `sizeLimit` goes under `emptyDir`. `readOnly` goes on the mount, not on the volume.
- Test it with `kubectl -n st-vol exec shared-web -c writer -- wget -qO- http://localhost/`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/shared-web.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: shared-web
  namespace: st-vol
spec:
  volumes:
    - name: content
      emptyDir:
        sizeLimit: 64Mi
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo hello from writer > /out/index.html; while true; do sleep 3600; done"]
      volumeMounts:
        - name: content
          mountPath: /out
    - name: web
      image: nginx:1.27
      volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
          readOnly: true
YAML
kubectl apply -f /tmp/cka/shared-web.yaml
kubectl -n st-vol wait --for=condition=Ready pod/shared-web --timeout=120s
kubectl -n st-vol exec shared-web -c writer -- wget -qO- http://localhost/
```

**Explanation:**

- `mkdir -p /tmp/cka` — Makes sure the course's answers folder exists; `-p` means no error if it is already there.
- `cat > /tmp/cka/shared-web.yaml <<'YAML'` — Writes everything up to the line `YAML` into the file. The quotes around `'YAML'` stop the shell from expanding anything like `$VAR` inside, so the manifest is saved exactly as typed.
- `volumes:` — One volume for the whole Pod. Listing it before `containers` is fine; the order of keys in YAML does not matter.
- `sizeLimit: 64Mi` — The 64Mi cap the question asks for. It sits under `emptyDir` because it belongs to the volume, not to a mount.
- `while true; do sleep 3600; done` — Writes the page once, then loops forever so the container keeps running. If the command exited, the container would be restarted again and again (`CrashLoopBackOff`).
- `mountPath: /out` — The writer sees the shared volume at `/out`, so its `index.html` lands in the volume.
- `mountPath: /usr/share/nginx/html` — The same volume, mounted where nginx looks for web pages. It hides the image's own default page, so nginx now serves the writer's file.
- `readOnly: true` — Set on this one mount, not on the volume: `web` can only read, while `writer` still writes. The question asks for it, and the grader checks it.
- `YAML` — Ends the file. The closing word must match the opening `'YAML'` and stand alone on its line.
- `kubectl apply -f` — Creates the Pod from the file.
- `wait --for=condition=Ready` — Waits until the Pod is Ready, which for a two-container Pod means both containers are up, or gives up after 120 seconds.
- `exec shared-web -c writer` — Runs `wget` inside the `writer` container: `-c` picks the container and `--` ends kubectl's own flags. `-qO-` prints the page instead of saving it. `localhost` reaches nginx because containers in a Pod share one network.

**Notes:** Start with `kubectl run shared-web --image=busybox:1.36 -n st-vol --dry-run=client -o yaml -- sh -c '…' > shared-web.yaml`. Then add the second container and the volume in vim, because `kubectl run` only makes one container. Both containers must be `Running`. If `writer` is in `CrashLoopBackOff`, its command is wrong. The shared folder then stays empty, and nginx answers 403. The read-only mount on `web` is part of the question. Forget it and the grader notices.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-vol
g="kubectl -n $ns get pod shared-web -o jsonpath"

kubectl -n $ns get pod shared-web >/dev/null 2>&1 && p "pod shared-web exists" || f "pod shared-web exists"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod is Running" || f "pod is Running"
[ "$($g='{.spec.containers[?(@.name=="writer")].image}' 2>/dev/null)" = "busybox:1.36" ] && p "container writer uses busybox:1.36" || f "container writer uses busybox:1.36"
[ "$($g='{.spec.containers[?(@.name=="web")].image}' 2>/dev/null)" = "nginx:1.27" ] && p "container web uses nginx:1.27" || f "container web uses nginx:1.27"
[ -n "$($g='{.spec.volumes[?(@.name=="content")].emptyDir}' 2>/dev/null)" ] && p "volume content is an emptyDir" || f "volume content is an emptyDir"
[ "$($g='{.spec.volumes[?(@.name=="content")].emptyDir.sizeLimit}' 2>/dev/null)" = "64Mi" ] && p "sizeLimit 64Mi" || f "sizeLimit 64Mi"
[ "$($g='{.spec.containers[?(@.name=="writer")].volumeMounts[?(@.name=="content")].mountPath}' 2>/dev/null)" = "/out" ] && p "writer mounts content at /out" || f "writer mounts content at /out"
[ "$($g='{.spec.containers[?(@.name=="web")].volumeMounts[?(@.name=="content")].mountPath}' 2>/dev/null)" = "/usr/share/nginx/html" ] && p "web mounts content at /usr/share/nginx/html" || f "web mounts content at /usr/share/nginx/html"
[ "$($g='{.spec.containers[?(@.name=="web")].volumeMounts[?(@.name=="content")].readOnly}' 2>/dev/null)" = "true" ] && p "web mount is read-only" || f "web mount is read-only"
kubectl -n $ns exec shared-web -c writer -- wget -qO- http://localhost/ 2>/dev/null | grep -q "hello from writer" && p "nginx serves the file writer wrote" || f "nginx serves the file writer wrote"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A hostPath volume on a specific node

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Create a Pod named `node-logger` in namespace `st-vol` that runs on node `cka-worker`. Mount the node directory `/opt/st-logs` into the container at `/host-logs` through a `hostPath` volume named `logs`; the directory must be created on the node if it does not exist yet. The container uses image `busybox:1.36` and runs `sh -c 'echo node-logger was here > /host-logs/marker.txt; while true; do sleep 3600; done'`. When you are done, `/opt/st-logs/marker.txt` must exist on `cka-worker`.

<details>
<summary>💡 Hints</summary>

- `nodeName: cka-worker` under `spec` pins the Pod without the scheduler. A `nodeSelector` on `kubernetes.io/hostname` works too.
- "Created if it does not exist" means hostPath type `DirectoryOrCreate`.
- Check from the node with `docker exec cka-worker cat /opt/st-logs/marker.txt`. On the exam, `ssh cka-worker` first.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/node-logger.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: node-logger
  namespace: st-vol
spec:
  nodeName: cka-worker
  volumes:
    - name: logs
      hostPath:
        path: /opt/st-logs
        type: DirectoryOrCreate
  containers:
    - name: logger
      image: busybox:1.36
      command: ["sh", "-c", "echo node-logger was here > /host-logs/marker.txt; while true; do sleep 3600; done"]
      volumeMounts:
        - name: logs
          mountPath: /host-logs
YAML
kubectl apply -f /tmp/cka/node-logger.yaml
kubectl -n st-vol wait --for=condition=Ready pod/node-logger --timeout=120s
docker exec cka-worker cat /opt/st-logs/marker.txt
```

**Explanation:**

- `cat > /tmp/cka/node-logger.yaml` — Saves the manifest with a heredoc, as in the previous task, so you can fix it and re-apply later.
- `nodeName: cka-worker` — Pins the Pod to `cka-worker`; the scheduler is skipped. The node matters because the marker file has to end up on that node's disk.
- `path: /opt/st-logs` — The directory on the node. The container sees it as `/host-logs`, through the mount further down.
- `type: DirectoryOrCreate` — "Created if it does not exist" in the question translates to this type. The kubelet makes `/opt/st-logs` on the node before the container starts.
- `> /host-logs/marker.txt` — Writes the marker through the mount, so it lands in `/opt/st-logs` on the node, then keeps the container alive.
- `wait --for=condition=Ready pod/node-logger` — Waits until the container is running, so the marker file has been written.
- `docker exec cka-worker cat` — Reads the file on the node itself. On the lab the node is a Docker container, hence `docker exec`; on the exam you `ssh cka-worker` and run the same `cat`.

**Notes:** `kubectl run node-logger --image=busybox:1.36 -n st-vol --dry-run=client -o yaml -- sh -c '…'` gives you the skeleton. Add `nodeName`, the volume and the mount. If the Pod sits in `Pending` and then disappears, the node name is misspelled. No kubelet picks the Pod up, and Kubernetes deletes Pods bound to a node that does not exist. On the exam, check the file after `ssh cka-worker`. On the lab the node is a container, so use `docker exec`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=st-vol
g="kubectl -n $ns get pod node-logger -o jsonpath"

kubectl -n $ns get pod node-logger >/dev/null 2>&1 && p "pod node-logger exists" || f "pod node-logger exists"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod is Running" || f "pod is Running"
[ "$($g='{.spec.nodeName}' 2>/dev/null)" = "cka-worker" ] && p "runs on cka-worker" || f "runs on cka-worker"
[ "$($g='{.spec.volumes[?(@.name=="logs")].hostPath.path}' 2>/dev/null)" = "/opt/st-logs" ] && p "hostPath volume logs -> /opt/st-logs" || f "hostPath volume logs -> /opt/st-logs"
[ "$($g='{.spec.volumes[?(@.name=="logs")].hostPath.type}' 2>/dev/null)" = "DirectoryOrCreate" ] && p "type DirectoryOrCreate" || f "type DirectoryOrCreate"
[ "$($g='{.spec.containers[0].volumeMounts[?(@.name=="logs")].mountPath}' 2>/dev/null)" = "/host-logs" ] && p "mounted at /host-logs" || f "mounted at /host-logs"
docker exec cka-worker cat /opt/st-logs/marker.txt 2>/dev/null | grep -q "node-logger was here" && p "marker.txt exists on cka-worker" || f "marker.txt exists on cka-worker"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 4: Storage*
