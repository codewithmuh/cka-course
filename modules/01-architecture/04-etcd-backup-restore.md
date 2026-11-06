# etcd backup and restore

> **Module 1** · Lesson 1.4 · 40 minutes

Back up etcd with etcdctl, check the snapshot with etcdutl, then restore it into a new folder and point etcd at it.

## Learning Objectives

- You can read etcd's address and certificate paths from its static Pod file and pass them to etcdctl.
- You can save a snapshot and check it with etcdutl snapshot status.
- You can restore a snapshot into a new data directory, switch the etcd static Pod to it and confirm the cluster serves the restored state.


etcd is the cluster's database. It stores every object: every Pod, Deployment and Secret. A **snapshot** is a copy of that whole database in one file, so it is your backup of the cluster. Example: someone deletes a ConfigMap by mistake. If you took a snapshot this morning, you can restore it. The ConfigMap is back, and so is everything else, exactly as it was this morning.

Expect an etcd question on the CKA. It is good value, because the steps never change. It belongs to the exam topic **Manage the lifecycle of Kubernetes clusters**. On the exam the etcd tools are already installed on the control plane node, and you reach it with `ssh`.

**Backup and restore**

*Save copies the live database into one file. Restore unpacks that file into a new folder. Then you point etcd at the new folder.*

`etcd` — the live database (`/var/lib/etcd`) → `Snapshot file` — etcdctl snapshot save (`/opt/cka/etcd-snapshot.db`) → `New data folder` — etcdutl snapshot restore (`/var/lib/etcd-from-backup`) → `etcd again` — etcd.yaml now points at the new folder

## etcd, etcdctl and etcdutl

Three names that look alike. One is the database, and two are tools that work on it:

| Name | What it is | What it needs | Example |
| --- | --- | --- | --- |
| **etcd** | The database itself. On kubeadm clusters it runs as a static Pod on the control plane. | Its data folder, `/var/lib/etcd` | `/etc/kubernetes/manifests/etcd.yaml` |
| **etcdctl** | A client that talks to a running etcd over the network. | etcd's address and certificates | `etcdctl snapshot save` |
| **etcdutl** | A tool that works on etcd's files directly, even when etcd is not running. | Only the file's path | `etcdutl snapshot status`, `etcdutl snapshot restore` |

## Where etcdctl's flags come from

etcdctl needs four things to reach etcd: its address and three certificate files. Never type them from memory. Copy them from etcd's static Pod file:

**Read them from the manifest; do not type them from memory**

```bash
# exam: ssh <control-plane>; sudo -i      lab: docker exec -it cka-control-plane bash
grep -E -- '--(listen-client-urls|trusted-ca-file|cert-file|key-file)=' /etc/kubernetes/manifests/etcd.yaml
#     - --cert-file=/etc/kubernetes/pki/etcd/server.crt
#     - --key-file=/etc/kubernetes/pki/etcd/server.key
#     - --listen-client-urls=https://127.0.0.1:2379,https://<node-ip>:2379
#     - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
```

<details>
<summary>Line-by-line explanation</summary>

- `grep -E -- '--(listen-client-urls` — Prints the four etcd flags etcdctl needs, straight from the static Pod manifest. With `-E`, `(a|b|c)` matches any one of the names, and `--` stops grep from reading the pattern as one of its own options.
- `--listen-client-urls=https://127.0.0.1:2379` — etcd listens on localhost and on the node IP. On this node either URL works as etcdctl's `--endpoints`; the table below maps the other three flags.

</details>

| In etcd.yaml | Pass to etcdctl as | Value on this lab |
| --- | --- | --- |
| `--listen-client-urls` (either URL) | `--endpoints` | `https://127.0.0.1:2379` |
| `--trusted-ca-file` | `--cacert` | `/etc/kubernetes/pki/etcd/ca.crt` |
| `--cert-file` | `--cert` | `/etc/kubernetes/pki/etcd/server.crt` |
| `--key-file` | `--key` | `/etc/kubernetes/pki/etcd/server.key` |

The certificate pair is etcd's own server certificate. kubeadm makes it valid for clients too, so etcdctl can log in to etcd with it.

## Take and check a snapshot

> [!TIP] **On the kind lab**
> kind keeps etcdctl and etcdutl inside the etcd container only. Each task's setup copies them onto the node for you, so you can then work exactly as on the exam. To try the commands before a task, copy them yourself with the block below.

**Lab only: copy etcdctl and etcdutl onto the kind node**

```bash
# Copy the tools out of the running etcd container (/proc/<pid>/root is its filesystem)
docker exec cka-control-plane sh -c 'cp /proc/$(pgrep -xo etcd)/root/usr/local/bin/etcdctl /proc/$(pgrep -xo etcd)/root/usr/local/bin/etcdutl /usr/local/bin/'
docker exec cka-control-plane etcdctl version
```

<details>
<summary>Line-by-line explanation</summary>

- `pgrep -xo etcd` — `pgrep -xo etcd` finds the oldest process named exactly `etcd`. Its `/proc//root` is that container's filesystem as seen from the node, so this copies both tools to `/usr/local/bin` on the node.
- `etcdctl version` — Proves etcdctl now runs on the node itself, and shows which etcd version you are working with.

</details>

Now save the snapshot, then check that the file is valid. Run these on the control plane node, as root:

**On the control plane node, as root**

```bash
mkdir -p /opt/cka
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/cka/etcd-snapshot.db
# Snapshot saved at /opt/cka/etcd-snapshot.db

etcdutl snapshot status /opt/cka/etcd-snapshot.db -w table
# +----------+----------+------------+------------+---------+
# |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
# +----------+----------+------------+------------+---------+
# | 9a1eac1d |     9745 |       1010 |      15 MB |   3.6.0 |
# +----------+----------+------------+------------+---------+
```

<details>
<summary>Line-by-line explanation</summary>

- `mkdir -p /opt/cka` — Creates the folder for the snapshot first; saving into a folder that does not exist fails.
- `ETCDCTL_API=3 etcdctl` — etcdctl is the client that talks to a running etcd over the network. `ETCDCTL_API=3` selects the v3 API, the default for years, so it is harmless. Each `\` continues the command.
- `--endpoints=https://127.0.0.1:2379` — Where etcd listens, from `--listen-client-urls`. It must be `https`: kubeadm's etcd only accepts TLS connections.
- `--cacert=` — The CA that signed etcd's serving certificate, so etcdctl can trust the server. In the manifest it is `--trusted-ca-file`.
- `--cert=` — The certificate, and on the next line the key, that etcdctl uses to prove who it is. etcd demands a client certificate, and kubeadm's server pair also works as one.
- `snapshot save /opt/cka/etcd-snapshot.db` — The command itself: copy etcd's entire database into this one file.
- `etcdutl snapshot status` — `etcdutl` works on files, so it needs no endpoint or certificates. `status` prints the snapshot's hash, revision, key count and size; `-w table` formats it as a table.

</details>

## Restore into a new data directory

Restoring takes three moves. Unpack the snapshot into a **new** folder. Point etcd at that folder. Wait for the control plane to come back. Stop the API server during the switch, so nothing writes to etcd half way.

Step 2 below parks the API server's file in `/etc/kubernetes`, outside the manifests folder. Never park it, or any backup, inside that folder: the kubelet runs every file there (see [Control plane and node components](/cka/architecture/control-plane-and-nodes)).

**Restore, then point the etcd static Pod at the result**

```bash
# 1. Restore into a NEW directory. etcdutl refuses one that is not empty.
etcdutl snapshot restore /opt/cka/etcd-snapshot.db --data-dir /var/lib/etcd-from-backup

# 2. Stop the API server while etcd switches data (the docs recommend it)
mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/

# 3. Change the etcd-data hostPath, and nothing else
vim /etc/kubernetes/manifests/etcd.yaml
#   volumes:
#   - hostPath:
#       path: /var/lib/etcd-from-backup      # was /var/lib/etcd
#       type: DirectoryOrCreate
#     name: etcd-data

# 4. Wait for the kubelet to recreate etcd (up to a minute), then start the API server again
crictl ps --name etcd
mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/

# 5. Check from wherever kubectl works
kubectl get nodes
kubectl get pods -A
```

<details>
<summary>Line-by-line explanation</summary>

- `etcdutl snapshot restore` — Unpacks the snapshot into a brand-new etcd data directory. Nothing running is touched yet: the live data in `/var/lib/etcd` stays as it is.
- `mv /etc/kubernetes/manifests/kube-apiserver.yaml` — Moving a static Pod's file out of the manifests folder makes the kubelet stop that Pod. With the API server down, nothing writes to etcd during the switch.
- `vim /etc/kubernetes/manifests/etcd.yaml` — Edit the etcd manifest. When you save, the kubelet sees the change and recreates the etcd Pod from it.
- `path: /var/lib/etcd-from-backup` — The one change: which host directory is mounted into the etcd container. Inside, etcd still uses `/var/lib/etcd`, but it now finds the restored data there.
- `crictl ps --name etcd` — `crictl` asks the container runtime directly, so it works while the API server is down. Repeat it until etcd is Running with a fresh CREATED time.
- `mv /etc/kubernetes/kube-apiserver.yaml` — Putting the file back makes the kubelet start the API server again, now reading the restored etcd.
- `kubectl get nodes` — When kubectl answers, the API server is back. A minute of *connection refused* before that is normal.
- `kubectl get pods -A` — The cluster now shows its objects as they were when the snapshot was taken.

</details>

**Which line to change in etcd.yaml**

*Only the hostPath changes. etcd still reads /var/lib/etcd inside its container, but now finds the restored data there.*

`Folder on the node` — the hostPath: change this (`/var/lib/etcd-from-backup`) → `Folder in the container` — the mountPath: leave it (`/var/lib/etcd`) → `etcd` — the flag: leave it (`--data-dir=/var/lib/etcd`)

Be careful with the `--data-dir` flag. If you change only the flag, etcd starts on an empty folder inside the container, and you get a brand-new, empty cluster. Changing the flag, the `mountPath` and the hostPath together also works, as long as all three agree. Changing only the hostPath is the simplest.

> [!IMPORTANT] **What gets checked, and where people lose the points**
> For a backup, the grader looks for the snapshot file at the exact path and may run `snapshot status` on it. For a restore, it checks that the cluster serves the restored objects. Points go missing on: running etcdctl without `sudo`, so it cannot read the key; a typo in a certificate path (copy them from the manifest); restoring over the live `/var/lib/etcd`; and checking too early.

## 📝 Key Takeaways

- etcd is the database. etcdctl talks to the running etcd and needs its address and certificates. etcdutl works on files and needs neither.
- Copy etcd's address and the three certificate paths from `/etc/kubernetes/manifests/etcd.yaml`. Never type them from memory.
- Backup: `etcdctl … snapshot save `, then `etcdutl snapshot status ` to check it.
- Restore: `etcdutl snapshot restore` into a new folder, then change only the etcd-data hostPath in `etcd.yaml`.
- After the switch, wait up to a minute and watch `crictl ps` on the node before you test with kubectl.

**📖 Official documentation:**

- [Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) *(search: "etcd backup restore")*
- [PKI certificates and requirements](https://kubernetes.io/docs/setup/best-practices/certificates/) *(search: "pki certificates")*
- [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) *(search: "static pod")*

---

### 🎯 Task: Back up etcd and record the snapshot revision

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

On the control plane node `cka-control-plane`, take a snapshot of the cluster's etcd and save it on that node as `/opt/cka/etcd-snapshot.db`. Connect with the endpoint and TLS files the etcd static Pod is configured with. Then read the snapshot's revision with `etcdutl` and write only that number to `/tmp/cka/ar-etcd-revision.txt` on your workstation.

<details>
<summary>💡 Hints</summary>

- grep the etcd manifest for listen-client-urls, trusted-ca-file, cert-file and key-file. They become --endpoints, --cacert, --cert and --key.
- etcdutl snapshot status prints a table with -w table, or JSON with -w json.

</details>

<details>
<summary>✅ Solution</summary>

```bash
docker exec cka-control-plane grep -E -- '--(listen-client-urls|trusted-ca-file|cert-file|key-file)=' /etc/kubernetes/manifests/etcd.yaml
docker exec cka-control-plane etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /opt/cka/etcd-snapshot.db
docker exec cka-control-plane etcdutl snapshot status /opt/cka/etcd-snapshot.db -w table
mkdir -p /tmp/cka
docker exec cka-control-plane etcdutl snapshot status /opt/cka/etcd-snapshot.db -w json | grep -o '"revision":[0-9]*' | cut -d: -f2 > /tmp/cka/ar-etcd-revision.txt
cat /tmp/cka/ar-etcd-revision.txt
```

**Explanation:**

- `docker exec cka-control-plane grep -E` — Reads the endpoint and the three TLS file paths from etcd's manifest, so you copy them rather than type them from memory.
- `snapshot save /opt/cka/etcd-snapshot.db` — Takes the snapshot on the node with those four values and saves it at the exact path the task names.
- `-w table` — A quick look at the snapshot as a table: if `etcdutl` can read it, the file is valid.
- `mkdir -p /tmp/cka` — Creates the answers folder on your workstation.
- `-w json | grep -o` — The same details as JSON. `grep -o` keeps only the text `"revision":`, and `cut -d: -f2` keeps the number after the colon for the answer file.
- `cat /tmp/cka/ar-etcd-revision.txt` — The file must hold the number and nothing else.

**Notes:** On the exam: `ssh` to the control plane, `sudo -i`, then run the same `etcdctl … snapshot save` and `etcdutl snapshot status`. If the exam node has only the older etcd 3.5 tools, `etcdctl snapshot status` works there too. An error with *context deadline exceeded* almost always means a wrong address or certificate path, or http instead of https. The setup copied etcdctl and etcdutl into `/usr/local/bin` on the lab node. They stay there for the next task.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

docker exec cka-control-plane test -s /opt/cka/etcd-snapshot.db 2>/dev/null && p "snapshot /opt/cka/etcd-snapshot.db exists on cka-control-plane" || f "snapshot /opt/cka/etcd-snapshot.db exists on cka-control-plane"
status=$(docker exec cka-control-plane sh -c 'pid=$(pgrep -xo etcd); /proc/$pid/root/usr/local/bin/etcdutl snapshot status /opt/cka/etcd-snapshot.db -w json' 2>/dev/null)
rev=$(echo "$status" | grep -o '"revision":[0-9]*' | cut -d: -f2)
keys=$(echo "$status" | grep -o '"totalKey":[0-9]*' | cut -d: -f2)
[ -n "$rev" ] && p "etcdutl snapshot status reads it (revision $rev)" || f "etcdutl snapshot status reads the snapshot"
[ -n "$keys" ] && [ "$keys" -gt 100 ] && p "snapshot holds cluster data ($keys keys)" || f "snapshot holds cluster data"
[ -n "$rev" ] && [ "$(tr -d '[:space:]' 2>/dev/null < /tmp/cka/ar-etcd-revision.txt)" = "$rev" ] && p "revision $rev recorded in /tmp/cka/ar-etcd-revision.txt" || f "revision recorded in /tmp/cka/ar-etcd-revision.txt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Restore etcd from a snapshot

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 12 min |

**Question:**

Someone deleted the ConfigMap `app-config` from namespace `ar-etcd`. A snapshot taken before the deletion is on `cka-control-plane` at `/opt/cka/etcd-before.db`. Restore etcd from that snapshot into the directory `/var/lib/etcd-from-backup` and make the cluster's etcd run from it. When you are done the API server must be serving again and `app-config` must exist.

<details>
<summary>💡 Hints</summary>

- etcdutl snapshot restore … --data-dir creates the new folder for you.
- In etcd.yaml, the hostPath of the etcd-data volume decides which node folder etcd sees at /var/lib/etcd.
- Stop the API server first by moving its manifest out of the folder. Do not forget to move it back.

</details>

<details>
<summary>✅ Solution</summary>

```bash
docker exec -i cka-control-plane bash <<'EOF'
set -e
etcdutl snapshot restore /opt/cka/etcd-before.db --data-dir /var/lib/etcd-from-backup
# keep the API server off while etcd changes data directories
mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/kube-apiserver.yaml
# only the etcd-data hostPath line ends in "path: /var/lib/etcd"
sed -i 's#path: /var/lib/etcd$#path: /var/lib/etcd-from-backup#' /etc/kubernetes/manifests/etcd.yaml
grep -n 'etcd-from-backup' /etc/kubernetes/manifests/etcd.yaml
# wait until etcd runs from the restored directory
for i in $(seq 1 60); do
  id=$(crictl ps --name '^etcd$' --state running -q | head -1)
  if [ -n "$id" ] && crictl inspect "$id" | grep -q '"hostPath": "/var/lib/etcd-from-backup"'; then break; fi
  sleep 3
done
mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
for i in $(seq 1 60); do kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 5; done
kubectl get --raw=/readyz
echo
kubectl -n ar-etcd get configmap app-config
```

**Explanation:**

- `docker exec -i cka-control-plane bash <<'EOF'` — Runs everything up to `EOF` as one script inside the node. Quoting `'EOF'` stops your local shell from expanding the `$` parts, so they are evaluated on the node.
- `set -e` — Makes the script stop at the first command that fails, instead of carrying on with a half-done restore.
- `etcdutl snapshot restore` — Restores the snapshot into the new directory `/var/lib/etcd-from-backup`.
- `mv /etc/kubernetes/manifests/kube-apiserver.yaml` — Stops the API server by moving its manifest out of the manifests folder.
- `sed -i 's#path: /var/lib/etcd$#` — Points the etcd-data hostPath at the restored directory. `$` means end of line, so only a line ending exactly in `path: /var/lib/etcd` changes, and running it twice does no harm.
- `grep -n 'etcd-from-backup'` — Shows the changed line with its line number (`-n`): proof the edit landed.
- `for i in $(seq 1 60); do` — Waits up to three minutes, 60 tries 3 seconds apart, for the kubelet to recreate etcd.
- `crictl ps --name '^etcd$'` — Gets the ID (`-q`) of the running container named exactly `etcd`; `^` and `$` mark the start and end of the name.
- `crictl inspect` — Searches that container's details for the restored hostPath. Once it is there, `break` leaves the loop.
- `mv /etc/kubernetes/kube-apiserver.yaml` — Moves the API server manifest back, so the kubelet starts it again.
- `kubectl get --raw=/readyz >/dev/null` — Back on your workstation: polls the API server's `/readyz` health endpoint every 5 seconds until it answers.
- `kubectl get --raw=/readyz` — Prints `ok` once the API server is ready. The `echo` after it only adds the newline that output lacks.
- `get configmap app-config` — The deleted ConfigMap is back, because the cluster now runs on data from before the deletion.

**Notes:** On the exam, make the hostPath change in vim. Then watch `crictl ps` until etcd and then kube-apiserver are back. In between, `kubectl` answers *connection refused*; that is normal. The docs say to stop the API server, because a running one can serve old data from its cache. If etcd will not start, `crictl ps -a --name etcd` and `crictl logs` show why; usually it is a typo in the path. This task changes the lab's etcd: run its cleanup afterwards to switch back to `/var/lib/etcd`, or rebuild with `lab-reset.sh`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

docker exec cka-control-plane grep -q 'path: /var/lib/etcd-from-backup$' /etc/kubernetes/manifests/etcd.yaml 2>/dev/null && p "etcd-data hostPath is /var/lib/etcd-from-backup" || f "etcd-data hostPath is /var/lib/etcd-from-backup"
docker exec cka-control-plane test -d /var/lib/etcd-from-backup/member 2>/dev/null && p "restored data directory exists" || f "restored data directory exists"
docker exec cka-control-plane test -f /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null && p "kube-apiserver manifest is in place" || f "kube-apiserver manifest is in place"
kubectl get --raw=/readyz >/dev/null 2>&1 && p "API server is ready" || f "API server is ready"
[ "$(kubectl -n ar-etcd get configmap app-config -o jsonpath='{.data.release}' 2>/dev/null)" = "blue" ] && p "ConfigMap app-config is back" || f "ConfigMap app-config is back"
total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
notready=$(kubectl get nodes --no-headers 2>/dev/null | grep -vc ' Ready ')
[ "$total" -gt 0 ] && [ "$notready" = "0" ] && p "all nodes Ready" || f "all nodes Ready"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
