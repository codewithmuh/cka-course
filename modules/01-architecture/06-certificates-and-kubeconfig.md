# Certificates, kubeconfig and the CSR API

> **Module 1** · Lesson 1.6 · 45 minutes

The cluster's certificates and how to renew them, what a kubeconfig holds, and how to give a new user a certificate through the CSR API.

## Learning Objectives

- You can find any control plane certificate, read its subject, issuer, SANs and expiry date with openssl, and renew it with kubeadm.
- You can read and build a kubeconfig with kubectl config, with the certificates embedded in the file.
- You can create a user with a private key and a CertificateSigningRequest, approve it and give the user a working kubeconfig.


A **certificate** is an ID card for a program or a person. Every part of a kubeadm cluster shows one to prove who it is. Example: when the API server connects to etcd, it shows its client certificate, and etcd checks that a CA it trusts signed it. A **CA** (certificate authority) issues these ID cards: whoever holds its key can sign new ones.

People reach the cluster through a **kubeconfig**: a file that says which cluster to talk to and which ID to show. This lesson covers both, plus a favorite exam task: create a new user and give them a kubeconfig that works. Certificates also expire and must be renewed. So the lesson touches two exam topics: **Create and manage Kubernetes clusters using kubeadm** and **Manage the lifecycle of Kubernetes clusters**.

| Word | What it is | Example file |
| --- | --- | --- |
| Private key | A secret that only the owner keeps. It proves the certificate belongs to them. | `jane.key` |
| CSR (certificate signing request) | A request that says "please sign this": the owner's name plus their public key. | `jane.csr` |
| Certificate | The signed ID card: a name, a public key, an expiry date and the CA's signature. | `jane.crt` |
| CA | The issuer. The cluster trusts every certificate its CA signed. | `ca.crt`, `ca.key` |

## The certificates kubeadm makes

`kubeadm init` creates a set of certificates and keys in `/etc/kubernetes/pki`. This set is called the cluster's **PKI** (public key infrastructure). These are the ones you will meet:

| File in /etc/kubernetes/pki | What it is | Signed by |
| --- | --- | --- |
| `ca.crt`, `ca.key` | The cluster CA. The API server accepts any client certificate it signed (`--client-ca-file`). The controller manager also signs approved CSRs with it. | Itself |
| `apiserver.crt` | The API server's own certificate, shown to every client. Its SANs are the names and IPs it is valid for. They cover the node IP, the `kubernetes` Service IP, the `kubernetes.default…` names and the control plane endpoint. | ca |
| `apiserver-kubelet-client.crt` | The API server's ID toward kubelets, for logs, exec and port-forward. | ca |
| `apiserver-etcd-client.crt` | The API server's ID toward etcd. | etcd/ca |
| `front-proxy-ca.crt`, `front-proxy-client.crt` | Lets the API server prove who it is to add-on APIs such as metrics-server. | front-proxy-ca |
| `sa.key`, `sa.pub` | Not certificates: the key pair that signs and checks ServiceAccount tokens. | n/a |
| `etcd/ca.crt`, `etcd/server.crt`, `etcd/peer.crt`, `etcd/healthcheck-client.crt` | etcd's own set: its server, member-to-member and health-check IDs. | etcd/ca |

Next to `pki/`, kubeadm writes one kubeconfig per component in `/etc/kubernetes`: `controller-manager.conf`, `scheduler.conf` and `kubelet.conf`. There is also `admin.conf` for you, the administrator, and `super-admin.conf` for emergencies. What each identity may do is the topic of [RBAC](/cka/architecture/rbac).

- Most certificates are valid for **one year**. The CAs are valid for **ten years**.
- The kubelet's client certificate is the exception: the kubelet renews it on its own, under `/var/lib/kubelet/pki/`.

## Check and renew certificates

Two tools read certificates. `kubeadm certs check-expiration` shows when every kubeadm certificate expires. `openssl x509` reads one certificate file in detail.

**Check expiry, inspect a certificate, renew**

```bash
# exam: ssh <control-plane>; sudo -i      lab: docker exec -it cka-control-plane bash
kubeadm certs check-expiration

# Subject, issuer, expiry and SANs of any certificate
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -enddate
# subject=CN=kube-apiserver
# issuer=CN=kubernetes
# notAfter=Oct 17 09:51:49 2027 GMT
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text        # everything

# Renew one certificate, or all of them (on a real cluster; see below before you do)
kubeadm certs renew apiserver
kubeadm certs renew all
```

<details>
<summary>Line-by-line explanation</summary>

- `kubeadm certs check-expiration` — Lists every certificate kubeadm manages with its expiry date and the time left, then the CAs. Run it as root on a control plane node.
- `-noout -subject -issuer -enddate` — `openssl x509` reads a certificate file. `-noout` skips printing the encoded certificate; the other three options print who it belongs to, who signed it and when it expires.
- `# issuer=CN=kubernetes` — `kubernetes` is the common name of the cluster CA, so this certificate was signed by `ca.crt`.
- `-ext subjectAltName` — Prints the SANs: every name and IP this certificate is valid for. A client that connects through an address missing from this list gets a TLS error.
- `-noout -text` — The full human-readable dump, every field and extension. Pipe it to `less` or `grep`.
- `kubeadm certs renew apiserver` — Issues a new API server certificate, valid for another year and signed by the same CA. The running API server keeps the old one until it restarts.
- `kubeadm certs renew all` — Renews every certificate kubeadm manages, including those embedded in its kubeconfig files. CA certificates are never renewed this way.

</details>

Renewing rewrites the certificate files, including the ones inside the kubeconfig files. But running control plane Pods still hold the old certificate in memory. So after renewing:

1. Restart each control plane Pod. kubectl cannot restart a static Pod. Instead, move its file out of `/etc/kubernetes/manifests`, wait about 20 seconds for the kubelet to stop it, then move it back.
2. If your own kubeconfig is a copy of `admin.conf`, copy the renewed file again.

`kubeadm upgrade apply` also renews every certificate. That is why a cluster upgraded at least once a year never hits expiry.

## Inside a kubeconfig

A kubeconfig is a file on your machine. It tells kubectl where the cluster is and who you are. It holds three lists and a pointer:

**What a kubeconfig holds**

*Example: the context jane@kind-cka means talk to cluster kind-cka, as user jane, in namespace dev.*

`A kubeconfig file` (`~/.kube/config`)
  - `clusters` — where: the API server's URL and its CA
  - `users` — who: a certificate and key, or a token
  - `contexts` — one cluster + one user + a namespace
  - `current-context` — the context kubectl uses now

**Three lists and a pointer**

```yaml
apiVersion: v1
kind: Config
clusters:                 # where: API server URL and the CA that signed its certificate
  - name: kind-cka
    cluster:
      server: https://127.0.0.1:52634
      certificate-authority-data: LS0tLS1CRUdJTi...     # base64 PEM, or certificate-authority: /path/ca.crt
users:                    # who: a client certificate, a token or an exec plugin
  - name: jane
    user:
      client-certificate-data: LS0tLS1CRUdJTi...
      client-key-data: LS0tLS1CRUdJTi...
contexts:                 # a named pairing of cluster and user, with an optional default namespace
  - name: jane@kind-cka
    context:
      cluster: kind-cka
      user: jane
      namespace: dev
current-context: jane@kind-cka
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: Config` — A kubeconfig is a file on your machine, not an object in the cluster. kubectl reads `~/.kube/config` unless `--kubeconfig` or `KUBECONFIG` says otherwise.
- `- name: kind-cka` — Every entry in each list has a name. Contexts refer to a cluster and a user by these names.
- `server: https://127.0.0.1:52634` — The API server's URL. On kind it is a local port that Docker forwards to the control plane container, so the number differs from machine to machine.
- `certificate-authority-data:` — The cluster CA certificate, base64 encoded. kubectl uses it to check that it is talking to the real API server.
- `client-certificate-data:` — The user's certificate and, on the next line, private key, base64 encoded. `-data` fields carry the file contents inline, so the kubeconfig works on its own.
- `- name: jane@kind-cka` — A context ties one cluster and one user together, plus an optional namespace. `user@cluster` is only a naming habit.
- `namespace: dev` — The namespace commands use in this context when you leave out `-n`.
- `current-context:` — The context kubectl uses when you pass no `--context`. `kubectl config use-context` rewrites this one line.

</details>

To list, switch and change contexts with `kubectl config`, see [kubectl fluency](/cka/foundations/kubectl-fluency). Below you build a kubeconfig from scratch, for a new user.

## A new user through the CSR API

Kubernetes has no User object. Instead, any client certificate signed by the cluster CA lets you log in. Its Common Name (`CN`) becomes the username, and each Organization (`O`) becomes a group. Example: a certificate for `/CN=jane/O=developers` logs in as user `jane` in group `developers`.

The **CertificateSigningRequest** (CSR) API gets such a certificate signed, without anyone touching `ca.key`:

1. You submit a CSR object for the signer `kubernetes.io/kube-apiserver-client`.
2. An administrator approves it. This signer never approves anything automatically.
3. The controller manager signs it with the cluster CA. The certificate appears in the CSR's status.

**From key to kubeconfig**

`Key and request` — jane.key and jane.csr, on your machine (`openssl`) → `CSR object` — waits as Pending (`kubectl apply`) → `Approve` — the cluster CA signs it (`kubectl certificate approve`) → `jane.crt` — goes into jane's kubeconfig

`expirationSeconds` asks for how long the certificate stays valid, at least 600 seconds. The signer may make it shorter.

**Key, CSR and approval**

```bash
mkdir -p /tmp/cka && cd /tmp/cka
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -subj "/CN=jane/O=developers" -out jane.csr

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 < jane.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

kubectl get csr jane                  # CONDITION: Pending
kubectl certificate approve jane
kubectl get csr jane                  # CONDITION: Approved,Issued
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt
openssl x509 -in jane.crt -noout -subject -issuer -enddate
```

<details>
<summary>Line-by-line explanation</summary>

- `mkdir -p /tmp/cka && cd /tmp/cka` — Works inside `/tmp/cka`, so all the short file names below land there.
- `openssl genrsa -out jane.key 2048` — Creates jane's 2048-bit RSA private key. It never leaves this machine; only the request built from it goes to the cluster.
- `openssl req -new` — Builds a certificate signing request from the key. In `-subj`, `CN=jane` becomes the username and `O=developers` a group.
- `cat <<EOF | kubectl apply -f -` — Sends the YAML up to `EOF` straight to the cluster. Because `EOF` is not quoted, the shell runs the `$(...)` inside it first.
- `kind: CertificateSigningRequest` — A request for the cluster to sign a certificate. CSRs are cluster-wide objects, so there is no namespace.
- `request: $(base64` — The CSR file, base64 encoded. `tr -d` deletes any line breaks `base64` puts in, because the value must be one unbroken line.
- `signerName: kubernetes.io/kube-apiserver-client` — Which signer handles the request: this one issues client certificates the API server accepts. The field is required, and this signer never approves automatically.
- `expirationSeconds: 86400` — Asks for 24 hours of validity (86400 seconds). The signer may shorten it.
- `- client auth` — The key usage this signer requires: the certificate is for logging in as a client.
- `# CONDITION: Pending` — A new CSR waits as Pending until someone approves it.
- `kubectl certificate approve jane` — Approves the request. The controller manager then signs it with the cluster CA.
- `# CONDITION: Approved,Issued` — **Issued** means the signed certificate is now in the object's status. It can take a moment to appear after approval.
- `base64 -d > jane.crt` — The certificate is stored base64 encoded in `status.certificate`; `base64 -d` decodes it into a normal certificate file.
- `openssl x509 -in jane.crt` — Checks the result: subject `CN=jane`, issued by the cluster CA, expiring in about a day.

</details>

Now jane has a certificate. Put it in a kubeconfig file of her own, together with the cluster's address and CA. Run this in the same folder, `/tmp/cka`:

**A kubeconfig for jane**

```bash
# A kubeconfig for jane in its own file. On a control plane node the CA is /etc/kubernetes/pki/ca.crt.
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
kubectl config set-cluster kind-cka --server="$SERVER" --certificate-authority=ca.crt --embed-certs=true --kubeconfig=jane.kubeconfig
kubectl config set-credentials jane --client-certificate=jane.crt --client-key=jane.key --embed-certs=true --kubeconfig=jane.kubeconfig
kubectl config set-context jane@kind-cka --cluster=kind-cka --user=jane --kubeconfig=jane.kubeconfig
kubectl config use-context jane@kind-cka --kubeconfig=jane.kubeconfig

kubectl --kubeconfig=jane.kubeconfig auth whoami
kubectl --kubeconfig=jane.kubeconfig get pods       # Forbidden: authenticated, not yet authorized
```

<details>
<summary>Line-by-line explanation</summary>

- `SERVER=$(kubectl config view` — Copies the API server URL from your own current context into the variable `SERVER`.
- `base64 -d > ca.crt` — Extracts the cluster CA certificate from your kubeconfig. `--raw` is needed, or the data would be hidden.
- `kubectl config set-cluster kind-cka` — Writes the cluster entry into `jane.kubeconfig`, creating the file. `--embed-certs=true` stores the CA's contents in the file rather than its path.
- `kubectl config set-credentials jane` — Adds user `jane` with her certificate and key, also embedded, so the file works on any machine.
- `kubectl config set-context jane@kind-cka` — A context that pairs that cluster with that user.
- `kubectl config use-context jane@kind-cka` — Makes it the current context of the new file. Every command here passes `--kubeconfig=jane.kubeconfig`, so your own kubeconfig is never touched.
- `auth whoami` — Asks the API server who you are, using jane's file. It should show username `jane` and group `developers`.
- `get pods` — *Forbidden* is the expected result: the API server knows who jane is, but no RBAC rule lets her list Pods yet.

</details>

> [!IMPORTANT] **What a CSR task is graded on**
> The grader checks the CSR (`Approved`, `Issued`, the signer, sometimes the expiry), the files at the given paths, and whether the kubeconfig logs in. Common slips: a base64 value broken over several lines (use `base64 -w0` on Linux, or `tr -d '\n'`); the private key pasted into `request` instead of the CSR; a missing `signerName`. And *Forbidden* is not a failure: the login worked, and permissions are up to [RBAC](/cka/architecture/rbac).

## 📝 Key Takeaways

- A certificate is an ID card signed by a CA. kubeadm keeps the cluster's in `/etc/kubernetes/pki`. Most last one year; the CAs last ten.
- `kubeadm certs check-expiration` shows every expiry date. `openssl x509 -noout -subject -issuer -enddate` reads one file. After `kubeadm certs renew`, restart the static Pods.
- A kubeconfig holds clusters (where), users (who) and contexts (one cluster + one user + a namespace). `current-context` picks one.
- New user: key, CSR for `kubernetes.io/kube-apiserver-client`, approve, decode `status.certificate`, then build a kubeconfig with `--embed-certs=true`.
- CN is the username and O is the group. *Forbidden* means the login worked; permissions are RBAC's job.

**📖 Official documentation:**

- [Certificates and Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/) *(search: "certificate signing request normal user")*
- [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/) *(search: "kubeadm certs renew")*
- [Organizing Cluster Access Using kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) *(search: "kubeconfig")*
- [PKI certificates and requirements](https://kubernetes.io/docs/setup/best-practices/certificates/) *(search: "pki certificates")*

---

### 🎯 Task: Inspect control plane certificates

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 3% |
| **Time** | 6 min |

**Question:**

Inspect this cluster's certificates on `cka-control-plane`. (1) Write the expiry date of the API server's serving certificate to `/tmp/cka/ar-apiserver-expiry.txt`, exactly as openssl prints it after `notAfter=` (for example `Oct 17 09:51:49 2027 GMT`). (2) Find the client certificate the API server presents to etcd and write the Common Name of the CA that issued it to `/tmp/cka/ar-etcd-client-issuer.txt`. (3) Save the complete output of `kubeadm certs check-expiration` to `/tmp/cka/ar-cert-expiration.txt`.

<details>
<summary>💡 Hints</summary>

- The serving certificate is kube-apiserver's --tls-cert-file. The client certificate it shows etcd is its --etcd-certfile.
- openssl x509 -noout -enddate prints one line, and so does -issuer.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
docker exec cka-control-plane grep -E -- '--(tls-cert-file|etcd-certfile)=' /etc/kubernetes/manifests/kube-apiserver.yaml
docker exec cka-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate | cut -d= -f2 > /tmp/cka/ar-apiserver-expiry.txt
docker exec cka-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver-etcd-client.crt -noout -issuer | sed 's/.*CN *= *//' > /tmp/cka/ar-etcd-client-issuer.txt
docker exec cka-control-plane kubeadm certs check-expiration > /tmp/cka/ar-cert-expiration.txt
cat /tmp/cka/ar-apiserver-expiry.txt /tmp/cka/ar-etcd-client-issuer.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the answers folder if needed.
- `tls-cert-file|etcd-certfile` — Confirms which files the API server uses: `--tls-cert-file` is its serving certificate, `--etcd-certfile` the client certificate it presents to etcd.
- `-noout -enddate | cut -d= -f2` — openssl prints `notAfter=`; `cut -d= -f2` keeps only the date, which goes to the answer file on your workstation.
- `-noout -issuer | sed` — Prints the issuer line, and the `sed` deletes everything up to and including `CN=` (with any spaces), leaving just the CA's name, `etcd-ca`.
- `kubeadm certs check-expiration >` — Runs the expiry report on the node and saves its complete output on your workstation.
- `cat /tmp/cka/ar-apiserver-expiry.txt` — Shows the two one-line answers. The third file is long; open it with `less` to read it.

**Notes:** The issuer is `etcd-ca`, not the cluster CA. etcd has its own set of certificates, and its CA signed the API server's etcd client certificate. That is also why `check-expiration` lists more than one CA. Older openssl versions print `issuer= /CN=etcd-ca` with a slash; write only the name. On the exam, write the answer files on the machine the question names. That is usually the base host, not the node you ssh'd into.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }

want_exp=$(docker exec cka-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2 | tr -s ' ')
etcd_cert=$(docker exec cka-control-plane grep -- '--etcd-certfile=' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | cut -d= -f2 | tr -d ' ')
want_iss=$(docker exec cka-control-plane openssl x509 -in "$etcd_cert" -noout -issuer 2>/dev/null | sed 's/.*CN *= *//')
got_exp=$(tr -s ' ' 2>/dev/null < /tmp/cka/ar-apiserver-expiry.txt | sed 's/^ *//; s/ *$//')
got_iss=$(tr -d '[:space:]' 2>/dev/null < /tmp/cka/ar-etcd-client-issuer.txt | sed 's#^/##; s#^CN=##')

[ -n "$want_exp" ] && [ "$got_exp" = "$want_exp" ] && p "API server certificate expiry is $want_exp" || f "API server certificate expiry in /tmp/cka/ar-apiserver-expiry.txt"
[ -n "$want_iss" ] && [ "$got_iss" = "$want_iss" ] && p "etcd client certificate issued by $want_iss" || f "issuer of the etcd client certificate in /tmp/cka/ar-etcd-client-issuer.txt"
grep -q 'apiserver-etcd-client' /tmp/cka/ar-cert-expiration.txt 2>/dev/null && grep -q 'CERTIFICATE AUTHORITY' /tmp/cka/ar-cert-expiration.txt 2>/dev/null && p "check-expiration output saved" || f "check-expiration output in /tmp/cka/ar-cert-expiration.txt"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Create a user with the CSR API and a kubeconfig

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 10 min |

**Question:**

Create credentials for a new user `ar-dev` in group `ar-team`. Generate a 2048-bit RSA private key at `/tmp/cka/ar-dev.key` and a certificate signing request for it. Submit the request as a CertificateSigningRequest named `ar-dev` for signer `kubernetes.io/kube-apiserver-client`, valid for 24 hours, approve it, and save the issued certificate as `/tmp/cka/ar-dev.crt`. Then create a self-contained kubeconfig at `/tmp/cka/ar-dev.kubeconfig` (CA, certificate and key embedded, not referenced by path) whose current context connects to this cluster as `ar-dev` with default namespace `ar-certs`. A RoleBinding that lets `ar-dev` read Pods in `ar-certs` already exists. Do not change your own kubeconfig.

<details>
<summary>💡 Hints</summary>

- openssl req -subj "/CN=ar-dev/O=ar-team" sets the username and the group.
- spec.request is the base64 of the whole CSR file, on one line. spec.expirationSeconds is 86400.
- Pass --kubeconfig=/tmp/cka/ar-dev.kubeconfig to every kubectl config command, plus --embed-certs=true where it applies.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cd /tmp/cka
openssl genrsa -out ar-dev.key 2048
openssl req -new -key ar-dev.key -subj "/CN=ar-dev/O=ar-team" -out ar-dev.csr
kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ar-dev
spec:
  request: $(base64 < ar-dev.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF
kubectl certificate approve ar-dev
for i in $(seq 1 20); do [ -n "$(kubectl get csr ar-dev -o jsonpath='{.status.certificate}')" ] && break; sleep 2; done
kubectl get csr ar-dev -o jsonpath='{.status.certificate}' | base64 -d > ar-dev.crt

SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ar-ca.crt
K=/tmp/cka/ar-dev.kubeconfig
kubectl config set-cluster kind-cka --server="$SERVER" --certificate-authority=ar-ca.crt --embed-certs=true --kubeconfig=$K
kubectl config set-credentials ar-dev --client-certificate=ar-dev.crt --client-key=ar-dev.key --embed-certs=true --kubeconfig=$K
kubectl config set-context ar-dev@kind-cka --cluster=kind-cka --user=ar-dev --namespace=ar-certs --kubeconfig=$K
kubectl config use-context ar-dev@kind-cka --kubeconfig=$K
kubectl --kubeconfig=$K auth whoami
kubectl --kubeconfig=$K get pods
```

**Explanation:**

- `cd /tmp/cka` — Works in the answers folder, so the short file names below land where the task wants them.
- `openssl genrsa -out ar-dev.key 2048` — Creates the 2048-bit RSA private key at the path the task names.
- `openssl req -new` — Builds the signing request from that key: `CN=ar-dev` becomes the username and `O=ar-team` the group.
- `kubectl apply -f - <<EOF` — Applies the YAML that follows, up to `EOF`. The heredoc marker is unquoted, so the shell runs the `$(...)` inside before kubectl sees it.
- `request: $(base64` — The whole CSR file as one line of base64; `tr -d` removes any line breaks `base64` puts in.
- `expirationSeconds: 86400` — 24 hours, as the task asks.
- `kubectl certificate approve ar-dev` — Approves the request. The controller manager signs it with the cluster CA a moment later.
- `for i in $(seq 1 20)` — Waits up to 40 seconds for `status.certificate` to be filled in. `[ -n "..." ]` is true when the text inside is not empty.
- `base64 -d > ar-dev.crt` — Decodes the issued certificate into `ar-dev.crt`.
- `SERVER=$(kubectl config view` — Copies the API server URL from your current context.
- `base64 -d > ar-ca.crt` — Decodes the cluster CA from your kubeconfig so it can be embedded in the new file.
- `K=/tmp/cka/ar-dev.kubeconfig` — A short name for the new file. Every command below passes `--kubeconfig=$K`, so your own kubeconfig is never touched.
- `config set-cluster kind-cka` — The cluster entry, with the CA embedded (`--embed-certs=true`) rather than referenced by path.
- `config set-credentials ar-dev` — The user entry, with the certificate and key embedded too. That is what makes the file self-contained.
- `config set-context ar-dev@kind-cka` — Pairs that cluster and user and sets the default namespace `ar-certs`.
- `config use-context ar-dev@kind-cka` — Makes that context current in the new file.
- `auth whoami` — Should report username `ar-dev` in group `ar-team`.
- `--kubeconfig=$K get pods` — Lists Pods in `ar-certs`, which the existing RoleBinding allows. *No resources found* is fine; *Forbidden* means a name or the namespace is wrong.

**Notes:** Right after approval, `kubectl get csr` may still show only `Approved`. The controller manager adds the certificate a moment later, hence the short wait. On Linux, `base64 -w0 ar-dev.csr` replaces the `tr` pipe. On the exam the CA file is `/etc/kubernetes/pki/ca.crt` on the control plane node, and the server URL is in your current kubeconfig. Test the result the way the grader does: `kubectl --kubeconfig /tmp/cka/ar-dev.kubeconfig auth can-i list pods` should print `yes`. With `-n default` added, it should print `no`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
K=/tmp/cka/ar-dev.kubeconfig
c() { kubectl get csr ar-dev -o jsonpath="$1" 2>/dev/null; }
k() { kubectl config view --kubeconfig=$K --minify --raw -o jsonpath="$1" 2>/dev/null; }

kubectl get csr ar-dev >/dev/null 2>&1 && p "CSR ar-dev exists" || f "CSR ar-dev exists"
[ "$(c '{.spec.signerName}')" = "kubernetes.io/kube-apiserver-client" ] && p "signer kube-apiserver-client" || f "signer kube-apiserver-client"
[ "$(c '{.spec.expirationSeconds}')" = "86400" ] && p "requested validity 24h" || f "requested validity 24h"
[ "$(c '{.status.conditions[?(@.type=="Approved")].status}')" = "True" ] && p "CSR approved" || f "CSR approved"
[ -n "$(c '{.status.certificate}')" ] && p "certificate issued" || f "certificate issued"
[ -s /tmp/cka/ar-dev.key ] && [ -s /tmp/cka/ar-dev.crt ] && p "key and certificate saved in /tmp/cka" || f "key and certificate saved in /tmp/cka"
[ -n "$(k '{.users[0].user.client-certificate-data}')" ] && [ -n "$(k '{.users[0].user.client-key-data}')" ] && [ -n "$(k '{.clusters[0].cluster.certificate-authority-data}')" ] && p "kubeconfig embeds CA, certificate and key" || f "kubeconfig embeds CA, certificate and key"
[ "$(k '{.contexts[0].context.namespace}')" = "ar-certs" ] && p "current context defaults to namespace ar-certs" || f "current context defaults to namespace ar-certs"
[ "$(kubectl --kubeconfig=$K auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)" = "ar-dev" ] && p "kubeconfig authenticates as ar-dev" || f "kubeconfig authenticates as ar-dev"
kubectl --kubeconfig=$K auth whoami -o jsonpath='{.status.userInfo.groups}' 2>/dev/null | grep -q '"ar-team"' && p "ar-dev is in group ar-team" || f "ar-dev is in group ar-team"
[ "$(kubectl --kubeconfig=$K auth can-i list pods 2>/dev/null)" = "yes" ] && p "ar-dev can list Pods in its default namespace" || f "ar-dev can list Pods in its default namespace"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
