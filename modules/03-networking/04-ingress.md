# Ingress controllers and Ingress resources

> **Module 3** · Lesson 3.4 · 40 minutes

How an Ingress routes web traffic by host and path, how pathTypes match, and how to serve HTTPS with a Secret.

## Learning Objectives

- You can tell the Ingress controller, the IngressClass and the Ingress apart, and find all three on a cluster.
- You can write host and path rules with the right pathType, with kubectl or in YAML, and test them with curl.
- You can turn on HTTPS for an Ingress with a kubernetes.io/tls Secret, and check which certificate is served.


A Service works inside the cluster. An **Ingress** lets web traffic in from outside, and sends each request to the right Service by its host name and path. For example, `shop.local/api` goes to Service `shop-api`, and every other path to `shop-web`. The exam topic is **Know how to use Ingress controllers and Ingress resources**.

A typical task gives you two Services and asks for one Ingress, sometimes with HTTPS. The YAML is short. Points are lost on small details:

- a missing `ingressClassName`
- `Exact` where `Prefix` was meant
- a backend port that the Service does not have

> [!NOTE] **Ingress in 2026**
> The community `ingress-nginx` controller this lab uses stopped being maintained in March 2026. The Ingress API itself is not deprecated, and the exam still tests it.

## Controller, class and Ingress: three names, three jobs

Three things work together here, and their names look alike:

| Name | What it is | In this lab |
| --- | --- | --- |
| **Ingress controller** | A program that receives the web traffic and does the routing. It runs as a Deployment, with its own Service. | ingress-nginx, in namespace `ingress-nginx` |
| **IngressClass** | A small object that names a controller, in `spec.controller`. It links Ingresses to that controller. | `nginx` |
| **Ingress** | Your routing rules: which host and path go to which Service. It is only configuration. | `shop`, in the first task below |

An Ingress picks its class in `spec.ingressClassName`. Without a running controller, an Ingress routes nothing at all. Other controllers you may meet are Traefik, HAProxy and the cloud providers' own.

**A request through an Ingress**

*The Ingress object only holds the rules. The controller reads them, and sends each request to the matching Service's Pods.*

`Client` — asks for shop.local/api → `Ingress controller` — ingress-nginx; checks the host and path against the Ingress rules → `Service` (`shop-api:80`) → `Pods` — a shop-api Pod answers

**Find the controller on any cluster**

```bash
kubectl get ingressclass
# NAME    CONTROLLER             PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx   <none>       1h
kubectl get ingressclass -o yaml | grep is-default-class     # a default class is used when ingressClassName is omitted
kubectl -n ingress-nginx get deploy,pods,svc -o wide

# Lab: the controller runs on cka-control-plane with hostPorts 80/443,
# which kind maps to localhost:8080 and localhost:8443 on your machine.
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/      # 404 from the controller's default backend

# No default class and no ingressClassName: no controller claims the Ingress.
# It just sits there with an empty ADDRESS column and no events.
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get ingressclass` — Lists the IngressClasses: the names an Ingress can put in `ingressClassName`, and the controller behind each one. The comment lines show this lab's single class.
- `grep is-default-class` — Looks for the annotation that marks a class as the default. No output means no class is marked, so every Ingress must name its class.
- `get deploy,pods,svc -o wide` — Three kinds in one command: the controller's Deployment, its Pods (with their node, thanks to `-o wide`) and the Service that traffic enters through.
- `curl -s -o /dev/null -w` — Prints only the HTTP status code: `-o /dev/null` throws the body away and `-w` writes the code. A 404 is good news here: the controller answered, it just has no rule for this request.

</details>

## What an Ingress looks like

This Ingress sends `shop.local/api` to `shop-api`, and every other path on `shop.local` to `shop-web`:

**One host, two paths**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: nw-ing
spec:
  ingressClassName: nginx
  # defaultBackend: (optional) a Service for requests that match no rule
  rules:
    - host: shop.local         # omit host to match every host; "*.shop.local" matches one label
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: shop-api
                port:
                  number: 80   # or  name: http  for a named Service port
          - path: /
            pathType: Prefix
            backend:
              service:
                name: shop-web
                port:
                  number: 80
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: networking.k8s.io/v1` — Ingress lives in the `networking.k8s.io` API group. Old `v1beta1` examples from blog posts no longer work.
- `ingressClassName: nginx` — Picks the controller. It must be a name from `kubectl get ingressclass`; leave it out with no default class and nothing acts on this Ingress.
- `rules:` — The routing rules. A request is matched on its Host header first, then on its path.
- `paths:` — One entry per path. Order does not matter: the longest matching path wins, so `/api/orders` goes to `/api`, not to `/`.
- `pathType: Prefix` — Required on every path. `Prefix` matches `/api` and anything below it, split on `/`: `/api/v1` yes, `/apiv1` no.
- `backend:` — The Service that gets matching requests: always a Service name plus one of its ports. It must be in the Ingress's own namespace.
- `number: 80` — A port of the Service, never the container's `targetPort`; the controller works out which Pod port that maps to.
- `- path: /` — The catch-all: every path starts with `/`, so anything not under `/api` lands on `shop-web`.

</details>

| pathType | Matches | Example: path /api |
| --- | --- | --- |
| `Exact` | Only this exact path. Upper and lower case count. | `/api` only. Not `/api/` or `/api/v1`. |
| `Prefix` | This path and anything below it, compared one `/`-separated part at a time | `/api`, `/api/`, `/api/v1`. Not `/apiv1`. |
| `ImplementationSpecific` | Whatever the controller decides | Avoid it unless the question asks for it |

When several paths match, the longest one wins. At equal length, `Exact` beats `Prefix`. That is why `/` with `Prefix` works as a catch-all next to `/api`. Also, the backend Service must be in the *same namespace* as the Ingress. Its port is the Service's `port`, not the container's `targetPort`.

## kubectl create ingress

`kubectl create ingress` builds an Ingress in one line. Each `--rule` reads `host/path=service:port`.

```bash
# --rule="host/path=service:port[,tls=secret]"; a trailing * means Prefix, no * means Exact
kubectl -n nw-ing create ingress shop --class=nginx \
  --rule="shop.local/*=shop-web:80" \
  --rule="shop.local/api*=shop-api:80"

kubectl -n nw-ing create ingress shop --class=nginx --rule="shop.local/api=shop-api:80"   # Exact /api only!
kubectl -n nw-ing create ingress secure --class=nginx --rule="secure.shop.local/*=shop-web:80,tls=secure-tls"

# Always look at what you generated before applying it
kubectl -n nw-ing create ingress shop --class=nginx --rule="shop.local/*=shop-web:80" --dry-run=client -o yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `create ingress shop --class=nginx` — Creates an Ingress named `shop` with class `nginx`. Each trailing `\` continues the command on the next line.
- `shop.local/*=shop-web:80` — Host `shop.local`, path `/` as a Prefix (that is what the `*` does), sent to Service `shop-web` on its port 80.
- `shop.local/api*=shop-api:80` — A second path on the same host: `/api` and everything below it goes to `shop-api`.
- `Exact /api only!` — No `*`, so the path is `Exact`: `/api` matches, `/api/orders` does not. This line and the ones below are standalone examples, not steps to run after the command above.
- `create ingress secure` — `,tls=secure-tls` at the end of the rule adds a `tls` entry for that host using Secret `secure-tls`.
- `--dry-run=client -o yaml` — Prints the Ingress as YAML without creating it. Check each `pathType` and backend port before you apply.

</details>

> [!TIP] **The asterisk decides the pathType**
> `--rule="shop.local/api*=shop-api:80"` gives `path: /api` with `pathType: Prefix`. Without the `*` you get `pathType: Exact`, so `/api/orders` no longer matches. If the question says "`/api` and everything below it", you need the asterisk.

## TLS: serving HTTPS

With TLS, the controller serves HTTPS for a host. It needs that host's certificate and private key. You store both in a Secret of type `kubernetes.io/tls`, and the Ingress names that Secret in a `tls` list:

**The tls part of an Ingress**

```yaml
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - secure.shop.local
      secretName: secure-tls   # type kubernetes.io/tls, same namespace as the Ingress
  rules:
    - host: secure.shop.local  # the same host name as under tls
```

<details>
<summary>Line-by-line explanation</summary>

- `tls:` — Turns on HTTPS. Each entry pairs a list of hosts with the Secret that holds their certificate and key.
- `- secure.shop.local` — The host to serve over HTTPS. Use exactly the same name as in the rule below.
- `secretName: secure-tls` — The Secret with the certificate and key. It must be in the Ingress's own namespace.
- `- host: secure.shop.local` — The rule for that host. Its paths and backends follow, as in the YAML above.

</details>

To try it, make a certificate, store it in a Secret, then check which certificate the controller serves:

```bash
# A self-signed certificate for one host (use the files you are given on the exam)
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout tls.key -out tls.crt -subj "/CN=secure.shop.local" -addext "subjectAltName=DNS:secure.shop.local"

kubectl -n nw-tls create secret tls secure-tls --cert=tls.crt --key=tls.key   # type kubernetes.io/tls
kubectl -n nw-tls get secret secure-tls -o jsonpath='{.type}{"\n"}'

# Test without touching /etc/hosts: --resolve pins the name to the lab's port
curl -sk --resolve secure.shop.local:8443:127.0.0.1 https://secure.shop.local:8443/hostname
# Which certificate is served? A wrong or missing Secret gives the controller's fake certificate
echo | openssl s_client -connect 127.0.0.1:8443 -servername secure.shop.local 2>/dev/null | openssl x509 -noout -subject
```

<details>
<summary>Line-by-line explanation</summary>

- `openssl req -x509` — Makes a self-signed certificate: `-x509` outputs a certificate rather than a signing request, `-nodes` leaves the key unencrypted, `-newkey rsa:2048` creates a new key, and `-days 365` sets how long it is valid.
- `-keyout tls.key` — Writes the key to `tls.key` and the certificate to `tls.crt`. `-subj` sets its name, and `subjectAltName` lists the host names clients check it against.
- `create secret tls secure-tls` — Stores the pair in a Secret of type `kubernetes.io/tls`, under the keys `tls.crt` and `tls.key` that Ingress controllers look for.
- `-o jsonpath='{.type}` — Confirms the type. A Secret made with `create secret generic` would say `Opaque` instead.
- `curl -sk --resolve` — `--resolve` makes curl connect to 127.0.0.1 while still using `secure.shop.local` as the name, so TLS and the Host header match the rule. `-k` accepts the self-signed certificate.
- `openssl s_client` — Opens a TLS connection and prints the subject of the certificate the controller serves. `-servername` sends the host name (SNI) so the right certificate is picked; `echo |` closes the connection at once.

</details>

**Where HTTPS ends**

*"Terminating TLS" means the encryption ends at the controller. Your app never needs the certificate.*

`Client` — HTTPS to secure.shop.local → `Ingress controller` — decrypts with the certificate from Secret secure-tls → `Service and Pods` — get plain HTTP

- Once a host has TLS, ingress-nginx answers plain HTTP for it with a `308` redirect to HTTPS. So a curl on port 8080 suddenly returns nothing useful.
- The Secret must hold `tls.crt` and `tls.key`, and live in the Ingress's namespace.
- If the certificate's names do not cover the host, the controller ignores it and serves its own fake certificate.

## When an Ingress does not route

The HTTP status code tells you where to look. A `404` from nginx means no rule matched. A `503` means a rule matched, but the Service has no ready Pods.

**When an Ingress does not route**

```bash
kubectl -n nw-ing describe ingress shop          # rules, backends with their endpoints, events
kubectl -n nw-ing get endpointslices -l kubernetes.io/service-name=shop-api   # no endpoints = 503
curl -s -H 'Host: shop.local' localhost:8080/api/orders                       # Host header selects the rule
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=20       # one access-log line per request
# 404 from nginx: no rule matched (wrong host, Exact vs Prefix, missing class)
# 503: a rule matched, but the Service has no ready endpoints
```

<details>
<summary>Line-by-line explanation</summary>

- `describe ingress shop` — Shows each rule with its backend Service and the Pod addresses behind it, plus the events for the Ingress.
- `service-name=shop-api` — If the backend Service has no ready endpoints, the controller has nowhere to send the request and answers 503.
- `curl -s -H 'Host: shop.local'` — `-H` sets the Host header, which is what Ingress rules match on, so you can test any host name against `localhost:8080` without DNS.
- `logs deploy/ingress-nginx-controller` — The controller logs one line per request, with the status code and the Pod address it chose. `deploy/…` lets kubectl pick one of the Deployment's Pods for you.

</details>

> [!IMPORTANT] **What the grader reads**
> The grader reads the Ingress spec: `ingressClassName`, and each rule's `host`, `path`, `pathType`, Service name and port. For TLS it also reads `tls[].hosts`, `secretName` and the Secret's `type`. Many graders also send a request with the right Host header. So use the class the question names (or the one `kubectl get ingressclass` shows), copy host names exactly, and curl each path once.

## 📝 Key Takeaways

- An Ingress holds routing rules only. An Ingress controller (ingress-nginx here) reads them and does the routing.
- Always set `ingressClassName`. With no class and no default class, nothing serves your Ingress.
- `Prefix` matches a path and everything below it; `Exact` matches one path. In `kubectl create ingress`, a trailing `*` means Prefix.
- The longest matching path wins, so `/` works as a catch-all.
- For HTTPS, put the certificate in a `kubernetes.io/tls` Secret in the same namespace, and name it under `tls`.

**📖 Official documentation:**

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) *(search: "ingress pathType")*
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) *(search: "ingress controllers")*
- [kubectl create ingress](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_ingress/) *(search: "kubectl create ingress")*
- [Secrets: TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets) *(search: "kubernetes.io/tls secret")*

---

### 🎯 Task: Route one host to two Services by path

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 6 min |

**Question:**

In namespace `nw-ing`, create an Ingress named `shop` using IngressClass `nginx` for host `shop.local`. Requests for `/api` and every path below it must go to Service `shop-api` on port 80; all other paths must go to Service `shop-web` on port 80. On this lab, `curl -s -H 'Host: shop.local' localhost:8080/hostname` must be answered by a `shop-web` Pod and `curl -s -H 'Host: shop.local' localhost:8080/api/orders` by a `shop-api` Pod.

<details>
<summary>💡 Hints</summary>

- Both paths need pathType Prefix. In kubectl create ingress, that is a trailing * on the path.
- ingress-nginx needs a second or two to load a new Ingress. If the first curl returns 404, try again.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-ing create ingress shop --class=nginx \
  --rule="shop.local/*=shop-web:80" \
  --rule="shop.local/api*=shop-api:80"
kubectl -n nw-ing get ingress shop -o yaml | sed -n '/^spec:/,$p'
for i in $(seq 1 20); do curl -s -m 3 -H 'Host: shop.local' localhost:8080/api/orders | grep -q '^shop-api-' && break; sleep 2; done
curl -s -m 3 -H 'Host: shop.local' localhost:8080/hostname; echo
curl -s -m 3 -H 'Host: shop.local' localhost:8080/api/orders; echo
```

**Explanation:**

- `create ingress shop --class=nginx` — Creates Ingress `shop` with class `nginx`; the next two lines belong to the same command.
- `shop.local/*=shop-web:80` — Every path on `shop.local` goes to `shop-web:80`; the `*` makes `/` a Prefix match.
- `shop.local/api*=shop-api:80` — `/api` and everything below it goes to `shop-api:80`, again Prefix thanks to the `*`. The longer path wins, so it beats `/`.
- `sed -n '/^spec:/,$p'` — `sed -n` prints only what it is told to: here from the `spec:` line to the end (`$` is the last line). Check that both paths say `pathType: Prefix`.
- `for i in $(seq 1 20)` — ingress-nginx needs a moment to load a new Ingress. This retries every 2 seconds, up to 20 times, until a `shop-api` Pod answers.
- `localhost:8080/hostname; echo` — Should print a `shop-web` Pod name: `/hostname` is not under `/api`.
- `localhost:8080/api/orders; echo` — Should print a `shop-api` Pod name.

**Notes:** The one-line command is fastest, but check the `pathType` it made: both must be `Prefix`. In YAML, put both paths under one rule for `host: shop.local`, in any order, because the longest match wins. On the exam, the question usually gives you the URL to test. If not, curl the controller's Service with `-H 'Host: shop.local'`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-ing
i="kubectl -n $ns get ingress shop -o jsonpath"
bp() { $i="{.spec.rules[?(@.host==\"shop.local\")].http.paths[?(@.path==\"$1\")].$2}" 2>/dev/null; }
hit() { # $1 path, $2 label of the Deployment that must answer
  pods=" $(kubectl -n $ns get pods -l app=$2 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) "
  for n in 1 2 3 4 5 6; do
    r=$(curl -s -m 3 -H 'Host: shop.local' "localhost:8080$1" 2>/dev/null)
    [ -n "$r" ] && case "$pods" in *" $r "*) return 0;; esac
    sleep 2
  done
  return 1
}

kubectl -n $ns get ingress shop >/dev/null 2>&1 && p "ingress shop exists" || f "ingress shop exists"
[ "$($i='{.spec.ingressClassName}' 2>/dev/null)" = "nginx" ] && p "ingressClassName nginx" || f "ingressClassName nginx"
[ "$(bp / backend.service.name)" = "shop-web" ] && [ "$(bp / backend.service.port.number)" = "80" ] && p "/ -> shop-web:80" || f "/ -> shop-web:80"
[ "$(bp / pathType)" = "Prefix" ] && p "/ is Prefix" || f "/ is Prefix"
[ "$(bp /api backend.service.name)" = "shop-api" ] && [ "$(bp /api backend.service.port.number)" = "80" ] && p "/api -> shop-api:80" || f "/api -> shop-api:80"
[ "$(bp /api pathType)" = "Prefix" ] && p "/api is Prefix" || f "/api is Prefix"
hit /hostname shop-web && p "shop.local/hostname answered by shop-web" || f "shop.local/hostname answered by shop-web"
hit /api/orders shop-api && p "shop.local/api/orders answered by shop-api" || f "shop.local/api/orders answered by shop-api"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Terminate TLS on an Ingress

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

A certificate and key for `secure.shop.local` are in `/tmp/cka/nw-tls/tls.crt` and `/tmp/cka/nw-tls/tls.key`. In namespace `nw-tls`, store them in a TLS Secret named `secure-tls`. Then create an Ingress named `secure` with IngressClass `nginx` that routes all paths of host `secure.shop.local` to Service `secure-web` on port 80 and terminates TLS for that host with the Secret. On this lab, `https://secure.shop.local:8443` (resolved to 127.0.0.1) must serve that certificate.

<details>
<summary>💡 Hints</summary>

- kubectl create secret tls takes --cert and --key, and sets the type for you.
- kubectl create ingress accepts ,tls=SECRET-NAME at the end of a --rule.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-tls create secret tls secure-tls --cert=/tmp/cka/nw-tls/tls.crt --key=/tmp/cka/nw-tls/tls.key
kubectl -n nw-tls create ingress secure --class=nginx --rule="secure.shop.local/*=secure-web:80,tls=secure-tls"
kubectl -n nw-tls get ingress secure -o yaml | sed -n '/^spec:/,$p'
for i in $(seq 1 20); do curl -sk -m 3 --resolve secure.shop.local:8443:127.0.0.1 https://secure.shop.local:8443/hostname | grep -q '^secure-web-' && break; sleep 2; done
curl -sk -m 3 --resolve secure.shop.local:8443:127.0.0.1 https://secure.shop.local:8443/hostname; echo
```

**Explanation:**

- `create secret tls secure-tls` — Creates the TLS Secret from the given files; kubectl sets the type `kubernetes.io/tls` for you.
- `create ingress secure` — One rule sending every path of `secure.shop.local` to `secure-web:80`; `,tls=secure-tls` adds the `tls` block for that host.
- `sed -n '/^spec:/,$p'` — Check the stored spec: the host must appear under both `tls` and `rules`.
- `for i in $(seq 1 20)` — Retries over HTTPS until a `secure-web` Pod answers, giving the controller time to load the certificate.
- `https://secure.shop.local:8443/hostname; echo` — The final check: a `secure-web` Pod name, served over HTTPS on the lab's port 8443.

**Notes:** In YAML, TLS is a `tls` list next to `rules`, with `hosts: [secure.shop.local]` and `secretName: secure-tls`. The host must appear there and in the rule. A Secret made with `kubectl create secret generic` has the wrong type (`Opaque`), and graders check the type. Do you see *Kubernetes Ingress Controller Fake Certificate*? Then the controller could not use your Secret: check its name, its namespace, and the host names in the certificate.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-tls
h=secure.shop.local
i="kubectl -n $ns get ingress secure -o jsonpath"
fp() { openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }
want=$(fp < /tmp/cka/nw-tls/tls.crt)

[ "$(kubectl -n $ns get secret secure-tls -o jsonpath='{.type}' 2>/dev/null)" = "kubernetes.io/tls" ] && p "secret secure-tls is kubernetes.io/tls" || f "secret secure-tls is kubernetes.io/tls"
[ -n "$want" ] && [ "$(kubectl -n $ns get secret secure-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | fp)" = "$want" ] && p "secret holds the given certificate" || f "secret holds the given certificate"
[ "$($i='{.spec.ingressClassName}' 2>/dev/null)" = "nginx" ] && p "ingressClassName nginx" || f "ingressClassName nginx"
$i='{.spec.tls[?(@.secretName=="secure-tls")].hosts}' 2>/dev/null | grep -q "\"$h\"" && p "tls block: $h with secure-tls" || f "tls block: $h with secure-tls"
[ "$($i="{.spec.rules[?(@.host==\"$h\")].http.paths[0].backend.service.name}" 2>/dev/null)" = "secure-web" ] && p "rule $h -> secure-web" || f "rule $h -> secure-web"
[ "$($i="{.spec.rules[?(@.host==\"$h\")].http.paths[0].backend.service.port.number}" 2>/dev/null)" = "80" ] && p "backend port 80" || f "backend port 80"
pods=" $(kubectl -n $ns get pods -l app=secure-web -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) "
ok=""; for n in 1 2 3 4 5 6; do
  r=$(curl -sk -m 3 --resolve $h:8443:127.0.0.1 https://$h:8443/hostname 2>/dev/null)
  [ -n "$r" ] && case "$pods" in *" $r "*) ok=1; break;; esac
  sleep 2
done
[ -n "$ok" ] && p "https://$h:8443 answered by secure-web" || f "https://$h:8443 answered by secure-web"
served=$(echo | openssl s_client -connect 127.0.0.1:8443 -servername $h 2>/dev/null | fp)
[ -n "$want" ] && [ "$served" = "$want" ] && p "controller serves the given certificate" || f "controller serves the given certificate"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
