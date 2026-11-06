# The exam-day cheat sheet

> **Module 6** · Lesson 6.1 · 30 minutes

Every command and short YAML example this course uses, grouped by exam domain, plus the kubernetes.io search phrase that finds the right page for each topic.

## Learning Objectives

- You can write any YAML skeleton on this page from memory, or with one kubectl explain.
- You can find the right docs page for any exam topic with a single search phrase.
- You can run the cluster checks and then the node checks in order, without looking anything up.


This page is a reference, not a lesson. Keep it open while you do the mocks, until you no longer need it.

- Everything here runs on the lab as written.
- Node commands run in a node shell: `docker exec -it cka-control-plane bash` in the lab, or `ssh ` then `sudo -i` on the exam.
- The YAML examples are short on purpose. `kubectl explain .` shows any other field you need.
- The first block of each domain shows the domain's exam weight in its title, so you know where a minute is worth most.
- You cannot bring this page into the exam. The table at the end gives the kubernetes.io search phrase for each topic instead.

**kubectl: setup, generators, reading and changing objects**

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
source <(kubectl completion bash); complete -o default -F __start_kubectl k
printf 'set ts=2 sw=2 et nu\n' > ~/.vimrc

k run web --image=nginx:1.27 --port=80 --labels=app=web $do > pod.yaml
k run tmp --image=busybox:1.36 --restart=Never -it --rm -- sh          # throwaway shell
k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do > deploy.yaml
k expose deploy web --name=web-svc --port=80 --target-port=8080 --type=ClusterIP
k create svc nodeport web --tcp=80:8080 --node-port=30080
k create cm app-cfg --from-literal=KEY=value --from-file=app.properties
k create cm app-env --from-env-file=.env      # env files cannot be combined with the other two
k create secret generic db --from-literal=password=s3cret
k create secret tls web-tls --cert=tls.crt --key=tls.key
k create job once --image=busybox:1.36 -- sh -c 'date'
k create job manual --from=cronjob/nightly
k create cj nightly --image=busybox:1.36 --schedule='0 2 * * *' -- sh -c 'date'
k create ingress web --class=nginx --rule='shop.example.com/*=web-svc:80'
k create ns team-a; k create quota q --hard=pods=10,requests.cpu=2 -n team-a
k create pdb web-pdb --selector=app=web --min-available=1
k create priorityclass high --value=100000
k autoscale deploy web --min=2 --max=6 --cpu=70%
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.26
k set env deploy/web LOG_LEVEL=debug; k set env deploy/web --from=configmap/app-cfg
k set resources deploy/web -c nginx --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
k set sa deploy/web app
k label pod web tier=frontend --overwrite; k label pod web tier-
k annotate deploy web kubernetes.io/change-cause="image 1.26" --overwrite
k explain deploy.spec.strategy; k explain pod.spec.containers.livenessProbe --recursive
k api-resources | grep -i <word>; k api-versions

# --- Reading the cluster: formats, selectors, jsonpath, config
k get pods -o wide -A; k get pods -o name; k get pods --show-labels
k get pods -l app=web,tier!=cache; k get pods -l 'env in (prod,staging)'
k get pods -A --field-selector=status.phase!=Running
k get pods --sort-by=.metadata.creationTimestamp; k get events --sort-by=.lastTimestamp
k get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
k get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}'
k get pods -o jsonpath='{.items[*].metadata.name}'
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
k get pods -A -o jsonpath='{range .items[?(@.spec.nodeName=="cka-worker")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.taints[*].key}{"\n"}{end}'
k get deploy web -o yaml | yq '.spec.template.spec.containers[].image'
k get pods -w                                     # Ctrl+C to stop

k config get-contexts; k config use-context <ctx>; k config current-context
k config set-context --current --namespace=<ns>; k config view --minify
k --kubeconfig=/path/kubeconfig get nodes

k edit deploy web                                 # mutable fields
k apply -f file.yaml                              # from a file
k get pod web -o yaml > p.yaml; k replace --force -f p.yaml   # immutable Pod fields
k delete pod web $now                             # stuck Terminating
```

<details>
<summary>Line-by-line explanation</summary>

- `alias k=kubectl` — Makes `k` short for `kubectl`. The exam terminal already has it, and every line below uses it.
- `export do=` — `$do` expands to `--dry-run=client -o yaml`: print the object as YAML instead of creating it.
- `export now=` — `$now` expands to `--force --grace-period=0`: delete at once instead of waiting about 30 seconds.
- `source <(kubectl completion bash)` — Turns on Tab completion for `kubectl`; the `complete … k` part extends it to the alias.
- `printf 'set ts=2` — Writes a vim config: tabs and indents of 2 (`ts`, `sw`), spaces instead of tab characters (`et`), line numbers (`nu`). YAML rejects tabs, so this matters. `>` replaces any existing file.
- `k run web --image=nginx:1.27 --port=80` — Writes a Pod manifest to `pod.yaml` without creating anything: name, image, container port and the label `app=web`.
- `k run tmp --image=busybox:1.36 --restart=Never -it --rm -- sh` — A throwaway Pod with a shell. `-it` attaches your terminal, `--rm` deletes the Pod when you exit, `--restart=Never` keeps it a plain Pod.
- `k create deploy web` — Writes a 3-replica Deployment manifest to `deploy.yaml`, ready to edit and apply.
- `k expose deploy web` — Creates a Service in front of the Deployment's Pods, copying its selector. `--port` is the Service's port, `--target-port` the container's.
- `k create svc nodeport` — A NodePort Service on its own. `--tcp=80:8080` means Service port 80 to container port 8080. The selector becomes `app=web`, taken from the Service name.
- `k create cm app-cfg` — Two ways to fill a ConfigMap in one go: a key from the command line, and a file whose name becomes the key.
- `k create cm app-env` — An env file makes one key per `KEY=VALUE` line. kubectl refuses `--from-env-file` together with `--from-literal` or `--from-file`, so it gets its own ConfigMap.
- `k create secret generic db` — A Secret with one key, `password`. kubectl base64-encodes the value for you.
- `k create secret tls web-tls` — A TLS Secret from a certificate file and its key. Ingress and Gateway listeners refer to it by name.
- `k create job once` — A Job that runs `date` once. Everything after `--` becomes the container's command.
- `k create job manual --from=cronjob/nightly` — Starts a Job right now from a CronJob's template, without waiting for the schedule. The quick way to test a CronJob.
- `k create cj nightly` — A CronJob. The schedule is cron syntax (minute, hour, day of month, month, day of week), so `0 2 * * *` is 02:00 daily. Quotes keep the shell away from the `*`.
- `k create ingress web` — An Ingress sending `shop.example.com` to `web-svc` port 80. A path ending in `*` becomes pathType Prefix; without it, Exact.
- `k create ns team-a; k create quota` — A namespace, then a ResourceQuota capping it at 10 Pods and 2 CPUs of requests in total.
- `k create pdb web-pdb` — A PodDisruptionBudget: a drain, or any other planned eviction, must leave at least 1 Pod labeled `app=web` running.
- `k create priorityclass high` — A PriorityClass. Pods that name it in `priorityClassName` are scheduled first, and may push out (preempt) lower-priority Pods. A higher value means a higher priority.
- `k autoscale deploy web` — An HPA keeping 2 to 6 replicas at 70% average CPU of the Pods' requests. `--cpu=70%` replaces the deprecated `--cpu-percent=70`, which still works but prints a warning.
- `k scale deploy web --replicas=5` — Sets the replica count directly.
- `k set image deploy/web nginx=nginx:1.26` — Changes the image and starts a rollout. The part before `=` is the container name, not the image.
- `k set env deploy/web LOG_LEVEL=debug` — Adds one variable, or with `--from=configmap/app-cfg` every key of the ConfigMap. Both change the Pod template, so Pods are replaced.
- `k set resources deploy/web` — Sets requests (what the scheduler reserves) and limits (the ceiling) on the container picked with `-c`.
- `k set sa deploy/web app` — Makes the Deployment's Pods run as ServiceAccount `app`.
- `k label pod web tier=frontend --overwrite` — Sets a label, replacing an old value thanks to `--overwrite`. A trailing dash, `tier-`, removes it.
- `k annotate deploy web kubernetes.io/change-cause` — This annotation fills the CHANGE-CAUSE column of `rollout history`, now that `--record` is gone.
- `k explain deploy.spec.strategy` — Shows what a field means, straight from the cluster. `--recursive` prints every nested field at once.
- `k api-resources | grep -i` — Finds a resource's short name, its API group and whether it lives in a namespace (`` is a placeholder). `api-versions` lists every API group and version the cluster offers.
- `k get pods -o wide -A` — `-o wide` adds node and IP columns, `-A` covers every namespace, `-o name` prints only `pod/`, `--show-labels` adds a labels column.
- `k get pods -l app=web,tier!=cache` — Label selectors: a comma means AND, and `in (…)` is the set form. Quote the set form, because the shell treats parentheses specially.
- `--field-selector=status.phase!=Running` — Filters on fields instead of labels: every Pod not in phase Running, cluster-wide.
- `--sort-by=.metadata.creationTimestamp` — Sorts Pods oldest first and events by time, so the newest event is the last line.
- `custom-columns=NAME` — Your own table: each `HEADER:.path` pair is one column.
- `containers[*].image}'` — Every container image in the Deployment's Pod template.
- `'{.items[*].metadata.name}'` — All Pod names on one line. A list result wraps the objects in `items`.
- `{.metadata.name}{" "}{.status.addresses` — One line per node with its InternalIP: `range … end` loops, `?(@.type=="InternalIP")` filters the address list, `{"\n"}` ends each line.
- `items[?(@.spec.nodeName=="cka-worker")]` — Filters whole Pods: only those on `cka-worker`, printed as namespace/name. Text outside braces, like the `/`, prints as is.
- `{.spec.taints[*].key}` — Each node's name and its taint keys; an untainted node prints its name alone.
- `| yq '` — `yq` walks YAML with a simpler syntax; `containers[]` means every container.
- `k get pods -w` — Watches: prints a new line on every change until Ctrl+C.
- `k config get-contexts;` — Lists contexts (`*` marks the current one), switches, and confirms. Each exam task names the context to use.
- `set-context --current --namespace` — Changes the current context's default namespace so you can drop `-n`. `view --minify` shows only the active cluster, user and namespace.
- `--kubeconfig=/path/kubeconfig` — Uses another kubeconfig file for one command, when a task hands you one.
- `k edit deploy web` — Opens the live object in vim; saving applies it. An invalid change reopens the file with the error at the top.
- `k apply -f file.yaml` — Creates or updates objects from a file. Safe to repeat after every edit.
- `k replace --force -f p.yaml` — For Pod fields that cannot change in place: save the Pod, edit the file, then `replace --force` deletes and recreates it.
- `k delete pod web $now` — Deletes at once, for a Pod stuck Terminating or one you are about to recreate.

</details>

**Architecture (25%): RBAC, service accounts, certificates, kubeconfig**

```bash
k create role dev --verb=get,list,watch --resource=pods,deployments -n team-a
k create role dev-pod --verb=get --resource=pods --resource-name=web -n team-a
k create rolebinding dev-rb --role=dev --user=jane -n team-a
k create clusterrole nodes-ro --verb=get,list,watch --resource=nodes
k create clusterrole health --verb=get --non-resource-url=/healthz
k create clusterrolebinding nodes-ro-rb --clusterrole=nodes-ro --group=ops
k create rolebinding sa-rb --clusterrole=view --serviceaccount=team-a:app -n team-a   # ClusterRole bound in one namespace
k auth can-i list pods --as=jane -n team-a
k auth can-i get nodes --as=system:serviceaccount:team-a:app
k auth can-i --list --as=jane -n team-a

k create sa app -n team-a
k create token app -n team-a --duration=1h
# Pod: spec.serviceAccountName: app   spec.automountServiceAccountToken: false

# Client certificate for a user via the CSR API
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -subj "/CN=jane/O=devs" -out jane.csr
base64 < jane.csr | tr -d '\n'    # one line; goes into spec.request below
k certificate approve jane; k certificate deny jane
k get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt
k config set-credentials jane --client-key=jane.key --client-certificate=jane.crt --embed-certs
k config set-context jane --cluster=kubernetes --user=jane --namespace=team-a

# kubeadm-managed certificates (on the control plane)
kubeadm certs check-expiration
kubeadm certs renew apiserver; kubeadm certs renew all
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates -subject -ext subjectAltName
```

<details>
<summary>Line-by-line explanation</summary>

- `k create role dev` — A Role lists what may be done (the verbs) to which resource types, in one namespace. kubectl puts each resource under its API group for you (`deployments` under `apps`).
- `--resource-name=web` — Narrows the rule to one named object: `get` on Pod `web` only.
- `k create rolebinding dev-rb` — Grants Role `dev` to user `jane` in `team-a`. A Role does nothing until a binding names a subject.
- `k create clusterrole nodes-ro` — A ClusterRole is not tied to a namespace, so it can cover cluster-wide resources such as nodes.
- `--non-resource-url=/healthz` — Non-resource URLs are plain API paths like `/healthz`, not objects. Only a ClusterRole can grant them.
- `k create clusterrolebinding nodes-ro-rb` — Grants the ClusterRole across the whole cluster to everyone in group `ops`.
- `k create rolebinding sa-rb --clusterrole=view` — A RoleBinding can point at a ClusterRole: you reuse the built-in `view` rules, but only inside `team-a`. ServiceAccounts are written `namespace:name`.
- `k auth can-i list pods --as=jane` — Asks the API server whether jane may list Pods there and prints yes or no. The fastest check after any RBAC task.
- `--as=system:serviceaccount:team-a:app` — To impersonate a ServiceAccount, use its full username: `system:serviceaccount::`.
- `k auth can-i --list --as=jane` — Lists everything jane may do in the namespace.
- `k create sa app -n team-a` — Creates a ServiceAccount: the identity a Pod uses to talk to the API server.
- `k create token app` — Issues a short-lived token for that ServiceAccount, valid for one hour. Nothing is stored in a Secret.
- `openssl genrsa -out jane.key 2048` — Creates a 2048-bit private key for the user. It never leaves your machine.
- `openssl req -new -key jane.key` — Builds a certificate signing request. Kubernetes reads the CN as the username (`jane`) and each O as a group (`devs`).
- `base64 < jane.csr` — Encodes the request and strips the line breaks, because `spec.request` needs it on one line. Works on Linux and macOS; on Linux `base64 -w0 jane.csr` does the same.
- `k certificate approve jane` — Approves the CertificateSigningRequest so the cluster signs it; `deny` refuses it.
- `k get csr jane -o jsonpath` — The signed certificate sits base64-encoded in `status.certificate`; `base64 -d` turns it back into a PEM file.
- `k config set-credentials jane` — Adds user jane to your kubeconfig. `--embed-certs` copies the key and certificate into the file, so it works on its own.
- `k config set-context jane` — A context ties a cluster, a user and a default namespace together. Use the name from `k config get-clusters`: `kubernetes` on kubeadm clusters, `kind-cka` in the lab.
- `kubeadm certs check-expiration` — Lists every certificate kubeadm manages with its expiry date and time left.
- `kubeadm certs renew apiserver` — Renews one certificate or all of them. The control-plane static Pods must restart afterwards to load the new files.
- `openssl x509 -in /etc/kubernetes/pki/apiserver.crt` — Prints a certificate's validity dates, subject and the names it is valid for (subjectAltName); `-noout` skips the encoded body.

</details>

**Architecture: kubeadm upgrade sequence, drain, etcd backup and restore**

```bash
# --- Upgrade one minor (example 1.36 -> 1.37). On the node, as root. Control plane first, then each worker.
sed -i 's|v1\.36|v1.37|' /etc/apt/sources.list.d/kubernetes.list && apt-get update
apt-cache madison kubeadm | head -3
apt-mark unhold kubeadm && apt-get install -y kubeadm='1.37.0-*' && apt-mark hold kubeadm
kubeadm version
kubeadm upgrade plan
kubeadm upgrade apply v1.37.0                 # first control plane only
kubeadm upgrade node                          # other control planes and every worker
# From a machine with kubectl, before touching kubelet on that node:
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# Back on the node:
apt-mark unhold kubelet kubectl && apt-get install -y kubelet='1.37.0-*' kubectl='1.37.0-*' && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon <node>
kubectl get nodes                              # VERSION column moves node by node

# --- Node maintenance
kubectl cordon <node>; kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force; kubectl uncordon <node>

# --- etcd: find the flags first (static pod on the control plane)
grep -E 'listen-client-urls|cert-file|key-file|trusted-ca-file|data-dir' /etc/kubernetes/manifests/etcd.yaml

# Snapshot
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db
etcdutl snapshot status /opt/etcd-backup.db -w table

# Restore into a new data dir, then point the static pod at it
etcdutl snapshot restore /opt/etcd-backup.db --data-dir /var/lib/etcd-restored
# edit /etc/kubernetes/manifests/etcd.yaml: the etcd-data hostPath volume -> /var/lib/etcd-restored
# kubelet notices the manifest change and recreates etcd; wait, then:
crictl ps | grep etcd; kubectl get pods -A

# --- Static pods and the control plane
ls /etc/kubernetes/manifests/                 # kube-apiserver, controller-manager, scheduler, etcd
grep staticPodPath /var/lib/kubelet/config.yaml
kubectl -n kube-system get pods -o wide         # control-plane pods are named <component>-<node>
```

<details>
<summary>Line-by-line explanation</summary>

- `sed -i 's|v1` — Points apt at the v1.37 package repository (pkgs.k8s.io has one per minor version), then `apt-get update` reads its package list.
- `apt-cache madison kubeadm` — Lists the kubeadm versions the repository offers, so you can pick the exact patch release.
- `apt-mark unhold kubeadm` — The packages are held so routine updates never touch them: unhold, install the chosen version, hold again. `'1.37.0-*'` matches any package revision of 1.37.0.
- `kubeadm version` — Confirms the new kubeadm is the one that runs.
- `kubeadm upgrade plan` — Checks that the cluster can be upgraded and shows the target versions. Changes nothing.
- `kubeadm upgrade apply v1.37.0` — Upgrades the control-plane components on the first control-plane node by rewriting their static Pod manifests. It also renews their certificates.
- `kubeadm upgrade node` — On every other node: brings the local kubelet configuration (and, on extra control planes, the static Pods) up to the new version.
- `kubectl drain <node>` — Cordons the node (no new Pods) and evicts its Pods before the kubelet restarts, so their controllers start them elsewhere. DaemonSet Pods stay. Data in emptyDir volumes is lost.
- `apt-mark unhold kubelet kubectl` — The same unhold, install, hold pattern for kubelet and kubectl.
- `systemctl daemon-reload` — Reloads systemd's unit files, which the package may have changed, and restarts kubelet so the new version runs.
- `kubectl uncordon <node>` — Lets the scheduler use the node again. drain does not undo itself.
- `kubectl cordon <node>;` — `cordon` only stops new Pods; `drain` also evicts running ones (`--force` deletes Pods no controller manages); `uncordon` reverses both.
- `grep -E 'listen-client-urls` — Pulls the endpoint, certificate paths and data directory out of etcd's static Pod manifest, so you copy them instead of guessing.
- `etcdctl --endpoints=https://127.0.0.1:2379` — etcd only talks to clients with a certificate: `--cacert` checks etcd's, `--cert` and `--key` prove yours. Each trailing `\` continues the command on the next line.
- `snapshot save /opt/etcd-backup.db` — Saves a copy of the whole database, taken at one moment, to that file.
- `etcdutl snapshot status` — Reads the file offline and prints its hash, revision, key count and size as a table. A readable status proves the backup is usable.
- `etcdutl snapshot restore` — Unpacks the snapshot into a new, empty data directory. It never touches the running etcd's directory.
- `crictl ps | grep etcd; kubectl get pods -A` — Checks that the etcd container runs again, then that the API answers. Expect a minute without the API while etcd and the API server restart.
- `ls /etc/kubernetes/manifests/` — kubelet runs every manifest in this folder as a static Pod; that is how a kubeadm control plane runs.
- `grep staticPodPath` — Shows which folder kubelet watches for static Pods, in case it is not the usual one.
- `kubectl -n kube-system get pods -o wide` — Static Pods show up in the API as mirror Pods with the node name appended, such as `etcd-cka-control-plane`.

</details>

**Architecture: Helm, Kustomize, CRDs and operators**

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx; helm repo update
helm search repo ingress-nginx --versions | head
helm show values ingress-nginx/ingress-nginx > values.yaml
helm install ingress ingress-nginx/ingress-nginx -n ingress --create-namespace --version 4.13.0 -f values.yaml --set controller.replicaCount=2
helm upgrade ingress ingress-nginx/ingress-nginx -n ingress --version 4.13.1 --reuse-values
helm list -A; helm status ingress -n ingress; helm get values ingress -n ingress
helm history ingress -n ingress; helm rollback ingress 1 -n ingress
helm template ingress ingress-nginx/ingress-nginx -n ingress > rendered.yaml   # inspect without installing
helm uninstall ingress -n ingress

kubectl kustomize overlays/prod                  # render
kubectl apply -k overlays/prod; kubectl delete -k overlays/prod
# kustomization.yaml keys you will touch: resources, namespace, namePrefix, labels, images (name/newTag), patches (path + target)

kubectl get crd; kubectl get crd <name> -o yaml | less
kubectl explain <kind> --recursive | less        # works for CRD kinds too
kubectl api-resources | grep <group>
kubectl get <plural>.<group> -A                   # fully qualified when short names collide
```

<details>
<summary>Line-by-line explanation</summary>

- `helm repo add ingress-nginx` — Registers a chart repository under a local name; `repo update` downloads its latest index.
- `helm search repo ingress-nginx --versions` — Lists every chart version in the repository; `head` keeps the newest few.
- `helm show values` — Saves the chart's default values to a file you can read and edit. This is how you find the right value names.
- `helm install ingress` — Installs release `ingress` from chart version 4.13.0 into a namespace it creates. Values come from the file, and `--set` overrides one on top.
- `helm upgrade ingress` — Moves the release to a new chart version. `--reuse-values` keeps the previous values instead of starting from the chart's defaults.
- `helm list -A;` — Releases in every namespace, one release's status, and the values you supplied.
- `helm history ingress` — Every install, upgrade and rollback is a numbered revision. `rollback ingress 1` returns to revision 1, recorded as a new revision.
- `helm template ingress` — Renders the chart's manifests locally without installing, for when a task wants the YAML.
- `helm uninstall ingress` — Removes the release and the objects it created.
- `kubectl kustomize overlays/prod` — Prints what the overlay produces without applying it. Read it before you apply.
- `kubectl apply -k overlays/prod` — `-k` builds the kustomization in that folder, then applies (or deletes) the result.
- `kubectl get crd;` — Lists CustomResourceDefinitions, named `.`. The YAML shows the group, kind, versions and schema.
- `kubectl explain <kind> --recursive` — explain reads a CRD's schema too, so custom resources document themselves like built-in ones.
- `kubectl api-resources | grep <group>` — Shows the plural, short names and kind a CRD registered.
- `kubectl get <plural>.<group> -A` — The fully qualified name always works, even when two resources share a short name.

</details>

**Architecture: CSR object, kustomization.yaml and a minimal CRD**

```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: <base64 of jane.csr, one line>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
---
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: prod
namePrefix: prod-
labels:
  - pairs:
      env: prod
    includeSelectors: true
images:
  - name: nginx
    newTag: "1.27"
patches:
  - path: replicas.yaml
    target:
      kind: Deployment
      name: web
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: ["bk"]
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                schedule: { type: string }
                retainDays: { type: integer }
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: certificates.k8s.io/v1` — Every manifest starts with `apiVersion` (API group and version) and `kind`. A CSR is cluster-wide, so there is no namespace.
- `request: <base64` — The CSR file, base64-encoded on a single line.
- `signerName: kubernetes.io/kube-apiserver-client` — The built-in signer for client certificates the API server accepts for login.
- `expirationSeconds: 86400` — Asks for a certificate valid for one day.
- `- client auth` — The certificate may only authenticate a client; this signer requires that usage.
- `apiVersion: kustomize.config.k8s.io/v1beta1` — A kustomization is read by kubectl, not stored in the cluster.
- `- ../../base` — The base folder to build on. The overlay never edits it.
- `namespace: prod` — Sets the namespace on every object.
- `namePrefix: prod-` — Adds `prod-` to the front of every object's name, and updates references to those names.
- `includeSelectors: true` — `labels` adds `env: prod` to every object, and `includeSelectors: true` also writes it into selectors. A Deployment's selector cannot change after it is created, so this fails on an existing Deployment.
- `newTag: "1.27"` — Replaces the tag of every image named `nginx`. Quote it: unquoted, YAML reads 1.27 as a number and kustomize rejects it.
- `- path: replicas.yaml` — Applies the patch in `replicas.yaml` to the object `target` picks: Deployment `web`.
- `name: backups.ops.example.com` — A CRD teaches the API server a new type. Its name must be `.`.
- `scope: Namespaced` — Backups live in namespaces like Pods; `Cluster` would make them cluster-wide like nodes.
- `plural: backups` — How you name the type: the plural in URLs and `kubectl get backups`, the singular, the `kind` written in manifests, and short names like `bk`.
- `served: true` — `served` means the API offers this version. Exactly one version has `storage: true`: the one etcd stores.
- `openAPIV3Schema:` — The schema each Backup is validated against: `spec.schedule` must be a string and `spec.retainDays` an integer.

</details>

**Workloads (15%): rollouts, scheduling, autoscaling**

```bash
k rollout status deploy/web --timeout=120s
k rollout history deploy/web; k rollout history deploy/web --revision=2
k rollout undo deploy/web; k rollout undo deploy/web --to-revision=1
k rollout pause deploy/web; k rollout resume deploy/web; k rollout restart deploy/web
k scale deploy web --replicas=4; k scale sts db --replicas=3
k autoscale deploy web --min=2 --max=6 --cpu=70%; k get hpa

k taint node cka-worker dedicated=gpu:NoSchedule        # NoSchedule | PreferNoSchedule | NoExecute
k taint node cka-worker dedicated=gpu:NoSchedule-       # remove
k label node cka-worker disk=ssd; k label node cka-worker disk-
k cordon cka-worker; k uncordon cka-worker
k get pods -o wide                                      # which node did it land on
k describe pod web | grep -A10 Events                   # FailedScheduling tells you why

k get ds,job,cj -A; k get job once -o jsonpath='{.status.succeeded}'
k create job manual --from=cronjob/nightly
k get pdb; k get priorityclass; k get limitrange,resourcequota -n team-a
k describe quota -n team-a
```

<details>
<summary>Line-by-line explanation</summary>

- `k rollout status deploy/web --timeout=120s` — Waits until the rollout finishes, or 120 seconds pass. Run it after every change to a Deployment.
- `k rollout history deploy/web;` — Lists the revisions; `--revision=2` shows one revision's Pod template.
- `k rollout undo deploy/web;` — Goes back one revision, or to an exact one with `--to-revision`. Name the revision when the task names one.
- `k rollout pause` — `pause` holds several edits back so they roll out together, and `resume` starts that rollout. `restart` replaces every Pod without changing the template, for example to reload a ConfigMap.
- `k scale sts db --replicas=3` — Scales a Deployment or a StatefulSet. StatefulSet Pods are added and removed one at a time, in order, by default.
- `k autoscale deploy web` — Creates the HPA; `k get hpa` shows current CPU against the target.
- `k taint node cka-worker dedicated=gpu:NoSchedule` — A taint repels Pods that do not tolerate it. NoSchedule blocks new Pods, PreferNoSchedule only avoids the node, NoExecute also evicts running ones.
- `dedicated=gpu:NoSchedule-` — The same taint with a trailing dash removes it.
- `k label node cka-worker disk=ssd` — A node label that nodeSelector or node affinity can target; `disk-` removes it.
- `k cordon cka-worker; k uncordon` — Marks the node unschedulable (running Pods stay), then schedulable again.
- `grep -A10 Events` — `grep -A10` prints the matching line and the 10 after it: the Events, where a Pending Pod's FailedScheduling message lists why each node was rejected.
- `k get ds,job,cj -A;` — Several types in one get, comma-separated. `status.succeeded` counts the Job's Pods that finished successfully.
- `k create job manual --from=cronjob/nightly` — Runs the CronJob's template once, right now.
- `k get pdb; k get priorityclass;` — Quick looks at disruption budgets, priority classes, and the namespace's limit ranges and quotas.
- `k describe quota -n team-a` — Shows each quota's used amount next to its hard limit: the fastest way to see why a Pod was refused.

</details>

**Workloads: Pod spec skeletons (scheduling, probes, resources, config, sidecar)**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels: { app: web }
spec:
  priorityClassName: high
  serviceAccountName: app
  nodeSelector:
    disk: ssd
  tolerations:
    - key: dedicated
      operator: Equal          # or Exists (then omit value)
      value: gpu
      effect: NoSchedule
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disk, operator: In, values: [ssd] }   # In NotIn Exists DoesNotExist Gt Lt
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels: { app: web }
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels: { app: web }
  initContainers:
    - name: init-cfg
      image: busybox:1.36
      command: ["sh", "-c", "echo ready > /work/ok"]
      volumeMounts: [{ name: work, mountPath: /work }]
    - name: log-shipper              # sidecar: an init container that keeps running
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "tail -F /work/app.log"]
      volumeMounts: [{ name: work, mountPath: /work }]
  containers:
    - name: nginx
      image: nginx:1.27
      ports: [{ containerPort: 80 }]
      resources:
        requests: { cpu: 100m, memory: 64Mi }
        limits: { cpu: 200m, memory: 128Mi }
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef: { name: db, key: password }
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef: { name: app-cfg, key: LOG_LEVEL }
      envFrom:
        - configMapRef: { name: app-cfg }
      startupProbe:
        httpGet: { path: /, port: 80 }
        failureThreshold: 30
        periodSeconds: 2
      readinessProbe:
        httpGet: { path: /, port: 80 }
        initialDelaySeconds: 2
        periodSeconds: 5
      livenessProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/healthy"]
        periodSeconds: 10
        failureThreshold: 3
      volumeMounts:
        - { name: work, mountPath: /work }
        - { name: cfg, mountPath: /etc/app, readOnly: true }
  volumes:
    - name: work
      emptyDir: {}
    - name: cfg
      configMap:
        name: app-cfg
    - name: secrets
      secret:
        secretName: db
  restartPolicy: Always            # Pod-level: Always | OnFailure | Never
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: v1` — Core objects such as Pods, Services and ConfigMaps use plain `v1`; Deployments use `apps/v1`.
- `labels: { app: web }` — Labels are how Services, selectors and affinity rules find this Pod. `{ … }` is YAML's one-line map form.
- `priorityClassName: high` — Uses PriorityClass `high`: the Pod is scheduled ahead of lower-priority Pods, and may push them out.
- `serviceAccountName: app` — The identity the Pod uses against the API. Without it, the namespace's `default` ServiceAccount is used.
- `nodeSelector:` — The simplest placement rule: only nodes labeled `disk=ssd`.
- `tolerations:` — Lets the Pod onto nodes tainted `dedicated=gpu:NoSchedule`. A toleration allows a node but does not pick it, so pair it with a selector or affinity.
- `requiredDuringSchedulingIgnoredDuringExecution:` — A hard rule the scheduler must satisfy. *IgnoredDuringExecution*: running Pods stay even if the node's labels change later.
- `{ key: disk, operator: In, values: [ssd] }` — Node affinity, a more flexible nodeSelector. A node must match one of the terms (OR), and every expression inside that term (AND).
- `podAntiAffinity:` — Keeps Pods apart: no two `app=web` Pods on one node, because `topologyKey: kubernetes.io/hostname` makes each node its own domain.
- `topologySpreadConstraints:` — Spreads matching Pods so node counts differ by at most 1 (`maxSkew`). `DoNotSchedule` leaves a Pod Pending rather than break that.
- `initContainers:` — Init containers run one after another, each to completion, before the main containers start.
- `echo ready > /work/ok` — `command` replaces the image's entrypoint. `sh -c` runs the string as a shell command, here writing a file into the shared volume.
- `restartPolicy: Always` — This line makes it a sidecar: it starts before the main containers and keeps running beside them. `tail -F` follows the file, retrying until it exists.
- `containers:` — The main containers. Each needs a `name` and an `image`.
- `ports: [{ containerPort: 80 }]` — Records the port the app listens on, for people and tools to read. A Service sends traffic to its `targetPort` whether or not this is set.
- `resources:` — Requests are what the scheduler reserves; limits are the ceiling. Over its CPU limit a container is throttled, over its memory limit it is killed (OOMKilled). `100m` is a tenth of a CPU.
- `secretKeyRef: { name: db, key: password }` — One variable from one key: `DB_PASSWORD` gets key `password` of Secret `db`, already decoded.
- `configMapKeyRef:` — The same pattern for a single ConfigMap key.
- `envFrom:` — Imports every key of the ConfigMap as a variable under its own name.
- `startupProbe:` — Gives a slow app up to 30 × 2 = 60 seconds to start. The other probes wait until it succeeds.
- `readinessProbe:` — While it fails, the Pod is taken out of Service endpoints, but not restarted.
- `livenessProbe:` — After 3 failures in a row, kubelet restarts the container. An `exec` probe passes when the command exits 0, here when the file exists.
- `volumeMounts:` — Where each volume appears inside this container. The `name` must match an entry under `volumes`.
- `volumes:` — Volumes are declared once per Pod and mounted per container. `emptyDir` is scratch space that lives as long as the Pod; configMap and secret volumes show each key as a file.
- `restartPolicy: Always` — For the main containers. Deployments require Always; Job Pods use OnFailure or Never.

</details>

**Workloads: HPA (autoscaling/v2), PDB, LimitRange, ResourceQuota, CronJob**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2                 # or maxUnavailable: 1
  selector:
    matchLabels: { app: web }
---
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
    - type: Container
      default: { cpu: 200m, memory: 128Mi }
      defaultRequest: { cpu: 100m, memory: 64Mi }
      max: { cpu: "1", memory: 512Mi }
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
spec:
  hard:
    pods: "10"
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 300
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: run
              image: busybox:1.36
              command: ["sh", "-c", "date"]
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: autoscaling/v2` — Use `autoscaling/v2`: it is the version with `metrics` and `behavior`.
- `scaleTargetRef:` — The object to scale, named by apiVersion, kind and name.
- `minReplicas: 2` — The HPA keeps the replica count between the minimum and the maximum.
- `averageUtilization: 70` — Aims for average CPU use at 70% of the Pods' **requests**. Without CPU requests the HPA cannot compute a percentage.
- `stabilizationWindowSeconds: 60` — Before scaling down, the HPA uses the highest recommendation from the last 60 seconds, so a brief dip does not remove Pods. The default is 300.
- `kind: PodDisruptionBudget` — Limits planned disruptions such as drains: an eviction is refused if fewer than 2 matching Pods would be left. Set minAvailable or maxUnavailable, not both.
- `kind: LimitRange` — Per-container rules for every new Pod in its namespace.
- `default: { cpu: 200m` — `default` is the limit and `defaultRequest` the request given to a container that sets none; `max` rejects containers asking for more.
- `kind: ResourceQuota` — Caps the namespace's totals. Once a quota covers `requests.cpu` or `limits.cpu`, every new Pod must set them, or get them from a LimitRange, or it is rejected.
- `schedule: "0 2 * * *"` — 02:00 every day. Quoting is a safe habit: a schedule starting with `*`, like `*/5 * * * *`, is invalid YAML unquoted.
- `concurrencyPolicy: Forbid` — Skips a run while the previous Job is still going. `successfulJobsHistoryLimit` keeps the last 3 finished Jobs to inspect.
- `jobTemplate:` — Three nested specs: the CronJob's, the Job's in `jobTemplate`, and the Pod's in `template`. Most indentation mistakes happen here.
- `backoffLimit: 2` — The Job retries failed Pods twice, then is marked failed.
- `activeDeadlineSeconds: 300` — A hard time limit: after 300 seconds the Job's Pods are stopped and the Job fails, whatever retries are left.
- `restartPolicy: OnFailure` — Job Pods must use OnFailure or Never; Always is rejected.

</details>

**Networking (20%): Services, endpoints, DNS, Ingress, policies**

```bash
k expose deploy web --name=web-svc --port=80 --target-port=8080 --type=NodePort
k get svc web-svc -o wide; k get endpointslices -l kubernetes.io/service-name=web-svc
k get svc web-svc -o jsonpath='{.spec.ports[0].nodePort}'         # 30000-32767
k run tmp --image=busybox:1.36 --restart=Never -it --rm -- wget -qO- --timeout=2 http://web-svc.team-a.svc.cluster.local
k run tmp --image=busybox:1.36 --restart=Never -it --rm -- nslookup web-svc.team-a.svc.cluster.local
# DNS names: <svc>.<ns>.svc.cluster.local   <pod-ip-dashed>.<ns>.pod.cluster.local   <pod>.<headless-svc>.<ns>.svc.cluster.local

k -n kube-system get deploy coredns; k -n kube-system get svc kube-dns
k -n kube-system get cm coredns -o yaml                   # the Corefile
k -n kube-system logs deploy/coredns --tail=50
k -n kube-system rollout restart deploy coredns
k get pod tmp -o jsonpath='{.spec.dnsPolicy}'; cat /etc/resolv.conf   # inside a pod

k get ingressclass; k get ingress -A; k describe ingress web
curl -H 'Host: shop.example.com' http://localhost:8080/              # lab: ingress-nginx on 8080
k -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50

k get gatewayclass,gateway,httproute -A; k describe httproute web

k get netpol -n team-a; k describe netpol deny-all -n team-a
k get pods -n team-a --show-labels                        # does the podSelector match anything?

# On a node: the pod network
ip addr; ip route; cat /etc/cni/net.d/*; crictl ps
```

<details>
<summary>Line-by-line explanation</summary>

- `--type=NodePort` — Like a ClusterIP Service, plus a port from 30000-32767 opened on every node.
- `k get endpointslices -l kubernetes.io/service-name=web-svc` — `-o wide` adds the selector. EndpointSlices list the Pod IPs behind the Service, found by this label; empty means the selector matches no ready Pod.
- `{.spec.ports[0].nodePort}` — Prints the node port the Service got, when you did not choose one.
- `wget -qO- --timeout=2` — A temporary busybox Pod fetches the Service by its full DNS name. `-qO-` means quiet, print the page; `--timeout=2` gives up fast when traffic is blocked.
- `-- nslookup web-svc` — Asks cluster DNS for the name, to test DNS separately from the connection.
- `k -n kube-system get deploy coredns` — CoreDNS runs as Deployment `coredns`, behind a Service still named `kube-dns`.
- `get cm coredns -o yaml` — The CoreDNS configuration, the Corefile, lives in this ConfigMap.
- `logs deploy/coredns --tail=50` — The last 50 lines of one CoreDNS Pod's log; `deploy/` lets kubectl pick the Pod.
- `rollout restart deploy coredns` — Replaces the CoreDNS Pods, so a Corefile change takes effect at once.
- `{.spec.dnsPolicy}` — `dnsPolicy` decides which resolver a Pod gets; `ClusterFirst` is the default. Inside a Pod, `/etc/resolv.conf` shows the kube-dns IP and the search domains.
- `k get ingressclass;` — The Ingress classes (the lab has `nginx`), every Ingress, and one Ingress's rules and backends.
- `curl -H 'Host: shop.example.com'` — Sends a request to the lab's ingress controller with the host the rule expects. `-H` sets the header, so no DNS entry is needed.
- `logs deploy/ingress-nginx-controller` — The controller logs each request and errors about backends it cannot find.
- `k get gatewayclass,gateway,httproute -A` — The Gateway API objects. `describe httproute` shows whether a controller accepted the route; the lab has none.
- `k get netpol -n team-a;` — Lists NetworkPolicies and shows one in readable form, selectors included.
- `k get pods -n team-a --show-labels` — Compare these labels with the policy's selectors: a typo there silently matches nothing.
- `ip addr; ip route;` — On a node: interfaces, routes to other nodes' Pod ranges, the CNI configuration, and the running containers.

</details>

**Networking: Service, Ingress, Gateway, HTTPRoute, NetworkPolicy**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: team-a
spec:
  type: ClusterIP                 # ClusterIP | NodePort | LoadBalancer; clusterIP: None for headless
  selector:
    app: web
  ports:
    - name: http
      port: 80                    # the Service's port
      targetPort: 8080            # the container's port (number or port name)
      # nodePort: 30080           # NodePort only, 30000-32767
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: team-a
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
    - hosts: [shop.example.com]
      secretName: web-tls
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix      # Prefix | Exact | ImplementationSpecific
            backend:
              service:
                name: web-svc
                port:
                  number: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gw
  namespace: team-a
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: shop.example.com
      allowedRoutes:
        namespaces:
          from: Same              # Same | All | Selector
    - name: https
      protocol: HTTPS
      port: 443
      hostname: shop.example.com
      tls:
        mode: Terminate
        certificateRefs:
          - name: web-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web
  namespace: team-a
spec:
  parentRefs:
    - name: shared-gw
  hostnames: [shop.example.com]
  rules:
    - matches:
        - path:
            type: PathPrefix      # PathPrefix | Exact | RegularExpression
            value: /
      backendRefs:
        - name: web-svc
          port: 80
          weight: 90
        - name: web-canary
          port: 80
          weight: 10
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-policy
  namespace: team-a
spec:
  podSelector:
    matchLabels: { app: web }     # {} selects every pod in the namespace
  policyTypes: [Ingress, Egress]  # listing a type with no rules = deny all of that type
  ingress:
    - from:
        - podSelector:
            matchLabels: { app: frontend }
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: monitoring }
        - ipBlock:
            cidr: 10.0.0.0/8
            except: [10.0.1.0/24]
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels: { k8s-app: kube-dns }
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
# A podSelector and a namespaceSelector in ONE list item (no dash before the second) is AND; separate items are OR.
```

<details>
<summary>Line-by-line explanation</summary>

- `selector:` — Traffic goes to every ready Pod whose labels match. Check this first when a Service has no endpoints.
- `- name: http` — A port name is optional with one port and required with several.
- `nginx.ingress.kubernetes.io/rewrite-target: /` — An ingress-nginx annotation that rewrites the matched path to `/` before passing the request on. Annotations are controller-specific.
- `ingressClassName: nginx` — Which controller serves this Ingress. Without it, only a default class's controller picks it up.
- `tls:` — Handles HTTPS for this host, using the certificate in Secret `web-tls` from the same namespace.
- `- host: shop.example.com` — Rules match the Host header first, then the path.
- `pathType: Prefix` — Prefix matches whole path segments, so `/` matches everything; Exact matches only that path.
- `number: 80` — The backend Service and its port: the Service's `port`, not the container's.
- `gatewayClassName: nginx` — A Gateway is the entry point, like a load balancer. `gatewayClassName` names the controller that implements it.
- `listeners:` — Each listener is a port, protocol and optional hostname that routes attach to.
- `allowedRoutes:` — Which namespaces' routes may attach to this listener; `Same` means only `team-a`.
- `mode: Terminate` — The Gateway decrypts HTTPS with the certificate in Secret `web-tls` and forwards plain HTTP.
- `parentRefs:` — Attaches the route to Gateway `shared-gw` in this namespace. Add `sectionName` to pick one listener.
- `hostnames: [shop.example.com]` — The route only handles requests for this host.
- `type: PathPrefix` — A `/` prefix catches every path.
- `weight: 90` — Splits traffic by weight: 90 of every 100 requests to `web-svc`, 10 to `web-canary`. Weights are relative.
- `matchLabels: { app: web }     # {}` — The Pods this policy protects, in its own namespace only.
- `policyTypes: [Ingress, Egress]` — Once any policy selects a Pod for a direction (Ingress is incoming, Egress outgoing), only traffic that a rule allows gets through. Policies can only allow; there are no deny rules.
- `- from:` — Three peers as separate list items, so any one is allowed (OR): `app=frontend` Pods here, any Pod in `monitoring`, or addresses in 10.0.0.0/8 except one subnet.
- `kubernetes.io/metadata.name: monitoring` — Every namespace automatically carries this label with its own name, so you can select a namespace by name.
- `port: 8080` — `ports` belongs to the same rule as `from`: those peers may connect on TCP 8080 only.
- `namespaceSelector: {}` — No dash before `podSelector`, so both describe one peer (AND): `k8s-app=kube-dns` Pods in any namespace. Every egress policy needs this DNS allowance.
- `{ protocol: UDP, port: 53 }` — DNS uses UDP 53, and TCP 53 for large answers; allow both.

</details>

**Storage (10%): StorageClass, PV, PVC, mounting**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path        # lab; kubernetes.io/no-provisioner for manual PVs
reclaimPolicy: Delete                      # Delete | Retain
volumeBindingMode: WaitForFirstConsumer    # or Immediate
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-data
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]             # ReadWriteOnce | ReadOnlyMany | ReadWriteMany | ReadWriteOncePod
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/pv-data
  # local volumes need nodeAffinity:
  # local: { path: /mnt/disks/ssd1 }
  # nodeAffinity:
  #   required:
  #     nodeSelectorTerms:
  #       - matchExpressions:
  #           - { key: kubernetes.io/hostname, operator: In, values: [cka-worker] }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: team-a
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual                 # must match the PV, or omit to use the default class
  resources:
    requests:
      storage: 500Mi                       # a PV with >= this capacity binds
  # volumeName: pv-data                    # pin to one PV
---
# In a Pod:
#   volumes:
#     - name: data
#       persistentVolumeClaim:
#         claimName: data
#   containers[].volumeMounts:
#     - { name: data, mountPath: /var/lib/data }
# Check: kubectl get pv,pvc -A   STATUS Bound; a Pending PVC with WaitForFirstConsumer is normal until a Pod uses it.
# Reclaim: Retain leaves the PV Released; delete it and recreate (or clear spec.claimRef) to reuse.
```

<details>
<summary>Line-by-line explanation</summary>

- `is-default-class: "true"` — Makes this the default class for claims that name none. Only one class should carry it.
- `provisioner: rancher.io/local-path` — The plugin that creates volumes on demand. `kubernetes.io/no-provisioner` means you create the PVs by hand.
- `reclaimPolicy: Delete` — What happens to a provisioned volume when its claim is deleted: removed (Delete) or kept (Retain).
- `volumeBindingMode: WaitForFirstConsumer` — Delays binding until a Pod uses the claim, so the volume is created where the Pod is scheduled.
- `allowVolumeExpansion: true` — Lets you grow a claim later by editing its size; the provisioner must support resizing too.
- `kind: PersistentVolume` — A PV is a piece of storage at cluster level, with no namespace.
- `accessModes: [ReadWriteOnce]` — ReadWriteOnce: read-write from one node at a time. ReadOnlyMany and ReadWriteMany allow many nodes; ReadWriteOncePod allows a single Pod.
- `persistentVolumeReclaimPolicy: Retain` — When the claim is deleted, the PV and its data stay, in status Released.
- `storageClassName: manual` — A claim binds only to a PV with the same class name. No StorageClass object named `manual` has to exist.
- `hostPath:` — Storage in a folder on the node that runs the Pod. Fine for practice, not for real data.
- `kind: PersistentVolumeClaim` — A claim is a namespaced request for storage. Pods use claims, never PVs directly.
- `#       persistentVolumeClaim:` — The Pod side: a volume names the claim, which must be in the Pod's namespace, and a volumeMount puts it at a path.

</details>

**Troubleshooting order: the cluster first, then the node**

*Start with kubectl. Go to a node shell only when kubectl points there, or when the API server does not answer.*

`kubectl get` — what is not Running or Ready? → `describe and logs` — events and errors say why → `Node shell` — systemctl and journalctl for the kubelet → `crictl` — containers, even with the API down

**Troubleshooting (30%): inside the cluster, then on the node**

```bash
k get nodes; k describe node <node> | grep -A8 Conditions; k top nodes
k get pods -A --field-selector=status.phase!=Running
k get pods -A -o wide | grep -vE 'Running|Completed'
k describe pod web -n ns | tail -25                      # Events: image pull, scheduling, probes, mounts
k logs web -n ns; k logs web -c app --previous; k logs -l app=web --all-containers --tail=50
k logs deploy/web -n ns --since=10m -f
k get events -n ns --sort-by=.lastTimestamp; k events --for pod/web -n ns
k top pods -A --sort-by=memory; k top pod web --containers -n ns
k exec -it web -n ns -- sh; k exec web -n ns -- cat /etc/resolv.conf
k debug -it web -n ns --image=busybox:1.36 --target=app      # ephemeral container sharing the process namespace
k debug web -n ns -it --copy-to=web-debug --container=app -- sh   # a copy with a new command
k debug node/cka-worker -it --image=busybox:1.36              # host filesystem at /host
k get --raw '/readyz?verbose'; k get --raw '/livez?verbose'
k -n kube-system get pods -o wide; k -n kube-system logs kube-apiserver-cka-control-plane --tail=50
k -n kube-system logs kube-scheduler-cka-control-plane; k -n kube-system logs kube-controller-manager-cka-control-plane
k get svc,endpointslices -n ns; k get netpol -A
k auth can-i create pods --as=system:serviceaccount:ns:app -n ns
k get pod web -o yaml | grep -E 'image:|nodeName|serviceAccountName|phase|reason|message'

# --- On a node (lab: docker exec -it cka-control-plane bash; exam: ssh <node>, then sudo -i)
systemctl status kubelet; systemctl restart kubelet; systemctl enable --now kubelet
journalctl -u kubelet --no-pager --since '10 min ago' | tail -50
journalctl -u kubelet -f
cat /var/lib/kubelet/config.yaml                       # staticPodPath, clusterDNS, authentication
cat /etc/kubernetes/kubelet.conf                       # server URL, client certs
cat /var/lib/kubelet/kubeadm-flags.env                 # extra kubelet args
ls /etc/kubernetes/manifests/                          # static pod manifests; a typo here breaks the control plane
ls /etc/kubernetes/pki/                                # certificates

systemctl status containerd; journalctl -u containerd --no-pager | tail -30
crictl ps -a; crictl ps -a | grep -i apiserver
crictl logs <container-id>; crictl logs --tail=50 <container-id>
crictl pods; crictl images; crictl inspect <container-id>
cat /etc/crictl.yaml                                   # runtime endpoint if crictl complains

ip addr; ip route; cat /etc/cni/net.d/*                # pod network
ss -ltnp | grep -E '6443|10250|2379'                   # apiserver, kubelet, etcd listening?
df -h; free -m; top -bn1 | head -15                    # disk pressure, memory pressure
swapon --show                                          # kubelet refuses to start with swap on unless configured
cat /etc/hosts; nslookup kubernetes.default.svc.cluster.local 10.96.0.10 # DNS from the node
```

<details>
<summary>Line-by-line explanation</summary>

- `k get nodes; k describe node` — Start wide: node status, the node's conditions (Ready, MemoryPressure, DiskPressure) with reasons, and current CPU and memory use.
- `--field-selector=status.phase!=Running` — Every Pod not Running, cluster-wide. Finished Job Pods (phase Succeeded) show up too.
- `grep -vE 'Running|Completed'` — Catches what phase misses: a CrashLoopBackOff Pod is usually still phase Running. `-v` keeps the lines that do not match.
- `k describe pod web -n ns | tail -25` — The Events at the bottom of describe explain most Pod failures; `tail -25` jumps there.
- `k logs web -n ns; k logs web -c app --previous` — `-c` picks a container, `--previous` shows the crashed attempt, `-l` reads every matching Pod (10 lines each unless you set `--tail`).
- `k logs deploy/web -n ns --since=10m -f` — One Pod of the Deployment, the last 10 minutes, then keeps following (`-f`) until Ctrl+C.
- `k events --for pod/web` — Events by time; `k events --for` limits them to one object.
- `k top pods -A --sort-by=memory` — Live usage from metrics-server, biggest first; `--containers` splits a Pod into its containers.
- `k exec -it web -n ns -- sh;` — A shell in the running container, or a single command without `-it`. Everything after `--` runs in the container.
- `--target=app` — Adds a temporary debug container to the running Pod. `--target=app` lets it see the app's processes, handy when the image has no shell.
- `--copy-to=web-debug` — Makes a copy named `web-debug` with container `app`'s command replaced by `sh`, and attaches you to it (`-it`); without input, `sh` would exit at once. The original Pod is untouched.
- `k debug node/cka-worker` — A Pod on that node with the host's filesystem at `/host`: a node shell without ssh. Delete the leftover Pod afterwards.
- `k get --raw '/readyz?verbose'` — Calls the API server's health endpoints directly; `?verbose` lists each check as `[+]` or `[-]`. The quotes stop zsh from reading `?` as a file pattern.
- `logs kube-apiserver-cka-control-plane` — Control-plane components are static Pods named `-`, so their logs are a `kubectl logs` away while the API server works.
- `logs kube-scheduler-cka-control-plane` — Look here when Pods stay Pending with no events, or Deployments create no ReplicaSets.
- `k get svc,endpointslices -n ns` — For a Service problem: does it have endpoints, and is a NetworkPolicy in the way?
- `k auth can-i create pods --as=system:serviceaccount:ns:app` — For a Forbidden error: test the exact permission as the ServiceAccount the Pod uses.
- `grep -E 'image:|nodeName` — Pulls the usual suspects out of a Pod's YAML: image, node, ServiceAccount, phase and any reason or message.
- `systemctl status kubelet;` — kubelet is a systemd service: `status` shows whether it runs plus its latest log lines, `restart` restarts it, `enable --now` starts it and at every boot.
- `journalctl -u kubelet --no-pager` — kubelet's log from the last 10 minutes, printed straight out (`--no-pager`) so `tail` keeps the end, where the error usually is.
- `journalctl -u kubelet -f` — Follows kubelet's log live while you restart or change something.
- `cat /var/lib/kubelet/config.yaml` — kubelet's main configuration. A wrong value here can stop kubelet or break DNS for every Pod on the node.
- `cat /etc/kubernetes/kubelet.conf` — The kubeconfig kubelet uses to reach the API server. A wrong server address leaves the node NotReady.
- `kubeadm-flags.env` — Extra flags kubeadm wrote for kubelet; they are passed in when the service starts.
- `ls /etc/kubernetes/manifests/` — kubelet recreates a static Pod soon after its manifest changes. A broken manifest makes the component vanish, and kubelet's log says why.
- `systemctl status containerd;` — containerd is the runtime kubelet drives. If it is down, kubelet cannot run containers and the node goes NotReady.
- `crictl ps -a;` — crictl talks to containerd directly, so it works when the API server is down. `-a` includes exited containers, where a crashing component shows up.
- `crictl logs <container-id>;` — A container's log straight from the runtime: how you read a broken API server's error.
- `crictl pods; crictl images; crictl inspect` — Pod sandboxes, pulled images, and one container's full details such as mounts, command and exit code.
- `cat /etc/crictl.yaml` — If crictl cannot connect, this file (or `--runtime-endpoint`) tells it where containerd's socket is.
- `ip addr; ip route; cat /etc/cni/net.d/*` — Interfaces, routes and the CNI config. Without a valid file in `/etc/cni/net.d` the node stays NotReady.
- `ss -ltnp` — Lists listening TCP ports with their process: 6443 is the API server, 10250 kubelet, 2379 etcd.
- `df -h; free -m; top -bn1` — Disk space, memory in MB, and one snapshot of the busiest processes. A full disk causes DiskPressure and evictions.
- `swapon --show` — Prints active swap; no output means swap is off.
- `nslookup kubernetes.default.svc.cluster.local 10.96.0.10` — Asks the cluster DNS Service (10.96.0.10, the usual kube-dns IP) directly from the node. Use the full name: a node does not have the cluster's search domains, so a short name like `kubernetes.default` fails there.

</details>

> [!IMPORTANT] **Before you leave any task**
> Check five things. You are on the right host, context and namespace. Names and image tags are copied from the question. The rollout has finished (`k rollout status`). Answer files are at the exact path, and `cat` shows exactly what was asked. Nothing you made for testing is left behind. Then go to the next task. This page makes the doing fast, so you have time for the checking.

| Topic | Search phrase (kubernetes.io/docs) | Page it lands on |
| --- | --- | --- |
| Deployments, rollouts, undo | deployment | Deployments |
| RBAC | rbac | Using RBAC Authorization |
| Service account tokens | service account | Configure Service Accounts for Pods |
| Client certs, CSR | certificate signing requests | Certificate Signing Requests |
| kubeadm upgrade | kubeadm upgrade | Upgrading kubeadm clusters |
| kubeadm init and join | creating a cluster with kubeadm | Creating a cluster with kubeadm |
| HA control plane | highly available kubeadm | Creating Highly Available Clusters with kubeadm |
| etcd backup and restore | etcd backup | Operating etcd clusters for Kubernetes |
| Drain a node | safely drain node | Safely Drain a Node |
| Static pods | static pod | Create static Pods |
| Helm | (helm.sh/docs) helm install, helm upgrade, helm rollback | Helm Install / Upgrade / Rollback |
| Kustomize | kustomize | Declarative Management of Kubernetes Objects Using Kustomize |
| CRDs | custom resource definitions | Extend the Kubernetes API with CustomResourceDefinitions |
| Operators | operator pattern | Operator pattern |
| CNI, CSI, CRI | container runtime interface | Container Runtime Interface (CRI), and Network Plugins for CNI |
| ConfigMaps | configmap | ConfigMaps |
| Secrets | secret | Secrets |
| Resources, requests, limits | resource management pods containers | Resource Management for Pods and Containers |
| LimitRange, ResourceQuota | limit range / resource quotas | Limit Ranges / Resource Quotas |
| nodeSelector, affinity | assign pods to nodes | Assigning Pods to Nodes |
| Taints and tolerations | taints and tolerations | Taints and Tolerations |
| Topology spread | topology spread constraints | Pod Topology Spread Constraints |
| Probes | liveness readiness startup probes | Configure Liveness, Readiness and Startup Probes |
| Init containers, sidecars | init containers / sidecar containers | Init Containers / Sidecar Containers |
| DaemonSet, Job, CronJob, StatefulSet | daemonset / job / cronjob / statefulset | The page named after each one |
| HPA | horizontalpodautoscaler walkthrough | HorizontalPodAutoscaler Walkthrough |
| PodDisruptionBudget | pod disruption budget | Specifying a Disruption Budget for your Application |
| Pod Security Admission | pod security admission | Pod Security Admission |
| Priority and preemption | pod priority preemption | Pod Priority and Preemption |
| Services | service | Service |
| DNS names | dns pod service | DNS for Services and Pods |
| CoreDNS customization | customizing dns service | Customizing DNS Service |
| Ingress | ingress | Ingress |
| Gateway API | gateway api | Gateway API (and gateway-api.sigs.k8s.io for the full spec) |
| NetworkPolicy | network policies | Network Policies |
| PersistentVolumes, access modes, reclaim | persistent volumes | Persistent Volumes |
| StorageClass | storage classes | Storage Classes |
| Volumes | volumes | Volumes |
| kubectl debug | debug running pod | Debug Running Pods |
| Node debugging, crictl | crictl | Debugging Kubernetes nodes with crictl |
| Cluster troubleshooting | troubleshooting clusters | Troubleshooting Clusters |
| Metrics, kubectl top | resource metrics pipeline | Resource metrics pipeline |
| Logging | logging architecture | Logging Architecture |
| kubectl reference | cheat sheet | kubectl Quick Reference |
| jsonpath | jsonpath | JSONPath Support |
| Multiple clusters, contexts | configure access multiple clusters | Configure Access to Multiple Clusters |

## 📝 Key Takeaways

- `$do` (`--dry-run=client -o yaml`) prints a YAML skeleton for most objects, and `k explain` fills in the rest.
- Fields that can change: `k edit`, `k set`, `k scale`. Pod fields that cannot: save the YAML, edit it, then `k replace --force -f`.
- Troubleshoot from the outside in: kubectl first, then the node with `systemctl`, `journalctl` and `crictl`.
- Before you leave a task, check the host, context and namespace, then the end state.
- Every topic is one search phrase away on kubernetes.io. Learn the phrases, not the pages.

**📖 Official documentation:**

- [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) *(search: "cheat sheet")*
- [Kubernetes API reference (v1.37)](https://kubernetes.io/docs/reference/kubernetes-api/) *(search: "api reference")*
- [Helm commands](https://helm.sh/docs/helm/) *(search: "helm")*
- [Gateway API reference](https://gateway-api.sigs.k8s.io/reference/spec/) *(search: "httproute")*

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 6: Exam preparation*
