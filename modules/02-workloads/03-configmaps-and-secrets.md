# ConfigMaps and Secrets

> **Module 2** · Lesson 2.3 · 40 minutes

Keep settings in ConfigMaps and passwords in Secrets, pass them to a container as environment variables or files, and know when a change reaches a running Pod.

## Learning Objectives

- You can create a ConfigMap or a Secret from literals, a file or an env file in one command, and decode any Secret value.
- You can pass one key with env.valueFrom, every key with envFrom, and files with a configMap or secret volume, including items and subPath.
- You can say which of these ways picks up a change, and what immutable: true does.


Your app needs settings: a mode, a color, a database password. You should not build them into the image, because then every change needs a new image. Kubernetes keeps them in two objects instead:

- A **ConfigMap** holds plain settings, such as `APP_MODE=production`.
- A **Secret** holds sensitive values, such as the password of your Django app's database.

Both are a list of keys with values. A container gets them in one of two ways: as environment variables, or as files in a folder.

**How settings reach a container**

`ConfigMap or Secret` — keys and values → `Two ways in`
  - `Environment variable` — read once, at start
  - `Mounted file` — one file per key → `Container` — your app reads them

Exam tasks here are short and very literal: a named object with named keys, used in a set way by a set container. The grader reads the object, then the Pod spec. It often runs `env` or `cat` inside the container too. Every detail in the task can be checked, so read it twice.

## Create them with one command

Each source has its own flag, and the same flags work for ConfigMaps and Secrets.

**One command per source type**

```bash
# ConfigMaps
kubectl -n wl-config create configmap app-config --from-literal=APP_MODE=production --from-literal=APP_COLOR=blue
kubectl -n wl-config create configmap nginx-conf --from-file=default.conf=./site.conf   # key=path sets the key name
kubectl -n wl-config create configmap app-env --from-env-file=./app.env                  # one key per KEY=VALUE line
kubectl -n wl-config create configmap scripts --from-file=./scripts/                      # one key per file in the directory

# Secrets: same flags, plus a type
kubectl -n wl-config create secret generic db --from-literal=username=app --from-literal=password='s3cr3t!'

# Look before you mount
kubectl -n wl-config describe configmap app-config
kubectl -n wl-config get secret db -o yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `create configmap app-config` — Each `--from-literal=KEY=VALUE` adds one key. Repeat the flag for every key. The ConfigMap is created right away.
- `--from-file=default.conf=./site.conf` — Stores the whole contents of `site.conf` as one value, under the key `default.conf`. Mounted as a volume, that key becomes a file with that name.
- `--from-env-file` — Reads a file of `KEY=VALUE` lines and makes each line its own key. Blank lines and lines starting with `#` are skipped.
- `--from-file=./scripts/` — Pointing `--from-file` at a folder adds one key per regular file in it, named after the file. Subfolders are ignored.
- `create secret generic db` — `generic` makes an Opaque Secret, the everyday type. The single quotes stop the shell from acting on special characters such as `!` in the password.
- `describe configmap` — Shows every key and value in readable form. On a Secret, describe shows only each value's size in bytes.
- `get secret db -o yaml` — Shows the Secret's `data`, with every value base64-encoded. The next block decodes one.

</details>

| Flag | The key is | The value is |
| --- | --- | --- |
| `--from-literal=K=V` | `K` | `V` |
| `--from-file=path` | The file's name, or the name you give with `key=path` | The whole file |
| `--from-env-file=path` | One key for each `KEY=VALUE` line | The text after `=`. Quotes are kept, so `A="x"` stores the quotes too |

Mixing up the last two is the most common reason a file or a variable comes out wrong. Take a Django app's `.env` file. `--from-env-file=.env` gives you `DEBUG`, `SECRET_KEY` and so on as separate keys. `--from-file=.env` gives you one key, `.env`, holding the whole file.

Secrets also have a **type**. For your own apps it is `Opaque`, which `kubectl create secret generic` makes. Other types each have one set job, and each is taught where it is used. TLS certificates are in [Ingress](/cka/networking/ingress), registry logins in [Application failures](/cka/troubleshooting/application-failures), and service account tokens in [RBAC](/cka/architecture/rbac).

## base64 is an encoding, not protection

Secret values are stored in **base64**. That is an encoding, not encryption: anyone can turn it back into the original text with one command.

**Reading and writing Secret values**

```bash
kubectl -n wl-config get secret db -o jsonpath='{.data.password}' | base64 -d; echo
echo -n 's3cr3t!' | base64        # -n matters: without it the trailing newline is encoded too
kubectl -n wl-config create secret generic db2 --from-literal=password='s3cr3t!' --dry-run=client -o yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `base64 -d; echo` — Pulls out one encoded value and decodes it with `base64 -d`. The `echo` after `;` only adds a newline, so your prompt does not end up on the same line.
- `echo -n` — Encodes text by hand, for when you write a Secret's `data` field in YAML yourself.
- `create secret generic db2` — Lets kubectl do the encoding. It prints a Secret manifest with the value already in base64, ready to save. That is safer than encoding by hand.

</details>

- In a Secret's YAML, `data` takes base64 values.
- `stringData` takes plain text. The API server encodes it when it saves the Secret, and never shows `stringData` back to you.

Secrets are not encrypted by default. Anyone allowed to create Pods in a namespace can read every Secret there, just by mounting it. So the real protection is RBAC: who may read Secrets, and who may create Pods.

## As environment variables

There are two ways to turn keys into environment variables:

- `env` with `valueFrom`: one key, and you choose the variable's name.
- `envFrom`: every key in the object, each as a variable with the key's name.

**Environment variables: one key, or every key**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
  namespace: wl-config
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: MODE                  # one key, under a new name
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: APP_MODE
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db
              key: password
      envFrom:                        # every key becomes a variable
        - configMapRef:
            name: app-config
        - prefix: DB_                 # username becomes DB_username
          secretRef:
            name: db
```

<details>
<summary>Line-by-line explanation</summary>

- `command: ["sleep", "3600"]` — Keeps the container alive for an hour, so you can exec in and check the variables. busybox would otherwise exit at once.
- `valueFrom:` — Instead of a fixed `value`, read it from another object. `configMapKeyRef` names the ConfigMap and the key. The variable is called MODE even though the key is APP_MODE.
- `secretKeyRef:` — The same for one Secret key. The container sees the decoded value, not base64.
- `envFrom:` — Imports every key of `app-config` at once, each as a variable named after its key: APP_MODE and APP_COLOR.
- `- prefix: DB_` — `prefix` and `secretRef` belong to the same list entry (one dash). Every key of Secret `db` is imported with `DB_` in front.

</details>

- If the ConfigMap, the Secret or the key does not exist, the container does not start. The Pod shows `CreateContainerConfigError`, and `kubectl describe pod` names the missing piece.
- Add `optional: true` to a reference only when the task allows the value to be missing.
- If `env` and `envFrom` set the same name, the one under `env` wins.

## As files

A ConfigMap or Secret can also be a volume. Each key becomes a file, and the value becomes the file's contents. For example, a ConfigMap key `default.conf` becomes a file `default.conf` that nginx reads as its config.

**Files: a whole object, selected keys, or one file with subPath**

```yaml
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          volumeMounts:
            - name: conf                 # one file dropped into an existing directory
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
            - name: creds                # the whole Secret as a directory of files
              mountPath: /etc/creds
              readOnly: true
      volumes:
        - name: conf
          configMap:
            name: nginx-conf             # configMap uses "name" ...
            items:                       # only these keys, under these file names
              - key: default.conf
                path: default.conf
        - name: creds
          secret:
            secretName: db               # ... secret uses "secretName"
            defaultMode: 0400            # octal in YAML; the API stores it as 256
```

<details>
<summary>Line-by-line explanation</summary>

- `spec:` — A piece of a Deployment's Pod template, which is why it starts indented. It shows only the parts that mount files.
- `volumeMounts:` — Each entry names a volume from the list below and says where it appears in this container.
- `mountPath: /etc/nginx/conf.d/default.conf` — With `subPath`, `mountPath` is the full path of a single file, not a folder.
- `subPath: default.conf` — Takes only the `default.conf` entry from the volume and puts it at that path. The rest of `/etc/nginx/conf.d` stays as the image built it.
- `readOnly: true` — The container cannot write to this mount. Secret and ConfigMap volumes are read-only anyway; this makes it explicit.
- `volumes:` — Declared once per Pod. Each name here must match a `volumeMounts` name above.
- `configMap:` — A volume built from a ConfigMap: each key becomes a file, and its value the file's contents.
- `- key: default.conf` — `key` is the ConfigMap key and `path` the file name it gets inside the volume. Keys you do not list are left out.
- `secret:` — The same idea for a Secret: each key becomes a file holding the decoded value.
- `defaultMode: 0400` — File permissions for every file in the volume: 0400 means the owner may read and nobody may write. The leading 0 makes YAML read the number as octal.

</details>

Watch out: a volume mounted on a folder hides whatever the image had in that folder. That is fine for an empty folder such as `/etc/creds`. On `/etc/nginx` it breaks nginx, because its main config file disappears. To add one file to a folder that already has content, use `subPath`. It has a cost, shown in the next table.

## Which changes reach a running Pod

You edit a ConfigMap. Does the running app see the change? It depends on how the container gets it:

| Used as | Sees the change? | What to do |
| --- | --- | --- |
| `env` or `envFrom` | No. Variables are read once, when the container starts. | Restart: `kubectl rollout restart deploy/` |
| A volume (whole object or `items`) | Yes, usually within a minute or two. The app must read the file again. | Wait, or restart if the app keeps its config in memory |
| A volume with `subPath` | Never. | Restart the Pod |
| `immutable: true` | The object itself can no longer change. | Delete it, create it again, then restart the Pods that use it |

`immutable: true` on a ConfigMap or Secret is a one-way door. You cannot unset it; you can only delete the object. In return, the kubelet stops watching the object, which takes load off the API server in big clusters. And no one can change the config under a running app by accident.

> [!IMPORTANT] **What the grader reads**
> The grader reads the keys and values, the Secret's type, and how the Pod uses them: `env[].valueFrom`, `envFrom`, `volumes` and `volumeMounts`. Many graders also look inside the container. So check it yourself before you move on: `kubectl exec deploy/app -- env | grep MODE`, or `kubectl exec pod/x -- cat /etc/app/KEY`. Key names are case-sensitive. And a `--from-file` key is the file's name, not the name you had in mind.

## 📝 Key Takeaways

- A ConfigMap holds plain settings and a Secret holds sensitive ones. Both are keys with values.
- `--from-file` makes one key per file. `--from-env-file` makes one key per line.
- Secret values are only base64-encoded, not encrypted. RBAC is what protects them.
- `env` with `valueFrom` takes one key, and `envFrom` takes them all. A volume turns each key into a file.
- Environment variables and `subPath` files never see a change until the container restarts. Whole-volume files update by themselves.

**📖 Official documentation:**

- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) *(search: "configure pod configmap")*
- [Distribute Credentials Securely Using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) *(search: "distribute credentials secrets")*
- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) *(search: "secret types")*
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) *(search: "configmap")*

---

### 🎯 Task: Configure a Deployment from a ConfigMap and a Secret

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

In namespace `wl-config`: create a ConfigMap `app-config` with the keys `APP_MODE=production` and `APP_COLOR=blue`, and a Secret `app-secret` of type Opaque with the key `DB_PASSWORD=s3cr3t-pass`. Then create a Deployment `app` with 2 replicas, image `busybox:1.36`, container name `app`, running `sleep 3600`. The container must get an environment variable `MODE` from the key `APP_MODE` of `app-config`, every key of `app-secret` as an environment variable, and every key of `app-config` as a file under `/etc/app`.

<details>
<summary>💡 Hints</summary>

- Make the two objects with two `kubectl create` commands. Then get a Deployment skeleton with `kubectl create deployment --dry-run=client -o yaml`.
- `MODE` needs `env[].valueFrom.configMapKeyRef`. "Every key of the Secret" is `envFrom` with a `secretRef`. The files are a `configMap` volume mounted at `/etc/app`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-config create configmap app-config --from-literal=APP_MODE=production --from-literal=APP_COLOR=blue
kubectl -n wl-config create secret generic app-secret --from-literal=DB_PASSWORD=s3cr3t-pass
cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: wl-config
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sleep", "3600"]
          env:
            - name: MODE
              valueFrom:
                configMapKeyRef:
                  name: app-config
                  key: APP_MODE
          envFrom:
            - secretRef:
                name: app-secret
          volumeMounts:
            - name: config
              mountPath: /etc/app
      volumes:
        - name: config
          configMap:
            name: app-config
YAML
kubectl -n wl-config rollout status deploy/app --timeout=120s
```

**Explanation:**

- `create configmap app-config` — The ConfigMap with its two keys, in one command.
- `create secret generic app-secret` — `generic` gives the type Opaque that the question asks for. kubectl base64-encodes the value for you.
- `cat <<'YAML'` — The Deployment as a heredoc. In the exam you would generate it with `kubectl create deployment … --dry-run=client -o yaml` and edit it.
- `matchLabels:` — Selector and template labels must match: both are `app: app`.
- `command:` — Runs `sleep 3600` as asked, which keeps the container up.
- `configMapKeyRef:` — Variable MODE takes its value from key APP_MODE of `app-config`.
- `envFrom:` — "Every key of app-secret": `envFrom` with a `secretRef` imports them all, so DB_PASSWORD appears under its own name.
- `mountPath: /etc/app` — The whole ConfigMap as a folder: `/etc/app/APP_MODE` and `/etc/app/APP_COLOR`, each file holding one value.
- `configMap:` — The volume's source is the ConfigMap `app-config`; the volume name `config` links it to the mount above.
- `rollout status` — Waits until both replicas run. If a reference is wrong, the Pods sit in CreateContainerConfigError and this times out.

**Notes:** On the exam, run the two `create` commands first. Then generate the Deployment with `kubectl create deployment app -n wl-config --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml -- sleep 3600 > app.yaml`, and add `env`, `envFrom`, `volumeMounts` and `volumes` in vim. `kubectl set env deploy/app --from=secret/app-secret` also works for the Secret part. It adds each key as its own `secretKeyRef` instead of using `envFrom`, but the container gets the same variable. Check the result with `kubectl exec deploy/app -n wl-config -- env` and `kubectl exec deploy/app -n wl-config -- ls /etc/app`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-config
d="kubectl -n $ns get deploy app -o jsonpath"

[ "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.APP_MODE}' 2>/dev/null)" = "production" ] && p "app-config APP_MODE=production" || f "app-config APP_MODE=production"
[ "$(kubectl -n $ns get cm app-config -o jsonpath='{.data.APP_COLOR}' 2>/dev/null)" = "blue" ] && p "app-config APP_COLOR=blue" || f "app-config APP_COLOR=blue"
[ "$(kubectl -n $ns get secret app-secret -o jsonpath='{.type}' 2>/dev/null)" = "Opaque" ] && p "secret app-secret is Opaque" || f "secret app-secret is Opaque"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "deployment app has 2 replicas" || f "deployment app has 2 replicas"
[ "$($d='{.spec.template.spec.containers[0].env[?(@.name=="MODE")].valueFrom.configMapKeyRef.name}' 2>/dev/null)" = "app-config" ] && p "MODE comes from app-config" || f "MODE comes from app-config"
[ "$($d='{.spec.template.spec.containers[0].env[?(@.name=="MODE")].valueFrom.configMapKeyRef.key}' 2>/dev/null)" = "APP_MODE" ] && p "MODE uses key APP_MODE" || f "MODE uses key APP_MODE"
[ -n "$($d='{.spec.template.spec.volumes[?(@.configMap.name=="app-config")].name}' 2>/dev/null)" ] && p "app-config mounted as a volume" || f "app-config mounted as a volume"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
envout="$(kubectl -n $ns exec deploy/app -- env 2>/dev/null)"
echo "$envout" | grep -qx "MODE=production" && p "env MODE=production in the container" || f "env MODE=production in the container"
echo "$envout" | grep -qx "DB_PASSWORD=s3cr3t-pass" && p "env DB_PASSWORD in the container" || f "env DB_PASSWORD in the container"
[ "$(kubectl -n $ns exec deploy/app -- cat /etc/app/APP_COLOR 2>/dev/null)" = "blue" ] && p "/etc/app/APP_COLOR contains blue" || f "/etc/app/APP_COLOR contains blue"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Replace a config file and mount a Secret with strict permissions

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

A replacement nginx server block is in `/tmp/cka/wl-config/default.conf`. In namespace `wl-config`, create a ConfigMap `proxy-conf` from that file with the key `default.conf`, and a Secret `proxy-token` with the key `token` set to `abc123`. Then create a Pod `proxy` (image `nginx:1.27`) in which the ConfigMap's file replaces `/etc/nginx/conf.d/default.conf`, so that `http://localhost:8080/healthz` inside the Pod returns `healthy`, and the Secret is available as the file `/etc/proxy/token` with permissions `0400`.

<details>
<summary>💡 Hints</summary>

- `--from-file=default.conf=/tmp/cka/wl-config/default.conf` gives the key the right name.
- Mount the ConfigMap on `/etc/nginx/conf.d`, or mount one file with `subPath`. Mount the Secret on `/etc/proxy` with `defaultMode: 0400`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n wl-config create configmap proxy-conf --from-file=default.conf=/tmp/cka/wl-config/default.conf
kubectl -n wl-config create secret generic proxy-token --from-literal=token=abc123
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: proxy
  namespace: wl-config
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 8080
      volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
        - name: token
          mountPath: /etc/proxy
          readOnly: true
  volumes:
    - name: conf
      configMap:
        name: proxy-conf
    - name: token
      secret:
        secretName: proxy-token
        defaultMode: 0400
YAML
kubectl -n wl-config wait --for=condition=Ready pod/proxy --timeout=120s
```

**Explanation:**

- `create configmap proxy-conf` — `default.conf=` sets the key name explicitly; the value is the whole file.
- `create secret generic proxy-token` — One key, `token`. Mounted as a volume, it becomes the file `token`.
- `containerPort: 8080` — The replacement server block listens on 8080 instead of nginx's usual 80; this line documents that.
- `mountPath: /etc/nginx/conf.d/default.conf` — With `subPath` on the next line, only this one file is replaced and the rest of the folder stays as the image built it.
- `mountPath: /etc/proxy` — The Secret as a folder, so key `token` becomes `/etc/proxy/token`.
- `defaultMode: 0400` — Read-only for the owner and nothing for anyone else: the 0400 the question asks for. The leading 0 means octal.
- `wait --for=condition=Ready` — A broken config makes nginx exit, so the Pod would never become Ready. This wait also tests the file.

**Notes:** Either mount works here. You can mount the whole ConfigMap on `/etc/nginx/conf.d`, because the image has only `default.conf` there. Or you can mount one file with `subPath`, but then the file never picks up later ConfigMap edits. `defaultMode: 0400` is octal in YAML; in JSON you must write `256`. Secret files are symlinks, so check the permissions with `-L`, which follows the link: `kubectl exec proxy -n wl-config -- stat -L -c %a /etc/proxy/token`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=wl-config

kubectl -n $ns get cm proxy-conf -o jsonpath='{.data.default\.conf}' 2>/dev/null | grep -q "listen 8080" && p "proxy-conf has key default.conf from the file" || f "proxy-conf has key default.conf from the file"
[ "$(kubectl -n $ns get secret proxy-token -o jsonpath='{.data.token}' 2>/dev/null)" = "YWJjMTIz" ] && p "proxy-token token=abc123" || f "proxy-token token=abc123"
[ "$(kubectl -n $ns get pod proxy -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "pod proxy runs nginx:1.27" || f "pod proxy runs nginx:1.27"
[ "$(kubectl -n $ns get pod proxy -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod proxy Running" || f "pod proxy Running"
[ "$(kubectl -n $ns exec proxy -- curl -s localhost:8080/healthz 2>/dev/null)" = "healthy" ] && p "nginx answers /healthz on 8080" || f "nginx answers /healthz on 8080"
[ "$(kubectl -n $ns exec proxy -- cat /etc/proxy/token 2>/dev/null)" = "abc123" ] && p "/etc/proxy/token contains abc123" || f "/etc/proxy/token contains abc123"
[ "$(kubectl -n $ns exec proxy -- stat -L -c %a /etc/proxy/token 2>/dev/null)" = "400" ] && p "/etc/proxy/token mode 0400" || f "/etc/proxy/token mode 0400"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 2: Workloads & scheduling*
