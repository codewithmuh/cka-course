# The Gateway API

> **Module 3** · Lesson 3.5 · 40 minutes

How GatewayClass, Gateway and HTTPRoute share the work of an Ingress, and how to write matches and traffic splits.

## Learning Objectives

- You can say which team owns GatewayClass, Gateway and HTTPRoute, and how a route attaches to a listener.
- You can write an HTTPRoute with hostnames, path matches and weighted backends, and check it with kubectl.
- You can turn an Ingress into a Gateway plus an HTTPRoute, including TLS.


The **Gateway API** is the newer way to let web traffic into a cluster. It does the job of an Ingress, with more features, and splits the work over three objects. The exam topic is **Use the Gateway API to manage Ingress traffic**. A typical task: create a Gateway and an HTTPRoute, split traffic between two versions, or turn an Ingress into Gateway API objects.

It is all YAML, because there is no `kubectl create gateway`. So you need a clear picture of the three objects, and a fast way to look up their fields.

## Why it exists

An Ingress puts everything in one object: the entry point, TLS and every route. Anything beyond host and path, such as redirects or traffic splits, went into annotations. Each controller had its own annotations, so they did not work across controllers. The Gateway API (`gateway.networking.k8s.io/v1`) splits the object by team, and puts those features into the spec itself.

## Three objects, three owners

| Kind | Scope | Owned by | Says |
| --- | --- | --- | --- |
| `GatewayClass` | The whole cluster | The infrastructure team | "Gateways of this class are run by controller X" (`spec.controllerName`) |
| `Gateway` | One namespace | The cluster operator | "Listen on these ports and hostnames, with these certificates, and accept routes from these namespaces" |
| `HTTPRoute` | One namespace | The app team | "For these hostnames and paths, send traffic to these Services" (`parentRefs` picks the Gateway) |

**How the objects connect**

*Each object names the one before it: the Gateway names its class, and the route names its Gateway in parentRefs.*

`GatewayClass` — which controller runs the Gateways (`nw-edge`) → `Gateway` — listeners: ports and hostnames (`edge`) → `HTTPRoute` — rules: host and path to a Service (`store`) → `Service` — your app's Pods (`store-v1`)

Like an Ingress, none of this moves any traffic by itself:

- A **controller** does the work. It reads the objects and runs the actual proxy.
- **This lab installs the Gateway API CRDs but no controller.** Your objects are checked and saved, but their status stays at *Waiting for controller*, and no traffic flows.
- On the exam, a controller is installed, and the grader can send real requests.

These commands show what is installed, and which fields each kind has:

```bash
kubectl get crd | grep gateway.networking.k8s.io
kubectl api-resources --api-group=gateway.networking.k8s.io
kubectl get gatewayclass                       # which controllers exist (exam: usually one)
kubectl get gateway,httproute -A

# The CRDs carry full schemas, so kubectl explain works offline and is faster than the docs
kubectl explain gateway.spec.listeners
kubectl explain httproute.spec.rules.backendRefs
kubectl explain httproute.spec.rules.filters --recursive | less
```

<details>
<summary>Line-by-line explanation</summary>

- `kubectl get crd | grep` — Lists the installed CustomResourceDefinitions and keeps the Gateway API ones. No output means the CRDs are missing, and no Gateway API object can be created.
- `api-resources --api-group` — The kinds in that API group, with their short names and whether each lives in a namespace. GatewayClass is cluster-wide; Gateways and routes are namespaced.
- `kubectl get gatewayclass` — Each class names a controller. On the exam, use the class that exists unless the task says otherwise.
- `get gateway,httproute -A` — Every Gateway and HTTPRoute in every namespace, in one list.
- `explain gateway.spec.listeners` — Field docs from the CRD's own schema: everything a listener can set, with types.
- `explain httproute.spec.rules.backendRefs` — The fields of a backend reference: `name`, `port`, `weight` and the rest.
- `filters --recursive | less` — Every filter type and its nested fields as one tree, quicker than guessing how a redirect or rewrite is nested.

</details>

## GatewayClass and Gateway

The Gateway is the entry point. Each **listener** on it is one port and protocol, and optionally one hostname. This one has two listeners: HTTP on port 80, and HTTPS on port 443 for one host.

**A class and a Gateway with two listeners**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nw-edge
spec:
  controllerName: example.com/gateway-controller   # must match the installed controller; immutable
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
  namespace: nw-gw
spec:
  gatewayClassName: nw-edge
  listeners:
    - name: http                 # routes can target one listener with parentRefs[].sectionName
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same             # the default; All, or Selector with a label selector
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "store.nw.local" # optional; routes must share a hostname with the listener
      tls:
        mode: Terminate          # the default for HTTPS
        certificateRefs:
          - kind: Secret
            name: store-tls      # kubernetes.io/tls Secret in the Gateway's namespace
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: gateway.networking.k8s.io/v1` — Every Gateway API kind uses this group and version. It comes from the installed CRDs, not from Kubernetes itself.
- `kind: GatewayClass` — Cluster-scoped, so its metadata has no namespace.
- `controllerName:` — The controller that will implement Gateways of this class. Each controller documents the exact string it looks for.
- `gatewayClassName: nw-edge` — Ties this Gateway to the class above by name, as `ingressClassName` does for an Ingress.
- `listeners:` — The entry points: each listener is one port and protocol, optionally limited to one host name. This Gateway has two.
- `allowedRoutes:` — Which routes may attach to this listener. A route from a namespace that is not allowed is simply not attached.
- `- name: https` — The second listener: HTTPS on port 443, for `store.nw.local` only.
- `tls:` — TLS settings for this listener. What an Ingress keeps in `spec.tls` lives here in the Gateway API.
- `certificateRefs:` — The certificate to serve, referenced as a Secret by name, much like `secretName` on an Ingress.

</details>

`allowedRoutes` says which routes may attach to a listener. The default, `from: Same`, allows only routes in the Gateway's own namespace. To let routes from other namespaces attach, use `from: All`, or `from: Selector` with a namespace label.

## HTTPRoute

The HTTPRoute holds the routing rules. This one sends `store.nw.local/store` to two versions of an app: 80% to `store-v1` and 20% to `store-v2`. That is a **traffic split**, often used to try a new version on a few users first.

**Hostname, path match and an 80/20 split**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store
  namespace: nw-gw
spec:
  parentRefs:
    - name: edge                 # the Gateway; add sectionName: http to pin one listener
  hostnames:
    - store.nw.local
  rules:
    - matches:
        - path:
            type: PathPrefix     # Exact, PathPrefix, or RegularExpression (controller-dependent)
            value: /store
      backendRefs:
        - name: store-v1         # a Service in the route's namespace
          port: 80               # Service port; required for Services
          weight: 80
        - name: store-v2
          port: 80
          weight: 20             # weights are relative: 4 and 1 would split the same way
```

<details>
<summary>Line-by-line explanation</summary>

- `kind: HTTPRoute` — The application team's object: which requests go to which Services.
- `parentRefs:` — Which Gateway this route attaches to. The Gateway's listener must also allow it through `allowedRoutes`.
- `hostnames:` — The Host header values this route handles. They must overlap with the listener's hostname, if it has one.
- `- matches:` — A rule: a list of matches, plus the backends that get whatever matches.
- `type: PathPrefix` — The Gateway API version of Ingress's `Prefix`: `/store` and `/store/cart` match, `/storefront` does not.
- `backendRefs:` — Where matching requests go. Two entries with weights make a traffic split.
- `weight: 80` — This backend's share of the total. The two weights add up to 100 here, so they read as percentages.

</details>

- **matches**: a request needs to match only one entry of the list. Inside one entry, every field (`path`, `headers`, `method`, …) must match. A rule with no `matches` catches every path.
- **backendRefs**: `weight` is 1 when you leave it out, and a weight of 0 sends nothing. A Service in another namespace also needs a **ReferenceGrant** there: an object that allows the reference.
- **Which rule wins**: the most specific match. For example, an `Exact` path beats a prefix, and a longer prefix beats a shorter one.

## Filters

A **filter** changes a request on its way through. The most common one is a redirect, for example from an old path to a new one:

**A redirect filter**

```yaml
  rules:
    - matches:
        - path: { type: PathPrefix, value: /old-shop }
      filters:
        - type: RequestRedirect          # answers the client itself; no backendRefs allowed in this rule
          requestRedirect:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /store
            statusCode: 301
```

<details>
<summary>Line-by-line explanation</summary>

- `rules:` — A fragment: these rules go under `spec` of an HTTPRoute like the one above.
- `{ type: PathPrefix, value: /old-shop }` — The same kind of match in YAML flow style: the braces hold a whole map on one line.
- `type: ReplacePrefixMatch` — Replaces only the matched prefix, so `/old-shop/cart` is redirected to `/store/cart`.
- `statusCode: 301` — A permanent redirect. Leave it out and you get 302, a temporary one.

</details>

Other filters work the same way. `URLRewrite` changes the path on its way to the backend. `RequestHeaderModifier` and `ResponseHeaderModifier` edit headers. `RequestMirror` copies each request to a second backend. `kubectl explain httproute.spec.rules.filters` lists all their fields.

## From Ingress to Gateway API

Every Ingress field has a place in the Gateway API. Use this table when a task asks you to move an Ingress over:

| Ingress | Gateway API |
| --- | --- |
| `ingressClassName` and IngressClass | `gatewayClassName` and GatewayClass |
| The controller's Service and its ports | `Gateway.spec.listeners` |
| `spec.tls[].secretName` | `listeners[].tls.certificateRefs`, on the Gateway |
| `rules[].host` | `HTTPRoute.spec.hostnames` |
| `pathType: Prefix` / `Exact` | `path.type: PathPrefix` / `Exact` |
| `backend.service.port.number` | `backendRefs[].port` |
| Annotations (rewrite, redirect, canary) | `filters` and `weight`, in the spec |

> [!IMPORTANT] **What the grader reads**
> The grader reads the object fields. On the Gateway: `gatewayClassName`, and each listener's `protocol`, `port`, `hostname` and `certificateRefs`. On the route: `parentRefs`, `hostnames`, `matches`, and `backendRefs` with `port` and `weight`. With a controller, it may also check status (`PROGRAMMED True` on the Gateway, `Accepted` on the route) and send a real request. Use the GatewayClass that already exists, unless told otherwise.

## 📝 Key Takeaways

- GatewayClass names the controller. Gateway opens the ports (listeners). HTTPRoute holds the rules that send traffic to Services.
- A route attaches to a Gateway with `parentRefs`, and the listener's `allowedRoutes` must allow the route's namespace.
- A traffic split is two `backendRefs` with weights, such as 80 and 20.
- TLS moves from the Ingress to the Gateway listener: `tls.certificateRefs` names the Secret.
- There is no `kubectl create` for these objects. Write the YAML, and check field names with `kubectl explain`.

**📖 Official documentation:**

- [Gateway API (kubernetes.io concept page)](https://kubernetes.io/docs/concepts/services-networking/gateway/) *(search: "gateway api")*
- [HTTPRoute guide](https://gateway-api.sigs.k8s.io/guides/http-routing/) *(search: "http routing")*
- [Traffic splitting](https://gateway-api.sigs.k8s.io/guides/traffic-splitting/) *(search: "traffic splitting")*
- [Migrating from Ingress](https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/) *(search: "migrating from ingress")*

---

### 🎯 Task: A Gateway with a weighted HTTPRoute

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 8 min |

**Question:**

Create a GatewayClass named `nw-edge` whose controller name is `example.com/gateway-controller`. In namespace `nw-gw`, create a Gateway named `edge` of that class with one listener named `http` for protocol HTTP on port 80 that accepts routes from its own namespace only. Then create an HTTPRoute named `store` attached to `edge` for hostname `store.nw.local`. Requests whose path starts with `/store` must be split so that 80% go to Service `store-v1` and 20% to Service `store-v2`, both on port 80. (The Services exist; their Pods and a Gateway controller are not needed for this task.)

<details>
<summary>💡 Hints</summary>

- All three kinds are gateway.networking.k8s.io/v1. kubectl explain httproute.spec.rules shows the fields.
- The split is two backendRefs in one rule, with weight 80 and weight 20.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nw-edge
spec:
  controllerName: example.com/gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
  namespace: nw-gw
spec:
  gatewayClassName: nw-edge
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: store
  namespace: nw-gw
spec:
  parentRefs:
    - name: edge
  hostnames:
    - store.nw.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /store
      backendRefs:
        - name: store-v1
          port: 80
          weight: 80
        - name: store-v2
          port: 80
          weight: 20
YAML
kubectl get gatewayclass nw-edge
kubectl -n nw-gw get gateway,httproute
```

**Explanation:**

- `cat <<'YAML' | kubectl apply -f -` — All three objects in one heredoc, separated by `---`, created by a single `apply`.
- `controllerName: example.com/gateway-controller` — Copied exactly from the task. The field cannot be changed later, so a typo means deleting and recreating the class.
- `gatewayClassName: nw-edge` — Ties the Gateway to the class above by name.
- `- name: http` — The listener name the task asks for. Routes and graders find a listener by this name.
- `from: Same` — Only routes in `nw-gw` may attach: that is "its own namespace only". It is the default, but writing it makes it explicit.
- `- name: edge` — Attaches the route to Gateway `edge` in the route's own namespace.
- `- store.nw.local` — The route only handles requests for this host name.
- `type: PathPrefix` — Matches `/store` and every path below it.
- `weight: 80` — 80 out of a total of 100: 80% of matching requests go to `store-v1`.
- `weight: 20` — The other 20% go to `store-v2`. Both backends use Service port 80.
- `kubectl get gatewayclass nw-edge` — The class exists. With no controller claiming it, ACCEPTED stays Unknown; on the exam a real controller sets it to True.
- `get gateway,httproute` — Both objects are stored. Without a controller the Gateway gets no address and PROGRAMMED stays Unknown.

**Notes:** Start from the examples on the kubernetes.io Gateway API page (search "gateway api"), and change the names. Use `kubectl explain` for anything not shown there. On this lab, `kubectl get gateway` shows `PROGRAMMED Unknown` and the route has no status, because no controller claims `example.com/gateway-controller`. On the exam, a real controller sets `Accepted` and `Programmed` to `True`. Check that too.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-gw
gw="kubectl -n $ns get gateway edge -o jsonpath"
rt="kubectl -n $ns get httproute store -o jsonpath"

[ "$(kubectl get gatewayclass nw-edge -o jsonpath='{.spec.controllerName}' 2>/dev/null)" = "example.com/gateway-controller" ] && p "gatewayclass nw-edge -> example.com/gateway-controller" || f "gatewayclass nw-edge -> example.com/gateway-controller"
[ "$($gw='{.spec.gatewayClassName}' 2>/dev/null)" = "nw-edge" ] && p "gateway edge uses class nw-edge" || f "gateway edge uses class nw-edge"
[ "$($gw='{.spec.listeners[?(@.name=="http")].protocol}:{.spec.listeners[?(@.name=="http")].port}' 2>/dev/null)" = "HTTP:80" ] && p "listener http is HTTP:80" || f "listener http is HTTP:80"
[ "$($gw='{.spec.listeners[?(@.name=="http")].allowedRoutes.namespaces.from}' 2>/dev/null)" = "Same" ] && p "listener accepts routes from Same namespace" || f "listener accepts routes from Same namespace"
[ "$($rt='{.spec.parentRefs[0].name}' 2>/dev/null)" = "edge" ] && p "route attached to edge" || f "route attached to edge"
$rt='{.spec.hostnames}' 2>/dev/null | grep -q '"store.nw.local"' && p "hostname store.nw.local" || f "hostname store.nw.local"
[ "$($rt='{.spec.rules[*].matches[*].path.type}={.spec.rules[*].matches[*].path.value}' 2>/dev/null)" = "PathPrefix=/store" ] && p "match PathPrefix /store" || f "match PathPrefix /store"
w1=$($rt='{.spec.rules[*].backendRefs[?(@.name=="store-v1")].weight}' 2>/dev/null)
w2=$($rt='{.spec.rules[*].backendRefs[?(@.name=="store-v2")].weight}' 2>/dev/null)
case "$w1$w2" in *[!0-9]*|"") w1=0; w2=0;; esac
[ "$w2" -gt 0 ] 2>/dev/null && [ "$w1" -eq $((4 * w2)) ] && p "weights store-v1:store-v2 = 80:20 ($w1:$w2)" || f "weights store-v1:store-v2 = 80:20"
[ "$($rt='{.spec.rules[*].backendRefs[*].port}' 2>/dev/null)" = "80 80" ] && p "both backends on port 80" || f "both backends on port 80"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Migrate an Ingress to the Gateway API

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 7% |
| **Time** | 10 min |

**Question:**

The Ingress `legacy` in namespace `nw-gw2` must be replaced by Gateway API objects. Using the existing GatewayClass `nw-lab`, create a Gateway named `legacy-gw` in `nw-gw2` with a listener named `https` on port 443 using protocol HTTPS for hostname `legacy.nw.local`, terminating TLS with the Secret the Ingress uses. Then create an HTTPRoute named `legacy` attached to that Gateway that reproduces the Ingress's host and path routing exactly. Leave the Ingress in place.

<details>
<summary>💡 Hints</summary>

- Read the Ingress first: kubectl -n nw-gw2 get ingress legacy -o yaml. Note each path, its Service and its port.
- TLS moves to the Gateway listener: tls.mode Terminate, and certificateRefs with the Secret's name.
- Ingress Prefix becomes HTTPRoute PathPrefix. Use one rule per path, so each path keeps its own backend.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-gw2 get ingress legacy -o yaml | sed -n '/^spec:/,/^status:/p'
cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: legacy-gw
  namespace: nw-gw2
spec:
  gatewayClassName: nw-lab
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: legacy.nw.local
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: legacy-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: legacy
  namespace: nw-gw2
spec:
  parentRefs:
    - name: legacy-gw
      sectionName: https
  hostnames:
    - legacy.nw.local
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: api
          port: 8000
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: web
          port: 80
YAML
kubectl -n nw-gw2 get gateway legacy-gw -o yaml | sed -n '/^spec:/,/^status:/p'
kubectl -n nw-gw2 get httproute legacy -o yaml | sed -n '/^spec:/,/^status:/p'
```

**Explanation:**

- `sed -n '/^spec:/,/^status:/p'` — Prints the Ingress from `spec:` to `status:`, the part you translate: the TLS host and Secret, then each path with its Service and port.
- `cat <<'YAML' | kubectl apply -f -` — The Gateway and the HTTPRoute together in one heredoc.
- `gatewayClassName: nw-lab` — The class that already exists, as the task says.
- `- name: https` — The listener the task names. The route pins itself to it below with `sectionName`.
- `hostname: legacy.nw.local` — The Ingress's TLS host becomes the listener's hostname.
- `mode: Terminate` — The Gateway decrypts HTTPS and passes plain HTTP on to the Services, just as the Ingress controller did.
- `name: legacy-tls` — The Secret named in the Ingress's `spec.tls[].secretName`. It is in the Gateway's namespace, so no ReferenceGrant is needed.
- `sectionName: https` — Attaches the route to the `https` listener of `legacy-gw` only.
- `- legacy.nw.local` — The host from the Ingress rule.
- `value: /api` — One rule per Ingress path, so each keeps its own backend. Ingress `Prefix` becomes `PathPrefix`.
- `port: 8000` — The `api` Service listens on 8000, not 80. Copy the port from the Ingress backend; never assume.
- `value: /` — The catch-all to `web:80`. Rule order does not matter: the longer prefix `/api` wins for its paths.
- `get gateway legacy-gw -o yaml` — Reads back what the API stored, defaults included, to compare with the Ingress.
- `get httproute legacy -o yaml` — The same for the route. Expect added defaults such as `kind: Service` on each backendRef.

**Notes:** The trap is the port. The `api` Service listens on `8000`, and `backendRefs[].port` takes the Service port, just like the Ingress backend. The order of the rules does not matter, because the longer prefix wins. `sectionName: https` pins the route to that listener. Without it, the route attaches to every listener whose hostname matches.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-gw2
gw="kubectl -n $ns get gateway legacy-gw -o jsonpath"
rt="kubectl -n $ns get httproute legacy -o jsonpath"
l='{.spec.listeners[?(@.name=="https")]'

[ "$($gw='{.spec.gatewayClassName}' 2>/dev/null)" = "nw-lab" ] && p "gateway legacy-gw uses class nw-lab" || f "gateway legacy-gw uses class nw-lab"
[ "$($gw="$l.protocol}:$l.port}" 2>/dev/null)" = "HTTPS:443" ] && p "listener https is HTTPS:443" || f "listener https is HTTPS:443"
[ "$($gw="$l.hostname}" 2>/dev/null)" = "legacy.nw.local" ] && p "listener hostname legacy.nw.local" || f "listener hostname legacy.nw.local"
mode="$($gw="$l.tls.mode}" 2>/dev/null)"
[ "$mode" = "Terminate" ] && p "tls mode Terminate" || f "tls mode Terminate"
[ "$($gw="$l.tls.certificateRefs[0].name}" 2>/dev/null)" = "legacy-tls" ] && p "certificateRefs -> legacy-tls" || f "certificateRefs -> legacy-tls"
[ "$($rt='{.spec.parentRefs[0].name}' 2>/dev/null)" = "legacy-gw" ] && p "route attached to legacy-gw" || f "route attached to legacy-gw"
[ "$($rt='{.spec.hostnames[*]}' 2>/dev/null)" = "legacy.nw.local" ] && p "route hostname legacy.nw.local" || f "route hostname legacy.nw.local"
rules=$($rt='{range .spec.rules[*]}{range .matches[*]}{.path.type} {.path.value};{end}|{range .backendRefs[*]}{.name}:{.port};{end}{"\n"}{end}' 2>/dev/null)
echo "$rules" | grep -q '^PathPrefix /api;|api:8000;$' && p "PathPrefix /api -> api:8000" || f "PathPrefix /api -> api:8000"
echo "$rules" | grep -q '^PathPrefix /;|web:80;$' && p "PathPrefix / -> web:80" || f "PathPrefix / -> web:80"
kubectl -n $ns get ingress legacy >/dev/null 2>&1 && p "ingress legacy left in place" || f "ingress legacy left in place"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
