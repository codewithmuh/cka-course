# Mock exam 2

> ⏱️ 120 minutes · 17 tasks · Pass mark: 66%

A second full-length rehearsal with new scenarios: certificates for a user, Helm upgrades, generators, egress policies, canary routes, broken claims and a drain that a disruption budget blocks.

## Tasks

### Task 1: Access for a new developer

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 9 min |

**Question:**

Switch to the lab cluster with `kubectl config use-context kind-cka`. User `m2-dana` and an automation account both need to work in namespace `m2-dev`. The user's private key and certificate signing request are at `/tmp/cka/m2-dana.key` and `/tmp/cka/m2-dana.csr`. (1) Create a CertificateSigningRequest named `m2-dana` from that file with signer `kubernetes.io/kube-apiserver-client` and usage `client auth`, approve it, and save the issued certificate in PEM form to `/tmp/cka/m2-dana.crt`. (2) Create a ServiceAccount `ops-bot` in `m2-dev`. (3) Create a Role `dev-operator` in `m2-dev` that allows `get`, `list`, `watch` and `delete` on Pods and `get`, `list`, `watch`, `update` and `patch` on Deployments, and a single RoleBinding `dev-operators` that grants it to both `m2-dana` and `ops-bot`. Neither may create Pods.

<details>
<summary>💡 Hints</summary>

- spec.request is the CSR file base64-encoded on one line; the kubernetes.io page 'Certificates and Certificate Signing Requests' has a complete example (search 'normal user').
- kubectl create rolebinding accepts --user and --serviceaccount together, which gives one binding with two subjects.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: m2-dana
spec:
  request: $(base64 < /tmp/cka/m2-dana.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF
kubectl certificate approve m2-dana
for i in $(seq 1 15); do
  [ -n "$(kubectl get csr m2-dana -o jsonpath='{.status.certificate}')" ] && break
  sleep 2
done
kubectl get csr m2-dana -o jsonpath='{.status.certificate}' | base64 -d > /tmp/cka/m2-dana.crt
kubectl -n m2-dev create serviceaccount ops-bot
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-operator
  namespace: m2-dev
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "update", "patch"]
EOF
kubectl -n m2-dev create rolebinding dev-operators --role=dev-operator --user=m2-dana --serviceaccount=m2-dev:ops-bot
kubectl -n m2-dev auth can-i delete pods --as=m2-dana
```

**Explanation:**

- `cat <<EOF | kubectl apply -f -` — This heredoc is unquoted (`EOF`, not `'EOF'`) on purpose: the shell then runs the `$( … )` inside before kubectl sees the YAML.
- `request: $(base64` — Base64-encodes the CSR file and deletes the newlines with `tr`, so the request is one line. This works with GNU and macOS base64 alike.
- `signerName: kubernetes.io/kube-apiserver-client` — The built-in signer for client certificates the API server accepts.
- `- client auth` — The usage the question asks for; this signer requires it.
- `kubectl certificate approve m2-dana` — Approves the request, and the signer then issues the certificate.
- `for i in $(seq 1 15); do` — Waits up to 30 seconds for `status.certificate` to be filled in.
- `base64 -d > /tmp/cka/m2-dana.crt` — The certificate is stored base64-encoded in the CSR's status; decoding gives the PEM file.
- `create serviceaccount ops-bot` — The automation account.
- `apiGroups: [""]` — `""` is the core API group, where Pods live: four verbs and no `create`.
- `apiGroups: ["apps"]` — Deployments, in the `apps` group, with the five verbs asked for.
- `create rolebinding dev-operators` — One binding, two subjects: the user by name and the ServiceAccount as `namespace:name`.
- `auth can-i delete pods --as=m2-dana` — Checks the user's permission without her kubeconfig. Should print yes.

**Notes:** The CSR object carries the PEM request base64-encoded (`base64 -w0` on Linux, or pipe through `tr -d '\n'`). After `kubectl certificate approve` the signer fills `status.certificate`, again base64-encoded, so decode it before saving. The user's name in RBAC is the certificate's CN, its groups are the O fields. To use the identity, `kubectl config set-credentials m2-dana --client-certificate=… --client-key=… --embed-certs` plus a context; graders usually check the CSR, the file and `auth can-i`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-dev
crt=/tmp/cka/m2-dana.crt
[ "$(kubectl get csr m2-dana -o jsonpath='{.spec.signerName}' 2>/dev/null)" = "kubernetes.io/kube-apiserver-client" ] && p "csr m2-dana uses the kube-apiserver-client signer" || f "csr m2-dana uses the kube-apiserver-client signer"
case " $(kubectl get csr m2-dana -o jsonpath='{.status.conditions[*].type}' 2>/dev/null) " in *" Approved "*) p "csr approved";; *) f "csr approved";; esac
issued=$(kubectl get csr m2-dana -o jsonpath='{.status.certificate}' 2>/dev/null)
[ -n "$issued" ] && [ "$(echo "$issued" | base64 -d 2>/dev/null)" = "$(cat $crt 2>/dev/null)" ] && p "certificate file holds the issued certificate" || f "certificate file holds the issued certificate"
openssl x509 -in $crt -noout -subject 2>/dev/null | grep -Eq 'CN ?= ?m2-dana' && p "certificate subject CN=m2-dana" || f "certificate subject CN=m2-dana"
kubectl -n $ns get sa ops-bot >/dev/null 2>&1 && p "serviceaccount ops-bot exists" || f "serviceaccount ops-bot exists"
subj="$(kubectl -n $ns get rolebinding dev-operators -o jsonpath='{range .subjects[*]}{.kind}:{.name} {end}' 2>/dev/null)"
case " $subj" in *" User:m2-dana "*) p "binding includes user m2-dana";; *) f "binding includes user m2-dana";; esac
case " $subj" in *" ServiceAccount:ops-bot "*) p "binding includes serviceaccount ops-bot";; *) f "binding includes serviceaccount ops-bot";; esac
for who in m2-dana system:serviceaccount:m2-dev:ops-bot; do
  ok=1
  for v in get list watch delete; do [ "$(kubectl -n $ns auth can-i $v pods --as=$who 2>/dev/null)" = "yes" ] || ok=0; done
  for v in get list watch update patch; do [ "$(kubectl -n $ns auth can-i $v deployments.apps --as=$who 2>/dev/null)" = "yes" ] || ok=0; done
  [ $ok = 1 ] && p "$who has the required permissions" || f "$who has the required permissions"
  [ "$(kubectl -n $ns auth can-i create pods --as=$who 2>/dev/null)" = "no" ] && p "$who cannot create pods" || f "$who cannot create pods"
done
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 2: Return to a named release

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Deployment `ledger` in namespace `m2-ledger` has been released several times and the current release is not wanted. Find the revision whose change cause is `release 1.1 on nginx 1.27`, write that revision number to `/tmp/cka/m2-02-revision.txt`, and roll the Deployment back to exactly that revision. All 3 replicas must be available when you finish.

<details>
<summary>💡 Hints</summary>

- kubectl rollout history lists revisions with their CHANGE-CAUSE; --revision=N shows the template of one.
- rollout undo without --to-revision goes one step back. Here that happens to be the right release, but name the revision with --to-revision so the answer does not depend on luck.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n m2-ledger rollout history deploy/ledger
rev=$(kubectl -n m2-ledger rollout history deploy/ledger | awk '/release 1.1 on nginx 1.27/ {print $1}')
echo "$rev" > /tmp/cka/m2-02-revision.txt
kubectl -n m2-ledger rollout undo deploy/ledger --to-revision="$rev"
kubectl -n m2-ledger rollout status deploy/ledger --timeout=120s
```

**Explanation:**

- `kubectl -n m2-ledger rollout history deploy/ledger` — Lists the revisions with their CHANGE-CAUSE.
- `rev=$(` — awk finds the line with the wanted change cause and prints its first column, the revision number. `$( … )` stores that in `rev`.
- `echo "$rev" >` — Writes the number to the answer file.
- `rollout undo deploy/ledger --to-revision=` — Rolls back to exactly that revision instead of just the previous one.
- `rollout status deploy/ledger` — Waits until all 3 replicas run nginx 1.27 again.

**Notes:** History here shows revisions 1, 2 and 3; plain `rollout undo` would land on revision 2 by luck only because it is the previous one, so name it. After the undo, the old revision 2 reappears as revision 4 with the same change cause, and revision 2 disappears from the list. The grader reads the file, the live image and the available count.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-ledger
[ "$(tr -d '[:space:]' < /tmp/cka/m2-02-revision.txt 2>/dev/null)" = "2" ] && p "revision file says 2" || f "revision file says 2"
[ "$(kubectl -n $ns get deploy ledger -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)" = "nginx:1.27" ] && p "image back to nginx:1.27" || f "image back to nginx:1.27"
[ "$(kubectl -n $ns get deploy ledger -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "3" ] && p "3 pods available" || f "3 pods available"
[ "$(kubectl -n $ns get deploy ledger -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)" = "3" ] && p "rollout complete" || f "rollout complete"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 3: One host, two backends

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

Namespace `m2-portal` has two Services, `portal` and `static`, both on port `80`. Create an Ingress named `portal` with IngressClass `nginx` for host `m2-portal.local`: requests whose path starts with `/static` go to Service `static`, every other request goes to Service `portal`. Through the lab's controller, `curl -s -H 'Host: m2-portal.local' localhost:8080/static/index.html` must return the static page and `curl -s -H 'Host: m2-portal.local' localhost:8080/hostname` the name of a `portal` Pod.

<details>
<summary>💡 Hints</summary>

- One rule, two paths, both pathType Prefix. kubectl create ingress takes --rule twice: 'm2-portal.local/static*=static:80' and 'm2-portal.local/*=portal:80'.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal
  namespace: m2-portal
spec:
  ingressClassName: nginx
  rules:
    - host: m2-portal.local
      http:
        paths:
          - path: /static
            pathType: Prefix
            backend:
              service:
                name: static
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: portal
                port:
                  number: 80
EOF
for i in $(seq 1 15); do
  curl -s -H 'Host: m2-portal.local' http://localhost:8080/static/index.html | grep -q 'm2 static assets' && break
  sleep 2
done
curl -s -H 'Host: m2-portal.local' http://localhost:8080/hostname; echo
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `- path: /static` — First path: `/static` and anything under it go to Service `static`.
- `- path: /` — Second path: everything else to `portal`. The longest matching prefix wins, so the order does not matter.
- `for i in $(seq 1 15); do` — Retries until the controller serves the static page.
- `http://localhost:8080/hostname; echo` — Should print a portal Pod's name; `echo` adds a newline.

**Notes:** With `Prefix` the longest matching path wins, so the order of the two paths does not matter. `Prefix` matches whole path segments: `/static` matches `/static` and `/static/…` but not `/staticfiles`. The backends receive the full original path; no rewrite is needed because nginx serves the files from a `static/` directory.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-portal
g="kubectl -n $ns get ingress portal -o jsonpath"
[ "$($g='{.spec.ingressClassName}' 2>/dev/null)" = "nginx" ] && p "ingressClassName nginx" || f "ingressClassName nginx"
[ "$($g='{.spec.rules[0].host}' 2>/dev/null)" = "m2-portal.local" ] && p "host m2-portal.local" || f "host m2-portal.local"
[ "$($g='{.spec.rules[0].http.paths[?(@.backend.service.name=="static")].path}' 2>/dev/null)" = "/static" ] && p "/static goes to static" || f "/static goes to static"
[ "$($g='{.spec.rules[0].http.paths[?(@.backend.service.name=="portal")].path}' 2>/dev/null)" = "/" ] && p "/ goes to portal" || f "/ goes to portal"
ok=0
for i in $(seq 1 15); do
  curl -s -m 5 -H 'Host: m2-portal.local' http://localhost:8080/static/index.html 2>/dev/null | grep -q 'm2 static assets' && { ok=1; break; }
  sleep 2
done
[ $ok = 1 ] && p "/static/index.html served by static" || f "/static/index.html served by static"
case "$(curl -s -m 5 -H 'Host: m2-portal.local' http://localhost:8080/hostname 2>/dev/null)" in portal-*) p "/hostname served by portal";; *) f "/hostname served by portal";; esac
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 4: A sync job that keeps crashing

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 8% |
| **Time** | 7 min |

**Question:**

The Pods of Deployment `token-sync` in namespace `m2-sync` keep crashing. Find the cause and fix the Deployment so that both replicas run without restarts. The Secret `api-token` holds the correct data and must not be changed.

<details>
<summary>💡 Hints</summary>

- kubectl logs on a crashing Pod tells you what the program looked for; kubectl get deploy token-sync -o yaml shows how the Secret is mounted.

</details>

<details>
<summary>✅ Solution</summary>

```bash
pod=$(kubectl -n m2-sync get pods -l app=token-sync -o jsonpath='{.items[0].metadata.name}')
kubectl -n m2-sync logs "$pod" --previous 2>/dev/null || kubectl -n m2-sync logs "$pod"
kubectl -n m2-sync get deploy token-sync -o jsonpath='{.spec.template.spec.volumes[0].secret}'; echo
kubectl -n m2-sync patch deploy token-sync --type=json -p='[{"op":"replace","path":"/spec/template/spec/volumes/0/secret/items/0/path","value":"token"}]'
kubectl -n m2-sync rollout status deploy/token-sync --timeout=120s
```

**Explanation:**

- `pod=$(` — Stores the first Pod's name in `pod`.
- `logs "$pod" --previous` — The crashed attempt's log, or the current one if there was no restart yet. It reports `/etc/token/token` missing.
- `{.spec.template.spec.volumes[0].secret}` — Shows the Secret volume: its `items` maps key `token` to file `token.txt`, not `token`.
- `patch deploy token-sync --type=json` — A JSON patch changes that file path to `token`, the name the program expects. The Secret is untouched.
- `rollout status deploy/token-sync` — New Pods find the file and stay up.

**Notes:** The log says */etc/token/token not found*; the volume uses `items` to project key `token` as file `token.txt`. Changing the path to `token` (or removing `items` so every key becomes a file under its own name) fixes it. Changing the program's command would also work but is not what the question allows you to touch first: fix the wiring, not the app.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-sync
[ "$(kubectl -n $ns get secret api-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)" = "tok-4f9a2c7e" ] && p "secret unchanged" || f "secret unchanged"
[ "$(kubectl -n $ns get deploy token-sync -o jsonpath='{.spec.template.spec.volumes[0].secret.secretName}' 2>/dev/null)" = "api-token" ] && p "deployment still mounts api-token" || f "deployment still mounts api-token"
for i in $(seq 1 20); do [ "$(kubectl -n $ns get pods -l app=token-sync --no-headers 2>/dev/null | grep -vc Terminating)" = "2" ] && ! kubectl -n $ns get pods -l app=token-sync --no-headers 2>/dev/null | grep -q Terminating && break; sleep 2; done
[ "$(kubectl -n $ns get deploy token-sync -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
r=$(kubectl -n $ns get pods -l app=token-sync -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' 2>/dev/null | xargs -n1 2>/dev/null | sort -n | tail -1)
[ "$r" = "0" ] && p "no restarts on current pods" || f "no restarts on current pods (max $r)"
kubectl -n $ns logs deploy/token-sync 2>/dev/null | grep -q 'token loaded' && p "application loaded its token" || f "application loaded its token"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 5: Snapshot etcd and check it

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Save a snapshot of the cluster's etcd to `/var/lib/etcd/m2-snapshot.db` on the control plane node. etcd serves on `https://127.0.0.1:2379` with the certificates under `/etc/kubernetes/pki/etcd/`. Then check the snapshot with `etcdutl` and write its status in table form to `/tmp/cka/m2-05-status.txt`. *Lab note:* on kind both tools exist only inside the etcd Pod, so run them with `kubectl -n kube-system exec etcd-cka-control-plane -- …`; on the exam you would `ssh` to the control plane node.

<details>
<summary>💡 Hints</summary>

- etcdctl snapshot save needs --endpoints, --cacert, --cert and --key; etcdutl snapshot status needs only the file and -w table.
- Redirect the output of the kubectl exec on your own machine to write the status file.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n kube-system exec etcd-cka-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /var/lib/etcd/m2-snapshot.db
kubectl -n kube-system exec etcd-cka-control-plane -- etcdutl snapshot status /var/lib/etcd/m2-snapshot.db -w table > /tmp/cka/m2-05-status.txt
cat /tmp/cka/m2-05-status.txt
```

**Explanation:**

- `snapshot save /var/lib/etcd/m2-snapshot.db` — etcdctl inside the etcd Pod, with the endpoint and certificate flags, writes the snapshot to a folder shared with the node.
- `etcdutl snapshot status` — Reads the snapshot offline; `-w table` prints hash, revision, key count and size as a table. The `>` runs on your machine, so the file lands in your `/tmp/cka`.
- `cat /tmp/cka/m2-05-status.txt` — Checks the table is in the file.

**Notes:** Since etcd 3.5 the offline commands (`snapshot status`, `snapshot restore`) belong to `etcdutl`; `etcdctl snapshot status` is gone in 3.6. The status table shows the hash, revision, key count and size, which is how you prove a backup is readable before you need it. Take the certificate paths from `/etc/kubernetes/manifests/etcd.yaml` rather than memory.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
docker exec cka-control-plane test -s /var/lib/etcd/m2-snapshot.db 2>/dev/null && p "snapshot file exists on the node" || f "snapshot file exists on the node"
row=$(kubectl -n kube-system exec etcd-cka-control-plane -- etcdutl snapshot status /var/lib/etcd/m2-snapshot.db -w table 2>/dev/null | grep -E '^\| *[0-9a-f]+ *\|' | head -1)
[ -n "$row" ] && p "snapshot is readable" || f "snapshot is readable"
[ -n "$row" ] && grep -qF "$row" /tmp/cka/m2-05-status.txt 2>/dev/null && p "status file holds this snapshot's status table" || f "status file holds this snapshot's status table"
grep -q 'REVISION' /tmp/cka/m2-05-status.txt 2>/dev/null && p "status file is in table form" || f "status file is in table form"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 6: Lock down a reporter's outbound traffic

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

In namespace `m2-net`, Pods labeled `app=reporter` may open connections only to Pods labeled `app=db` in the same namespace on TCP port `8080`, and to DNS on port `53` (UDP and TCP) so they can still resolve Service names. Create a NetworkPolicy named `reporter-egress` that enforces this. Do not restrict inbound traffic, and do not affect any other Pod.

<details>
<summary>💡 Hints</summary>

- policyTypes [Egress] on podSelector app=reporter; one egress rule to app=db on 8080, one rule with ports 53/UDP and 53/TCP.
- Without the DNS rule, wget http://db:8080 fails at name resolution even though the db rule is right.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: reporter-egress
  namespace: m2-net
spec:
  podSelector:
    matchLabels:
      app: reporter
  policyTypes: ["Egress"]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: db
      ports:
        - protocol: TCP
          port: 8080
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF
sleep 3
kubectl -n m2-net exec deploy/reporter -- wget -qO- -T 3 http://db:8080/hostname
kubectl -n m2-net exec deploy/reporter -- wget -qO- -T 3 http://web:8080/hostname || echo "web is blocked, as required"
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `podSelector:` — The policy applies only to Pods labeled `app=reporter`.
- `policyTypes: ["Egress"]` — Restricts outbound traffic only; inbound stays open.
- `- to:` — Rule one: to Pods labeled `app=db` in this namespace, on TCP 8080.
- `- ports:` — Rule two: port 53 over UDP and TCP to any destination (no `to`), so DNS lookups still work.
- `http://db:8080/hostname` — Should print the db Pod's name, which proves both DNS and the db rule work.
- `http://web:8080/hostname || echo` — Should time out, because web is not allowed.

**Notes:** Egress policies break DNS first: the Pod resolves names through the `kube-dns` Service, so allow port 53 explicitly. A rule with `ports` and no `to` allows those ports to any destination; tighten it with a `namespaceSelector` for `kubernetes.io/metadata.name: kube-system` plus a `podSelector` for `k8s-app: kube-dns` if the question asks for it. Leaving `Ingress` out of `policyTypes` keeps inbound traffic open.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-net
n="kubectl -n $ns get netpol reporter-egress -o jsonpath"
kubectl -n $ns get netpol reporter-egress >/dev/null 2>&1 && p "networkpolicy reporter-egress exists" || f "networkpolicy reporter-egress exists"
[ "$($n='{.spec.podSelector.matchLabels.app}' 2>/dev/null)" = "reporter" ] && p "selects app=reporter" || f "selects app=reporter"
pt="$($n='{.spec.policyTypes[*]}' 2>/dev/null)"
case " $pt " in *" Egress "*) p "policyTypes includes Egress";; *) f "policyTypes includes Egress";; esac
case " $pt " in *" Ingress "*) f "ingress left alone";; *) p "ingress left alone";; esac
case " $($n='{.spec.egress[*].to[*].podSelector.matchLabels.app}' 2>/dev/null) " in *" db "*) p "egress to app=db";; *) f "egress to app=db";; esac
case " $($n='{.spec.egress[*].ports[*].port}' 2>/dev/null) " in *" 8080 "*) p "port 8080 allowed";; *) f "port 8080 allowed";; esac
case " $($n='{.spec.egress[*].ports[?(@.port==53)].protocol}' 2>/dev/null) " in *" UDP "*) p "DNS over UDP allowed";; *) f "DNS over UDP allowed";; esac
ok=0
for i in 1 2 3 4 5; do
  case "$(kubectl -n $ns exec deploy/reporter -- wget -qO- -T 3 http://db:8080/hostname 2>/dev/null)" in db-*) ok=1; break;; esac
  sleep 2
done
[ $ok = 1 ] && p "reporter reaches db by name" || f "reporter reaches db by name"
kubectl -n $ns exec deploy/reporter -- wget -qO- -T 3 http://web:8080/hostname >/dev/null 2>&1 && f "reporter cannot reach web" || p "reporter cannot reach web"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 7: Pin an indexer to SSD nodes

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

Label node `cka-worker` with `m2-disk=ssd`. Then create a Deployment `indexer` in namespace `m2-sched` with 2 replicas and image `nginx:1.27` whose Pods use a **required node affinity** rule (not a `nodeSelector`) so that they only ever run on nodes labeled `m2-disk=ssd`. Both Pods must be running on `cka-worker`.

<details>
<summary>💡 Hints</summary>

- affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[].matchExpressions with operator In.
- Search 'assign pods nodes using node affinity' on kubernetes.io for a YAML you can copy.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl label node cka-worker m2-disk=ssd --overwrite
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: indexer
  namespace: m2-sched
spec:
  replicas: 2
  selector:
    matchLabels:
      app: indexer
  template:
    metadata:
      labels:
        app: indexer
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: m2-disk
                    operator: In
                    values: ["ssd"]
      containers:
        - name: nginx
          image: nginx:1.27
EOF
kubectl -n m2-sched rollout status deploy/indexer --timeout=120s
kubectl -n m2-sched get pods -o wide
```

**Explanation:**

- `label node cka-worker m2-disk=ssd` — Labels the node; `--overwrite` makes the command safe to repeat.
- `requiredDuringSchedulingIgnoredDuringExecution:` — A hard rule: the scheduler places these Pods only on matching nodes.
- `- key: m2-disk` — Matches nodes whose `m2-disk` label is one of the listed values, here `ssd`.
- `rollout status deploy/indexer` — Waits until both Pods are scheduled and running.
- `get pods -o wide` — NODE should read `cka-worker` for both.

**Notes:** `IgnoredDuringExecution` means removing the label later does not evict running Pods; only new Pods are affected. Several `nodeSelectorTerms` are ORed, several `matchExpressions` inside one term are ANDed. `preferredDuringScheduling…` would be a soft rule with a weight, which the question does not want.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-sched
d="kubectl -n $ns get deploy indexer -o jsonpath"
[ "$(kubectl get node cka-worker -o jsonpath='{.metadata.labels.m2-disk}' 2>/dev/null)" = "ssd" ] && p "cka-worker labeled m2-disk=ssd" || f "cka-worker labeled m2-disk=ssd"
t='{.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]'
[ "$($d="$t.key}" 2>/dev/null)" = "m2-disk" ] && p "required affinity on key m2-disk" || f "required affinity on key m2-disk"
[ "$($d="$t.operator}" 2>/dev/null)" = "In" ] && p "operator In" || f "operator In"
[ "$($d="$t.values[0]}" 2>/dev/null)" = "ssd" ] && p "value ssd" || f "value ssd"
[ -z "$($d='{.spec.template.spec.nodeSelector}' 2>/dev/null)" ] && p "no nodeSelector used" || f "no nodeSelector used"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
n=$(kubectl -n $ns get pods -l app=indexer --field-selector=status.phase=Running -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null | xargs -n1 2>/dev/null | grep -c '^cka-worker$')
[ "$n" = "2" ] && p "both pods on cka-worker" || f "both pods on cka-worker (got $n)"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 8: Count server errors across replicas

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 7% |
| **Time** | 5 min |

**Question:**

Deployment `edge` in namespace `m2-edge` runs several replicas, each logging one line per request. Count the log lines that contain `status=500` across the **complete** logs of all its Pods and write only that number to `/tmp/cka/m2-08-count.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl logs deploy/edge reads one Pod only. kubectl logs -l app=edge reads all of them, but with a selector it prints only the last 10 lines of each unless you pass --tail=-1.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n m2-edge logs -l app=edge --tail=-1 --prefix | grep 'status=500'
kubectl -n m2-edge logs -l app=edge --tail=-1 | grep -c 'status=500' > /tmp/cka/m2-08-count.txt
cat /tmp/cka/m2-08-count.txt
```

**Explanation:**

- `--tail=-1 --prefix | grep` — Every line from every edge Pod (`--tail=-1`), each prefixed with its Pod name, filtered to the 500s. A look before you count.
- `grep -c 'status=500' >` — `grep -c` prints how many lines match instead of the lines, and that number goes into the file.
- `cat /tmp/cka/m2-08-count.txt` — Shows the count.

**Notes:** Two traps in one line. `kubectl logs deploy/edge` silently picks a single Pod, so you would count half. `kubectl logs -l …` covers every Pod but defaults to `--tail=10` per Pod when a selector is used, so early lines are dropped. `--tail=-1` means everything; `--prefix` shows which Pod each line came from.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-edge
want=0
for pod in $(kubectl -n $ns get pods -l app=edge --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  c=$(kubectl -n $ns logs $pod 2>/dev/null | grep -c 'status=500')
  want=$((want + c))
done
[ "$want" -gt 0 ] && p "edge pods are logging" || f "edge pods are logging"
[ "$(tr -d '[:space:]' < /tmp/cka/m2-08-count.txt 2>/dev/null)" = "$want" ] && p "count file holds $want" || f "count file holds $want"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 9: Upgrade a Helm release

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

Release `m2-podinfo` in namespace `m2-helm` was installed from chart `podinfo/podinfo` (repository `https://stefanprodan.github.io/podinfo`). Upgrade it to chart version `6.9.1` and, in the same upgrade, set the chart value `ui.message` to `m2 ready` and `replicaCount` to `2`. Do not uninstall the release. When you finish, the release history must show the upgrade and both Pods must be Ready.

<details>
<summary>💡 Hints</summary>

- helm list -n m2-helm and helm history m2-podinfo -n m2-helm show what is installed now.
- helm upgrade   --version … --set …; add --reuse-values if earlier overrides must survive.

</details>

<details>
<summary>✅ Solution</summary>

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo --force-update
helm repo update podinfo
helm -n m2-helm list
helm upgrade m2-podinfo podinfo/podinfo --version 6.9.1 --namespace m2-helm --reuse-values --set ui.message="m2 ready" --set replicaCount=2 --wait --timeout 5m
helm -n m2-helm history m2-podinfo
```

**Explanation:**

- `helm repo add podinfo` — Makes sure the repository is registered; `--force-update` is safe if it already is.
- `helm repo update podinfo` — Refreshes the index so version 6.9.1 is known.
- `helm -n m2-helm list` — Shows the current chart version and revision before you change anything.
- `helm upgrade m2-podinfo` — Upgrades the same release to 6.9.1. `--reuse-values` keeps earlier settings, each `--set` changes one value (quoted for the space), and `--wait` blocks until Pods are Ready.
- `history m2-podinfo` — Revision 2 should be the upgrade, with status deployed.

**Notes:** `helm upgrade` without `--reuse-values` starts from the new chart's defaults plus whatever you pass on this command line; with it, earlier `--set` values are kept. Quote values with spaces. If an upgrade goes wrong, `helm rollback m2-podinfo 1 -n m2-helm` returns to the first revision. `helm get values m2-podinfo -n m2-helm` shows the user-supplied values the grader is likely to read.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-helm
hl=$(helm -n $ns list -o json 2>/dev/null)
echo "$hl" | grep -q '"chart":"podinfo-6.9.1"' && p "release runs chart podinfo-6.9.1" || f "release runs chart podinfo-6.9.1"
echo "$hl" | grep -q '"status":"deployed"' && p "status deployed" || f "status deployed"
rev=$(echo "$hl" | grep -o '"revision":"\{0,1\}[0-9]*' | grep -o '[0-9]*$')
[ -n "$rev" ] && [ "$rev" -ge 2 ] && p "history shows an upgrade (revision $rev)" || f "history shows an upgrade"
d="kubectl -n $ns get deploy m2-podinfo -o jsonpath"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "2 replicas" || f "2 replicas"
[ "$($d='{.spec.template.spec.containers[0].env[?(@.name=="PODINFO_UI_MESSAGE")].value}' 2>/dev/null)" = "m2 ready" ] && p "ui.message is m2 ready" || f "ui.message is m2 ready"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 10: Canary routing with an HTTPRoute

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Gateway `m2-gateway` in namespace `m2-gw` has two listeners, `web` and `admin`. Create an HTTPRoute named `checkout` in that namespace, attached **only** to listener `web`, for hostname `checkout.m2.local`. Requests that carry the header `x-canary: true` must go only to Service `checkout-v2` on port `80`. All other requests are split by weight: 80 to `checkout-v1` port `80` and 20 to `checkout-v2` port `80`. The lab has no Gateway controller, so only the HTTPRoute object is graded.

<details>
<summary>💡 Hints</summary>

- parentRefs takes sectionName to pick a listener. Header matches live under rules[].matches[].headers; weights under rules[].backendRefs[].weight.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: checkout
  namespace: m2-gw
spec:
  parentRefs:
    - name: m2-gateway
      sectionName: web
  hostnames:
    - checkout.m2.local
  rules:
    - matches:
        - headers:
            - name: x-canary
              value: "true"
      backendRefs:
        - name: checkout-v2
          port: 80
    - backendRefs:
        - name: checkout-v1
          port: 80
          weight: 80
        - name: checkout-v2
          port: 80
          weight: 20
EOF
kubectl -n m2-gw get httproute checkout -o yaml | sed -n '/^spec:/,/^status:/p'
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `sectionName: web` — Attaches to the Gateway's listener named `web` only, not `admin`.
- `- checkout.m2.local` — The host this route serves.
- `- headers:` — Rule one matches requests carrying header `x-canary: true` and sends them to v2 only.
- `value: "true"` — Quoted, because the field is a string; an unquoted `true` is a YAML boolean the API rejects.
- `- backendRefs:` — Rule two has no `matches`, so it takes every other request and splits it 80 to 20 by `weight`.
- `sed -n '/^spec:/,/^status:/p'` — Prints only the stored `spec`, from the `spec:` line to the `status:` line, so you can compare it with the question.

**Notes:** A rule without `matches` matches every request (path prefix `/`), and the more specific header rule takes precedence over it. Quote `"true"`: an unquoted YAML boolean is rejected because header values are strings. Weights are relative, so 4 and 1 would split traffic the same way as 80 and 20, but write what the question asks.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-gw
r="kubectl -n $ns get httproute checkout -o jsonpath"
kubectl -n $ns get httproute checkout >/dev/null 2>&1 && p "httproute checkout exists" || f "httproute checkout exists"
[ "$($r='{.spec.parentRefs[*].name}' 2>/dev/null)" = "m2-gateway" ] && p "single parent m2-gateway" || f "single parent m2-gateway"
[ "$($r='{.spec.parentRefs[0].sectionName}' 2>/dev/null)" = "web" ] && p "attached to listener web" || f "attached to listener web"
case " $($r='{.spec.hostnames[*]}' 2>/dev/null) " in *" checkout.m2.local "*) p "hostname checkout.m2.local";; *) f "hostname checkout.m2.local";; esac
rules=$($r='{range .spec.rules[*]}{.matches[*].headers[*].name}={.matches[*].headers[*].value}|{range .backendRefs[*]}{.name}:{.port}:{.weight},{end}{"\n"}{end}' 2>/dev/null)
echo "$rules" | grep -Eq '^x-canary=true\|checkout-v2:80:[0-9]*,$' && p "x-canary: true goes only to checkout-v2:80" || f "x-canary: true goes only to checkout-v2:80"
echo "$rules" | grep -v 'x-canary' | grep 'checkout-v1:80:80,' | grep -q 'checkout-v2:80:20,' && p "other traffic split 80/20" || f "other traffic split 80/20"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 11: An archiver that never starts

| Detail | Value |
| --- | --- |
| **Domain** | storage |
| **Weight** | 8% |
| **Time** | 7 min |

**Question:**

The Pod of Deployment `archiver` in namespace `m2-store` has been `Pending` since it was created. It is meant to keep its data on the existing PersistentVolume `m2-archive-pv` through claim `archive`. Fix the problem **without changing the PersistentVolume**, so that claim `archive` is `Bound` to `m2-archive-pv` and the archiver Pod is `Running` with the claim mounted at `/archive`.

<details>
<summary>💡 Hints</summary>

- kubectl describe pvc archive -n m2-store, then compare its access modes, size and class with kubectl get pv m2-archive-pv.
- Most of a PVC's spec is immutable once created: scale the Deployment to 0, delete the claim, recreate it, scale back.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m2-store describe pvc archive | tail -5
kubectl get pv m2-archive-pv
kubectl -n m2-store scale deploy archiver --replicas=0
kubectl -n m2-store delete pvc archive --wait=true --timeout=60s
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
  namespace: m2-store
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: archive
  volumeName: m2-archive-pv
  resources:
    requests:
      storage: 300Mi
EOF
kubectl -n m2-store scale deploy archiver --replicas=1
kubectl -n m2-store rollout status deploy/archiver --timeout=120s
kubectl -n m2-store get pvc archive
```

**Explanation:**

- `describe pvc archive | tail -5` — The claim's events: no volume matches it.
- `kubectl get pv m2-archive-pv` — Compare: the PV offers 300Mi ReadWriteOnce, while the claim asks for 500Mi ReadWriteMany.
- `scale deploy archiver --replicas=0` — Stops the Pod using the claim. A claim in use by a Pod is not removed until the Pod is gone.
- `delete pvc archive` — Deletes the claim, waiting up to 60 seconds. Its access modes cannot be edited in place.
- `cat <<'EOF' | kubectl apply -f -` — Recreates the claim to fit the PV.
- `accessModes: ["ReadWriteOnce"]` — Now the same access mode as the PV.
- `volumeName: m2-archive-pv` — Pre-binds the claim to that exact PV.
- `storage: 300Mi` — No more than the PV offers. A claim may ask for less than a PV holds, never more.
- `scale deploy archiver --replicas=1` — Brings the Pod back; it now mounts the bound claim.
- `rollout status deploy/archiver` — Waits for the archiver Pod to be available.
- `get pvc archive` — STATUS should read Bound, VOLUME `m2-archive-pv`.

**Notes:** The claim asks for `ReadWriteMany` and 500Mi; the volume offers `ReadWriteOnce` and 300Mi, so the binder never pairs them. A claim binds when class, access modes and size all fit (the volume may be bigger, never smaller). `volumeName` pre-binds the claim to that exact volume, which is a good habit when the question names it. Access modes and a size decrease cannot be patched, hence the delete and recreate; `kubectl replace --force -f` does the same in one step.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-store
v="kubectl get pv m2-archive-pv -o jsonpath"
[ "$($v='{.spec.capacity.storage}/{.spec.accessModes[0]}/{.spec.persistentVolumeReclaimPolicy}/{.spec.storageClassName}' 2>/dev/null)" = "300Mi/ReadWriteOnce/Retain/archive" ] && p "pv unchanged" || f "pv unchanged"
[ "$(kubectl -n $ns get pvc archive -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && p "pvc archive Bound" || f "pvc archive Bound"
[ "$(kubectl -n $ns get pvc archive -o jsonpath='{.spec.volumeName}' 2>/dev/null)" = "m2-archive-pv" ] && p "bound to m2-archive-pv" || f "bound to m2-archive-pv"
[ "$(kubectl -n $ns get deploy archiver -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "1" ] && p "archiver pod available" || f "archiver pod available"
[ -n "$(kubectl -n $ns get deploy archiver -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="archive")].name}' 2>/dev/null)" ] && p "archiver uses claim archive" || f "archiver uses claim archive"
[ -n "$(kubectl -n $ns get deploy archiver -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/archive")].name}' 2>/dev/null)" ] && p "mounted at /archive" || f "mounted at /archive"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 12: A node port that does not answer

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 8% |
| **Time** | 6 min |

**Question:**

The orders API in namespace `m2-orders` is published on port `31780` of every node through Service `orders`, but requests to that port get no answer. Fix the Service so that `curl -s http://:31780/hostname` returns the name of an `orders` Pod. Keep the Service type and node port, and do not change the Deployment. (Test from a node: `docker exec cka-control-plane curl -s localhost:31780/hostname` in the lab, `ssh` to a node on the exam.)

<details>
<summary>💡 Hints</summary>

- kubectl get endpointslices -n m2-orders: an empty endpoint list means the selector matches no Pod. Compare it with kubectl get pods --show-labels.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n m2-orders get endpointslices -l kubernetes.io/service-name=orders
kubectl -n m2-orders get pods --show-labels
kubectl -n m2-orders patch svc orders -p '{"spec":{"selector":{"app":"orders","tier":"api"}}}'
sleep 3
ip=$(kubectl get node cka-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
docker exec cka-control-plane curl -s -m 5 http://$ip:31780/hostname; echo
```

**Explanation:**

- `get endpointslices` — No endpoints: the selector matches no Pod.
- `get pods --show-labels` — The Pods carry `app=orders`, while the Service asks for `app=order`.
- `patch svc orders` — Fixes the selector. The patch merges map keys, so both keys are written out to be sure of the result.
- `ip=$(` — Stores the control-plane node's InternalIP in `ip`.
- `docker exec cka-control-plane curl` — Calls the node port from the node itself, as the question describes; `-m 5` gives up after 5 seconds.

**Notes:** No endpoints is always a selector problem (or Pods that are not Ready): the Service selects `app=order`, the Pods carry `app=orders`. Fix the Service, not the Pods, as the question says. A strategic-merge patch on `selector` merges keys, so set every key you need. Once the endpoints appear, the node port answers on every node, including ones that run no orders Pod.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-orders
s="kubectl -n $ns get svc orders -o jsonpath"
[ "$($s='{.spec.type}' 2>/dev/null)" = "NodePort" ] && p "type NodePort" || f "type NodePort"
[ "$($s='{.spec.ports[0].nodePort}' 2>/dev/null)" = "31780" ] && p "nodePort 31780" || f "nodePort 31780"
[ "$(kubectl -n $ns get deploy orders -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)" = "orders" ] && p "deployment labels untouched" || f "deployment labels untouched"
eps=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=orders -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null | wc -w | tr -d ' ')
[ "$eps" = "2" ] && p "2 endpoints" || f "2 endpoints (got $eps)"
ip=$(kubectl get node cka-control-plane -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
ok=0
for i in 1 2 3 4 5; do
  case "$(docker exec cka-control-plane curl -s -m 3 http://$ip:31780/hostname 2>/dev/null)" in orders-*) ok=1; break;; esac
  sleep 2
done
[ $ok = 1 ] && p "node port 31780 answers from an orders pod" || f "node port 31780 answers from an orders pod"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 13: Generate settings in a staging overlay

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 7 min |

**Question:**

The Kustomize base in `/tmp/cka/m2-kustomize/base` deploys a Deployment `api` that reads its environment from a ConfigMap named `api-settings`, which the base does not contain. Create an overlay in `/tmp/cka/m2-kustomize/overlays/staging` that uses the base unchanged, places everything in namespace `m2-kz`, **generates** the ConfigMap `api-settings` with `MODE=staging` and `LOG_LEVEL=info`, and patches the `api` container to request `50m` CPU and `32Mi` memory. Apply the overlay. The running Pod must see `MODE=staging`.

<details>
<summary>💡 Hints</summary>

- configMapGenerator with literals; Kustomize appends a content hash to the name and rewrites the envFrom reference for you.
- A strategic-merge patch only needs apiVersion, kind, metadata.name and the fields you change; list it under patches.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka/m2-kustomize/overlays/staging
cat > /tmp/cka/m2-kustomize/overlays/staging/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: m2-kz
resources:
  - ../../base
configMapGenerator:
  - name: api-settings
    literals:
      - MODE=staging
      - LOG_LEVEL=info
patches:
  - path: resources.yaml
EOF
cat > /tmp/cka/m2-kustomize/overlays/staging/resources.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      containers:
        - name: api
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
EOF
kubectl kustomize /tmp/cka/m2-kustomize/overlays/staging
kubectl apply -k /tmp/cka/m2-kustomize/overlays/staging
kubectl -n m2-kz rollout status deploy/api --timeout=120s
kubectl -n m2-kz exec deploy/api -- printenv MODE
```

**Explanation:**

- `mkdir -p /tmp/cka/m2-kustomize/overlays/staging` — Creates the overlay folder.
- `cat > /tmp/cka/m2-kustomize/overlays/staging/kustomization.yaml` — Writes the overlay's kustomization file.
- `namespace: m2-kz` — Puts the Deployment and the generated ConfigMap in `m2-kz`.
- `configMapGenerator:` — Generates ConfigMap `api-settings` from these literals. Kustomize adds a hash to its name and updates the Deployment's reference to match.
- `- path: resources.yaml` — The patch file to merge into the base objects.
- `cat > /tmp/cka/m2-kustomize/overlays/staging/resources.yaml` — A strategic-merge patch: just enough to identify the Deployment and the container, plus the fields to add.
- `- name: api` — Containers are matched by name, so this changes the existing `api` container instead of adding one.
- `kubectl kustomize /tmp` — Shows the generated ConfigMap name and the patched Deployment before applying.
- `kubectl apply -k` — Builds the overlay and applies it.
- `rollout status deploy/api` — Waits for the new Pod.
- `printenv MODE` — Prints the variable inside the Pod; it should say `staging`.

**Notes:** The generated ConfigMap is called `api-settings-`, and Kustomize rewrites every reference to it, so a later change to a literal produces a new name and therefore a rolling update. That is the point of generators. The patch matches the container by `name`, which is how strategic merge handles lists of containers. Check `kubectl kustomize` output before applying.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-kz
ov=/tmp/cka/m2-kustomize/overlays/staging
d="kubectl -n $ns get deploy api -o jsonpath"
[ -f $ov/kustomization.yaml ] || [ -f $ov/kustomization.yml ] || [ -f $ov/Kustomization ] && p "overlay kustomization exists" || f "overlay kustomization exists"
grep -q 'configMapGenerator' /tmp/cka/m2-kustomize/base/kustomization.yaml 2>/dev/null && f "base left unchanged" || p "base left unchanged"
cm=$($d='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}' 2>/dev/null)
case "$cm" in api-settings-*) p "envFrom points at generated $cm";; *) f "envFrom points at a generated api-settings ConfigMap";; esac
[ -n "$cm" ] && [ "$(kubectl -n $ns get cm "$cm" -o jsonpath='{.data.MODE}/{.data.LOG_LEVEL}' 2>/dev/null)" = "staging/info" ] && p "configmap holds MODE=staging, LOG_LEVEL=info" || f "configmap holds MODE=staging, LOG_LEVEL=info"
[ "$($d='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)" = "50m" ] && p "cpu request 50m" || f "cpu request 50m"
[ "$($d='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)" = "32Mi" ] && p "memory request 32Mi" || f "memory request 32Mi"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "1" ] && p "api pod available" || f "api pod available"
[ "$(kubectl -n $ns exec deploy/api -- printenv MODE 2>/dev/null)" = "staging" ] && p "pod sees MODE=staging" || f "pod sees MODE=staging"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 14: Autoscaling that scales down gently

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

Create a HorizontalPodAutoscaler named `render` (API `autoscaling/v2`) for Deployment `render` in namespace `m2-hpa`. It must keep between **1** and **5** replicas and target **70%** average CPU utilization. When scaling down it must use a stabilization window of **120 seconds** and remove at most **1 Pod every 60 seconds**.

<details>
<summary>💡 Hints</summary>

- kubectl autoscale creates the basic object; the behavior block has to be written in YAML (spec.behavior.scaleDown).
- kubectl explain hpa.spec.behavior.scaleDown --api-version=autoscaling/v2 lists the fields.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: render
  namespace: m2-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: render
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 120
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
EOF
kubectl -n m2-hpa get hpa render
```

**Explanation:**

- `apiVersion: autoscaling/v2` — The v2 API is the one with a `behavior` field.
- `scaleTargetRef:` — The Deployment to scale.
- `averageUtilization: 70` — Aims for 70% of each Pod's 200m CPU request, averaged across Pods.
- `stabilizationWindowSeconds: 120` — Scale-down follows the highest recommendation of the last 120 seconds.
- `- type: Pods` — At most 1 Pod removed per 60-second period.
- `get hpa render` — Confirms the object; TARGETS fills in once metrics arrive.

**Notes:** Fastest exam route: `kubectl autoscale deploy render -n m2-hpa --min=1 --max=5 --cpu=70% --dry-run=client -o yaml > hpa.yaml`, then add the `behavior` block from the HPA docs page (search 'horizontal pod autoscale behavior'). Without behavior, scale-down uses a 300-second window and may remove all surplus Pods at once.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-hpa
h="kubectl -n $ns get hpa render -o jsonpath"
kubectl -n $ns get hpa render >/dev/null 2>&1 && p "hpa render exists" || f "hpa render exists"
[ "$($h='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}' 2>/dev/null)" = "Deployment/render" ] && p "targets Deployment/render" || f "targets Deployment/render"
[ "$($h='{.spec.minReplicas}/{.spec.maxReplicas}' 2>/dev/null)" = "1/5" ] && p "min 1, max 5" || f "min 1, max 5"
[ "$($h='{.spec.metrics[0].resource.name}/{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null)" = "cpu/70" ] && p "cpu target 70%" || f "cpu target 70%"
[ "$($h='{.spec.behavior.scaleDown.stabilizationWindowSeconds}' 2>/dev/null)" = "120" ] && p "scale-down window 120s" || f "scale-down window 120s"
[ "$($h='{.spec.behavior.scaleDown.policies[*].type}' 2>/dev/null)" = "Pods" ] && p "single Pods policy" || f "single Pods policy"
[ "$($h='{.spec.behavior.scaleDown.policies[0].value}/{.spec.behavior.scaleDown.policies[0].periodSeconds}' 2>/dev/null)" = "1/60" ] && p "1 pod per 60s" || f "1 pod per 60s"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 15: Discover peers through DNS

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

In namespace `m2-dns`, create a **headless** Service named `peers` that selects the Pods labeled `app=peer` on port `7000`. Then, from Pod `dns-probe`, look up the Service by its fully qualified name with `nslookup` and save the complete output to `/tmp/cka/m2-15-peers.txt`; it must list one address per peer Pod. Finally write the ClusterIP of the cluster DNS Service in `kube-system`, and nothing else, to `/tmp/cka/m2-15-dns-ip.txt`.

<details>
<summary>💡 Hints</summary>

- A headless Service has clusterIP: None; its DNS name resolves to the Pod IPs instead of a virtual IP.
- The cluster DNS Service is still called kube-dns even though CoreDNS answers behind it.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: peers
  namespace: m2-dns
spec:
  clusterIP: None
  selector:
    app: peer
  ports:
    - port: 7000
      targetPort: 7000
EOF
for i in $(seq 1 20); do
  n=$(kubectl -n m2-dns exec dns-probe -- nslookup peers.m2-dns.svc.cluster.local 2>/dev/null | grep -c '^Address: ' || true)
  [ "$n" -ge 3 ] && break
  sleep 2
done
kubectl -n m2-dns exec dns-probe -- nslookup peers.m2-dns.svc.cluster.local > /tmp/cka/m2-15-peers.txt
kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' > /tmp/cka/m2-15-dns-ip.txt
cat /tmp/cka/m2-15-peers.txt /tmp/cka/m2-15-dns-ip.txt; echo
```

**Explanation:**

- `cat <<'EOF' | kubectl apply -f -` — A heredoc piped to `kubectl apply -f -`: everything up to `EOF` goes straight to the cluster, no file needed. The quotes in `'EOF'` stop the shell from changing anything inside.
- `clusterIP: None` — Makes the Service headless: no virtual IP, and DNS answers with the Pod IPs.
- `app: peer` — Selects the peer Pods. The label is `peer`, not `peers`.
- `for i in $(seq 1 20); do` — Repeats the lookup until it returns at least 3 addresses, since records can take a moment to appear.
- `nslookup peers.m2-dns.svc.cluster.local > /tmp` — Saves the full lookup output: one Address line per peer Pod.
- `get svc kube-dns` — The cluster DNS Service's ClusterIP, written without a newline.
- `cat /tmp/cka/m2-15-peers.txt` — Shows both files.

**Notes:** `kubectl create service clusterip peers --clusterip=None --tcp=7000` creates a headless Service too, but its selector is `app=peers`; fix it or write the YAML. A normal Service answers with one ClusterIP; a headless one answers with an A record per ready Pod, which is how StatefulSets find each other. The lookup runs inside the Pod, so use the Pod's resolver, never your laptop's.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-dns
s="kubectl -n $ns get svc peers -o jsonpath"
[ "$($s='{.spec.clusterIP}' 2>/dev/null)" = "None" ] && p "peers is headless" || f "peers is headless"
[ "$($s='{.spec.selector.app}' 2>/dev/null)" = "peer" ] && p "selects app=peer" || f "selects app=peer"
[ "$($s='{.spec.ports[0].port}' 2>/dev/null)" = "7000" ] && p "port 7000" || f "port 7000"
grep -q 'peers.m2-dns.svc.cluster.local' /tmp/cka/m2-15-peers.txt 2>/dev/null && p "lookup output names the FQDN" || f "lookup output names the FQDN"
n=$(grep '^Address:' /tmp/cka/m2-15-peers.txt 2>/dev/null | grep -v ':53$' | sort -u | wc -l | tr -d ' ')
[ "$n" = "3" ] && p "lookup lists 3 peer addresses" || f "lookup lists 3 peer addresses (got $n)"
[ "$(tr -d '[:space:]' < /tmp/cka/m2-15-dns-ip.txt 2>/dev/null)" = "$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" ] && p "dns ip file holds the kube-dns ClusterIP" || f "dns ip file holds the kube-dns ClusterIP"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 16: Which container is busy

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 7% |
| **Time** | 4 min |

**Question:**

Pod `pipeline` in namespace `m2-top` runs several containers. Using the cluster's resource metrics, find the container in that Pod that is consuming the most CPU and write its name, and nothing else, to `/tmp/cka/m2-16-container.txt`.

<details>
<summary>💡 Hints</summary>

- kubectl top pod accepts --containers to break a Pod's usage down per container.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
kubectl -n m2-top top pod pipeline --containers
kubectl -n m2-top top pod pipeline --containers --no-headers | sort -k3 -n -r | awk 'NR==1 {print $2}' > /tmp/cka/m2-16-container.txt
cat /tmp/cka/m2-16-container.txt
```

**Explanation:**

- `kubectl -n m2-top top pod pipeline --containers` — Splits the Pod's usage per container: POD, NAME, CPU, MEMORY.
- `sort -k3 -n -r` — Sorts by the third column (CPU) as numbers, highest first, then awk prints the container name from the first line.
- `cat /tmp/cka/m2-16-container.txt` — Checks the file.

**Notes:** With `--containers` the columns are POD, NAME (the container), CPU and MEMORY. Sorting `200m`-style values numerically works because they share the `m` suffix; when in doubt, just read the table. Metrics lag by up to a minute, so give a freshly started Pod some time before trusting the numbers.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
[ "$(tr -d '[:space:]' < /tmp/cka/m2-16-container.txt 2>/dev/null)" = "transform" ] && p "answer file names transform" || f "answer file names transform"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### Task 17: A drain that will not finish

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 4% |
| **Time** | 6 min |

**Question:**

Node `cka-worker2` must be drained for maintenance, but a drain does not complete. Find out what blocks it. You may relax the PodDisruptionBudget `quorum-pdb` in namespace `m2-maint` so that at most one `quorum` Pod is unavailable at a time, but do not delete it. Drain the node (DaemonSet Pods may stay, standalone Pods may be deleted), then return it to service. Both `quorum` replicas must be available at the end.

<details>
<summary>💡 Hints</summary>

- Run the drain with a --timeout so it gives up and prints the eviction error; kubectl get pdb -A shows ALLOWED DISRUPTIONS.
- A PDB takes either minAvailable or maxUnavailable, not both.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl drain cka-worker2 --ignore-daemonsets --delete-emptydir-data --force --timeout=30s || true
kubectl get pdb -A
kubectl -n m2-maint patch pdb quorum-pdb --type=json -p='[{"op":"remove","path":"/spec/minAvailable"},{"op":"add","path":"/spec/maxUnavailable","value":1}]'
kubectl drain cka-worker2 --ignore-daemonsets --delete-emptydir-data --force --timeout=180s
kubectl uncordon cka-worker2
kubectl -n m2-maint rollout status deploy/quorum --timeout=180s
```

**Explanation:**

- `--timeout=30s || true` — A first drain with a short timeout, so it gives up and shows the eviction error instead of retrying for ever.
- `kubectl get pdb -A` — ALLOWED DISRUPTIONS is 0 for `quorum-pdb`: that is the blocker.
- `patch pdb quorum-pdb --type=json` — One JSON patch removes `minAvailable` and adds `maxUnavailable: 1`, since a PDB takes only one of the two.
- `--force --timeout=180s` — Now one quorum Pod may be evicted, so the drain finishes; `--force` deletes `scratch`.
- `kubectl uncordon cka-worker2` — Returns the node to service, so the Pending quorum replica can schedule there.
- `rollout status deploy/quorum` — Waits until both replicas are available again.

**Notes:** With `minAvailable: 2` and two replicas, ALLOWED DISRUPTIONS is 0, so every eviction is refused and drain retries until its timeout (*Cannot evict pod as it would violate the pod's disruption budget*). `maxUnavailable: 1` (or `minAvailable: 1`) lets one Pod go. The evicted replica stays Pending while the node is cordoned because the anti-affinity rule forbids two replicas on one node; it returns after `uncordon`. `--disable-eviction` would bypass the budget entirely, which is exactly what a PDB exists to prevent.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=m2-maint
kubectl -n $ns get pdb quorum-pdb >/dev/null 2>&1 && p "pdb quorum-pdb still exists" || f "pdb quorum-pdb still exists"
mu=$(kubectl -n $ns get pdb quorum-pdb -o jsonpath='{.spec.maxUnavailable}' 2>/dev/null)
ma=$(kubectl -n $ns get pdb quorum-pdb -o jsonpath='{.spec.minAvailable}' 2>/dev/null)
{ [ "$mu" = "1" ] || [ "$ma" = "1" ]; } && p "pdb allows one disruption" || f "pdb allows one disruption"
[ "$(kubectl get node cka-worker2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ] && p "cka-worker2 schedulable again" || f "cka-worker2 schedulable again"
kubectl -n $ns get pod scratch >/dev/null 2>&1 && f "standalone pod scratch evicted" || p "standalone pod scratch evicted"
[ "$(kubectl -n $ns get deploy quorum -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "quorum has 2 available" || f "quorum has 2 available"
[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka)*
