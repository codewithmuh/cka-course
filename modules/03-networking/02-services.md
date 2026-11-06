# Services: ClusterIP, NodePort, LoadBalancer and endpoints

> **Module 3** · Lesson 3.2 · 45 minutes

How a Service gives changing Pods one stable address, what each Service type adds, and how to read EndpointSlices.

## Learning Objectives

- You can expose a Deployment as a ClusterIP or NodePort Service, with the right port, targetPort and nodePort.
- You can explain what LoadBalancer, ExternalName and headless Services do, and how each looks on a cluster without a cloud provider.
- You can fix a Service with no endpoints by comparing its selector with the Pod labels, without touching the workload.


Pods come and go, and each new Pod gets a new IP. A **Service** gives a group of Pods one address that does not change. Your frontend calls `http://api`, and the Service passes each request to one of the `api` Pods. The exam topic is **Use ClusterIP, NodePort, LoadBalancer service types and endpoints**.

Expect one task that says "expose", and one where a Service exists but nothing answers. Both are quick if you know three things:

- The **selector** decides which Pods get the traffic.
- `targetPort` must be the port the container listens on.
- The **EndpointSlice** shows which of those two is wrong.

## What a Service is

A Service is a stable address in front of a group of Pods. It has three parts:

- A **ClusterIP**: a virtual IP address from the Service range (`10.96.0.0/16` in this lab).
- A **DNS name**, such as `api`, so clients never need to know the IP.
- A **selector**, such as `app=api`. Every Pod in the same namespace with those labels gets the traffic.

Three things happen behind the scenes to make that work:

1. The **EndpointSlice controller** watches the Pods. It writes the IPs of the matching Pods, and whether each one is ready, into an **EndpointSlice**.
2. **kube-proxy** on every node reads those EndpointSlices. It turns them into network rules on the node (iptables rules in this lab).
3. A client connects to `ClusterIP:port`. The rules on the client's node change the destination to one ready `PodIP:targetPort`.

No program listens on the ClusterIP itself, which is why you cannot ping a Service. kube-proxy runs as a DaemonSet in `kube-system`, one Pod per node. Its mode is in the `kube-proxy` ConfigMap: `iptables` here, with `nftables` as the newer choice.

Here is a Service in YAML, with the fields you set most often:

**The fields that matter**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: nw-svc
spec:
  type: ClusterIP            # default; NodePort and LoadBalancer build on it
  selector:
    app: api                 # must match the Pod template labels, not the Deployment's own labels
  ports:
    - name: http             # required once a Service has more than one port
      protocol: TCP
      port: 80               # what clients connect to on the ClusterIP
      targetPort: 8080       # container port; a number or a named containerPort such as "http"
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: v1` — Services belong to the core API group, so the apiVersion is plain `v1`, with no group in front.
- `type: ClusterIP` — Leave it out and you get ClusterIP. Each richer type keeps what is below it: a NodePort Service still has a ClusterIP, and a LoadBalancer Service still has node ports.
- `selector:` — How the Service finds its Pods: every Pod in the same namespace whose labels include all these pairs becomes an endpoint. There is no link by Deployment name; labels are the only connection.
- `app: api` — Check it against `kubectl get pods --show-labels`. A Deployment's own labels can differ from its Pods' labels, and the Service only ever looks at Pods.
- `- name: http` — `ports` is a list, and each `-` starts one entry. An Ingress backend can refer to this port by its name instead of its number.
- `port: 80` — The Service's own port: clients call `api:80`. It does not have to match what the container listens on.
- `targetPort: 8080` — Where traffic is delivered on the chosen Pod. If nothing listens there, the Service still has endpoints but every request is refused.

</details>

## port, targetPort and nodePort: three ports, three jobs

These names look alike, but each one is a different port:

| Field | What it is | Example |
| --- | --- | --- |
| `port` | The Service's own port. Clients call it. | `http://api:80` |
| `targetPort` | The port on the Pod that gets the traffic. It must match what the container listens on. | `8080` |
| `nodePort` | A port opened on every node, for traffic from outside. Only NodePort and LoadBalancer Services have one. | `30080` |
| `containerPort` | Set in the Pod spec, not in the Service. It documents the container's port, and can give it a name. | `8080`, named `http` |

**One request, three ports**

*A Pod inside the cluster skips the first step: it calls the Service on port 80 directly.*

`Client outside` (`curl <node-ip>:30080`) → `Any node` — nodePort (`30080`) → `Service` — port (`80`) → `A Pod` — targetPort (`8080`)

`targetPort` can also be a name, such as `http`. It then means the container port with that name. That lets you change the container's port number without editing the Service. If you leave `targetPort` out, it is the same as `port`. That is a common cause of "connection refused".

## The Service types

Each type adds one more way in, on top of the type before it.

**Each type builds on the one before**

*A NodePort Service still has a ClusterIP, and a LoadBalancer Service still has node ports.*

`ClusterIP` — a virtual IP, reachable only inside the cluster → `NodePort` — adds the same port on every node, from 30000 to 32767 → `LoadBalancer` — adds an external load balancer from the cloud

| Type | What you get | On this kind lab |
| --- | --- | --- |
| `ClusterIP` | A virtual IP that works only inside the cluster. This is the default type. | Works |
| `NodePort` | A ClusterIP, plus the same port opened on every node (`spec.ports[].nodePort`, from 30000–32767). Kubernetes picks one if you do not. | Works. kind maps node port 30080 to `localhost:30080` on your laptop. |
| `LoadBalancer` | A NodePort, plus an external load balancer. A cloud controller creates it and writes its address into `status.loadBalancer.ingress`. | EXTERNAL-IP stays ``, because nothing creates the load balancer |
| `ExternalName` | No ClusterIP and no proxying. DNS answers with a CNAME (an alias) to `spec.externalName`. | Works, because it is only DNS |
| Headless (`clusterIP: None`) | No virtual IP. DNS answers with the ready Pods' own IPs. | Works. StatefulSets use it. |

A LoadBalancer Service needs a helper outside Kubernetes, because Kubernetes only records the request. A cloud provider's controller (AWS, GCP, Azure) or an add-on such as MetalLB creates the load balancer and fills in its address. Without one, the Service still works as a NodePort. You can see this on `ingress-nginx-controller` in this lab.

## Quick commands: expose and create service

Two commands create a Service in one line. The difference is the selector:

- `kubectl expose` copies the selector from the Deployment, so the Service finds the right Pods.
- `kubectl create service` always sets the selector to `app=`. If your Pods have other labels, fix the selector afterwards.

**expose copies the selector; create service invents one**

```bash
# expose reads the Deployment's selector, so the endpoints are right by construction
kubectl -n nw-svc expose deploy api --name=api-svc --port=80 --target-port=8080
kubectl -n nw-svc expose deploy api --name=api-np --type=NodePort --port=80 --target-port=8080
#   there is no --node-port flag on expose; set it afterwards:
kubectl -n nw-svc patch svc api-np --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

# create service sets the selector to app=<service-name>; correct it if your Pods differ
kubectl -n nw-svc create service clusterip api --tcp=80:8080
kubectl -n nw-svc create service nodeport api --tcp=80:8080 --node-port=30080
kubectl -n nw-svc create service externalname docs --external-name=kubernetes.io
kubectl -n nw-svc create service clusterip db --clusterip=None --tcp=5432:5432   # headless

# A Pod can be exposed too (it uses the Pod's labels as the selector)
kubectl -n nw-svc expose pod web --port=80 --target-port=8080 --name=web
```

<details>
<summary>Line-by-line explanation</summary>

- `expose deploy api --name=api-svc` — Creates a ClusterIP Service (the default type) named `api-svc` with the Deployment's selector. `--port` is what clients call, `--target-port` what the container listens on.
- `--name=api-np --type=NodePort` — The same as a NodePort. With no number given, Kubernetes picks a free node port between 30000 and 32767.
- `patch svc api-np --type=json` — A JSON patch: `replace` the value at `/spec/ports/0/nodePort` (the first port; lists count from 0) with 30080. The single quotes stop the shell from touching the brackets and double quotes.
- `create service clusterip api` — `--tcp=80:8080` means port 80 on the Service, 8080 on the Pods. The selector becomes `app=api` only because the Service is named `api`.
- `create service nodeport api` — Unlike `expose`, this command takes `--node-port` directly. The selector is again `app=` plus the Service name. These lines are alternatives, not steps: run after the ones above, they would clash on name and port.
- `create service externalname docs` — No selector and no ClusterIP: a lookup of `docs` in this namespace returns a CNAME pointing at `kubernetes.io`.
- `--clusterip=None` — Makes the Service headless: no virtual IP, and DNS answers with the ready Pods' own IPs.
- `expose pod web` — The Pod's labels become the selector, so this only works on a Pod that has labels.

</details>

## Endpoints and EndpointSlices

An **EndpointSlice** is the list of Pod IPs behind a Service. When a Service does not answer, look here first.

- Each slice has the label `kubernetes.io/service-name=`, so you find it by label, not by name.
- Each address has conditions, such as `ready`. Only ready Pods get traffic.
- The older `Endpoints` object still exists, but reading it prints a deprecation warning. Use slices in scripts; either is fine for a quick look.

*[Interactive visual: service-routing]*

```bash
kubectl -n nw-svc get endpointslices -l kubernetes.io/service-name=api-svc
# NAME            ADDRESSTYPE   PORTS   ENDPOINTS                       AGE
# api-svc-x7k2p   IPv4          8080    10.244.157.130,10.244.89.67   10s

kubectl -n nw-svc describe svc api-svc | grep -E 'Selector|TargetPort|Endpoints'
kubectl -n nw-svc get endpoints api-svc       # works, with "v1 Endpoints is deprecated" warning
```

<details>
<summary>Line-by-line explanation</summary>

- `get endpointslices -l kubernetes.io/service-name=api-svc` — A slice is named after its Service plus a random suffix, so you find it by the label that names the Service. The comment lines show what a healthy slice looks like.
- `describe svc api-svc | grep -E` — `describe` sums up the Service; `grep -E` keeps lines matching any of the three words. An empty `Endpoints:` line means no ready Pod matches the selector.
- `get endpoints api-svc` — The older Endpoints object, still kept in sync. Fine for a glance; the warning is expected.

</details>

A Service whose selector matches no Pod still looks fine in `kubectl get svc`. The signs are elsewhere:

- `kubectl describe svc` shows an empty `Endpoints:` line.
- The EndpointSlice shows `` for its ports and endpoints.
- Clients get *connection refused* at once, because kube-proxy rejects traffic to a Service with no backends.
- Pods that match but are not Ready appear with `ready=false`, and get no traffic.

**The no-endpoints checklist**

```bash
kubectl -n nw-svc get svc orders -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n nw-svc get pods --show-labels
kubectl -n nw-svc get pods -l app=orders,tier=backend      # paste the selector here; empty means mismatch
kubectl -n nw-svc get endpointslices -l kubernetes.io/service-name=orders

# Fix the Service, not the Pods, unless the question says otherwise
kubectl -n nw-svc set selector svc orders app=orders,tier=backend
# or: kubectl -n nw-svc patch svc orders -p '{"spec":{"selector":{"app":"orders"}}}'
```

<details>
<summary>Line-by-line explanation</summary>

- `{.spec.selector}` — Step 1: the labels the Service is looking for, printed as JSON.
- `--show-labels` — Step 2: the labels the Pods actually carry. Compare them with the selector key by key; one letter is enough to break it.
- `get pods -l app=orders,tier=backend` — Step 3: use the selector as a filter. If no Pods are listed, the Service cannot have endpoints either.
- `get endpointslices -l kubernetes.io/service-name=orders` — Step 4: the Service's side. A healthy slice lists one address per matching Pod; `` means none.
- `set selector svc orders` — Replaces the Service's whole selector with exactly these labels. Fixing the Service sticks; relabeled Pods last only until the Deployment replaces them.
- `# or: kubectl` — A patch merges instead: it changes `app` and keeps any other keys the selector already has.

</details>

> [!IMPORTANT] **What the grader reads**
> The grader reads the Service spec: `type`, `port`, `targetPort`, `nodePort` and `selector`. It often checks that the Service has endpoints or answers a request, too. Right ports with a wrong selector score zero. So after every Service task, check the EndpointSlice and send one real request from a client Pod. And watch `kubectl create service`: it quietly sets the selector to `app=`.

## 📝 Key Takeaways

- A Service gives a group of Pods one stable name and IP. Its selector picks the Pods by label.
- `port` is what clients call, `targetPort` is where the container listens, and `nodePort` is the port on every node.
- Each type adds a way in: ClusterIP inside the cluster, NodePort on every node, LoadBalancer through a cloud load balancer.
- `kubectl expose` copies the right selector. `kubectl create service` sets `app=`.
- No answer? Check the EndpointSlice. If it is empty, the selector matches no ready Pod.

**📖 Official documentation:**

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/) *(search: "service nodeport targetport")*
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) *(search: "endpointslice")*
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/) *(search: "connecting applications with services")*
- [kubectl expose](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_expose/) *(search: "kubectl expose")*

---

### 🎯 Task: Expose a Deployment inside the cluster

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 4 min |

**Question:**

In namespace `nw-svc`, the Deployment `api` serves HTTP on container port 8080. Create a Service named `api-svc` of type `ClusterIP` that exposes it on port `80` and forwards to port 8080 of the Pods. A request from Pod `client` to `http://api-svc/hostname` must return the name of an `api` Pod.

<details>
<summary>💡 Hints</summary>

- kubectl expose deploy copies the Deployment's selector.
- --port is the Service's port. --target-port is the container's port.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-svc expose deploy api --name=api-svc --type=ClusterIP --port=80 --target-port=8080
for i in $(seq 1 20); do
  [ -n "$(kubectl -n nw-svc get endpointslices -l kubernetes.io/service-name=api-svc -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ] && break
  sleep 1
done
kubectl -n nw-svc get endpointslices -l kubernetes.io/service-name=api-svc
kubectl -n nw-svc exec client -- wget -qO- -T 3 http://api-svc/hostname
```

**Explanation:**

- `expose deploy api --name=api-svc` — Creates the Service from the Deployment's own selector: port 80 for clients, 8080 on the Pods.
- `for i in $(seq 1 20); do` — A wait loop of up to 20 tries. `seq 1 20` prints the numbers 1 to 20, one per pass.
- `[ -n "$(kubectl` — `[ -n … ]` is true when the text is not empty, so `break` leaves the loop as soon as the slice lists an address. Otherwise it sleeps a second and tries again.
- `get endpointslices -l kubernetes.io/service-name=api-svc` — Shows the slice: two Pod IPs on port 8080 mean both Pods are behind the Service.
- `exec client -- wget` — The test the task describes. The short name `api-svc` resolves because `client` is in the same namespace, and the reply is the name of whichever Pod answered.

**Notes:** `kubectl expose` is the fastest way, and it gets the selector right. `--target-port=http` would also be correct here, because the container port is named `http`. Then test it the way the question says: `kubectl -n nw-svc exec client -- wget -qO- -T 3 http://api-svc/hostname`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-svc
s="kubectl -n $ns get svc api-svc -o jsonpath"

kubectl -n $ns get svc api-svc >/dev/null 2>&1 && p "service api-svc exists" || f "service api-svc exists"
[ "$($s='{.spec.type}' 2>/dev/null)" = "ClusterIP" ] && p "type ClusterIP" || f "type ClusterIP"
[ "$($s='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "port 80" || f "port 80"
tp="$($s='{.spec.ports[0].targetPort}' 2>/dev/null)"
[ "$tp" = "8080" ] || [ "$tp" = "http" ] && p "targetPort 8080" || f "targetPort 8080 (got '$tp')"
ready=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=api-svc -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' 2>/dev/null | grep -c true)
[ "$ready" = "2" ] && p "2 ready endpoints" || f "2 ready endpoints (got $ready)"
pods=" $(kubectl -n $ns get pods -l app=api -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) "
ok=""
for i in 1 2 3; do
  r=$(kubectl -n $ns exec client -- wget -qO- -T 3 http://api-svc/hostname 2>/dev/null)
  [ -n "$r" ] && case "$pods" in *" $r "*) ok=1; break;; esac
  sleep 2
done
[ -n "$ok" ] && p "client reaches an api pod through api-svc ($r)" || f "client reaches an api pod through api-svc"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Publish a Deployment on a fixed NodePort

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

Make the Deployment `greeter` in namespace `nw-nodeport` reachable from outside the cluster. Create a Service `greeter-np` of type `NodePort` with Service port `80`, target port `8080` and node port `30080`. From your laptop, `curl -s localhost:30080/hostname` must then return the name of a `greeter` Pod.

<details>
<summary>💡 Hints</summary>

- kubectl expose has no --node-port flag. Print the YAML with --dry-run=client -o yaml and add nodePort, or patch the Service afterwards.
- kubectl create service nodeport has --node-port, but it sets the selector to app=greeter-np.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-nodeport expose deploy greeter --name=greeter-np --type=NodePort --port=80 --target-port=8080
kubectl -n nw-nodeport patch svc greeter-np --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'
kubectl -n nw-nodeport get svc greeter-np
for i in $(seq 1 15); do curl -s -m 3 localhost:30080/hostname | grep -q '^greeter-' && break; sleep 2; done
curl -s -m 3 localhost:30080/hostname; echo     # from your laptop; on the exam: curl http://<node-ip>:30080
```

**Explanation:**

- `expose deploy greeter` — Creates the NodePort Service. `expose` cannot choose the node port, so Kubernetes assigns a random one for now.
- `patch svc greeter-np` — Replaces that random port with 30080. `ports/0` is the first entry of the ports list.
- `get svc greeter-np` — PORT(S) should read `80:30080/TCP`: the Service port, then the node port.
- `for i in $(seq 1 15)` — Retries every 2 seconds, up to 15 times, until the reply starts with `greeter-`. `-m 3` caps each curl at 3 seconds; `grep -q` prints nothing and only reports whether it matched.
- `curl -s -m 3 localhost:30080/hostname; echo` — The real check. kind maps node port 30080 on the control plane to your laptop's `localhost:30080`. On a real cluster any node's IP works, because every node opens the port.

**Notes:** The exam way: run `kubectl expose deploy greeter -n nw-nodeport --name=greeter-np --type=NodePort --port=80 --target-port=8080 --dry-run=client -o yaml > np.yaml`. Add `nodePort: 30080` under the port in vim, then run `kubectl apply -f np.yaml`. If another Service already uses 30080, the API server says *provided port is already allocated*. On the exam, test with `curl http://:30080`. kube-proxy opens the port on every node, even nodes without the Pods.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-nodeport
s="kubectl -n $ns get svc greeter-np -o jsonpath"

kubectl -n $ns get svc greeter-np >/dev/null 2>&1 && p "service greeter-np exists" || f "service greeter-np exists"
[ "$($s='{.spec.type}' 2>/dev/null)" = "NodePort" ] && p "type NodePort" || f "type NodePort"
[ "$($s='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "port 80" || f "port 80"
[ "$($s='{.spec.ports[0].targetPort}' 2>/dev/null)" = "8080" ] && p "targetPort 8080" || f "targetPort 8080"
[ "$($s='{.spec.ports[0].nodePort}' 2>/dev/null)" = "30080" ] && p "nodePort 30080" || f "nodePort 30080"
pods=" $(kubectl -n $ns get pods -l app=greeter -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) "
ok=""
for i in 1 2 3 4 5; do
  for src in host node; do
    if [ $src = host ]; then r=$(curl -s -m 3 localhost:30080/hostname 2>/dev/null); else r=$(docker exec cka-control-plane curl -s -m 3 localhost:30080/hostname 2>/dev/null); fi
    [ -n "$r" ] && case "$pods" in *" $r "*) ok=$src; break 2;; esac
  done
  sleep 2
done
[ -n "$ok" ] && p "localhost:30080/hostname answered by greeter pod $r (via $ok)" || f "localhost:30080/hostname answered by a greeter pod"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Service that sends traffic nowhere

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 5% |
| **Time** | 5 min |

**Question:**

In namespace `nw-svcfix`, requests from Pod `client` to `http://orders/hostname` fail with *connection refused*, even though both `orders` Pods are Running and Ready. Find the cause and fix it so the Service `orders` delivers requests to the `orders` Pods. Do not modify the Deployment.

<details>
<summary>💡 Hints</summary>

- Compare the Service's selector with the labels on the Pods.
- An empty EndpointSlice means the Service's selector matches no ready Pod.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-svcfix get svc orders -o jsonpath='{.spec.selector}'; echo
kubectl -n nw-svcfix get pods --show-labels
kubectl -n nw-svcfix patch svc orders --type=merge -p '{"spec":{"selector":{"app":"orders","tier":"backend"}}}'
for i in $(seq 1 20); do
  [ -n "$(kubectl -n nw-svcfix get endpointslices -l kubernetes.io/service-name=orders -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ] && break
  sleep 1
done
kubectl -n nw-svcfix exec client -- wget -qO- -T 3 http://orders/hostname
```

**Explanation:**

- `{.spec.selector}'; echo` — What the Service selects. `; echo` adds the line break jsonpath leaves out.
- `--show-labels` — What the Pods carry. Side by side you spot `app=order` against `app=orders`.
- `patch svc orders --type=merge` — Sets the selector to the Pods' real labels. `--type=merge` sends a JSON merge patch: only the keys you send change, and the rest of the Service stays as it was.
- `for i in $(seq 1 20); do` — Waits up to 20 seconds for the EndpointSlice to list the Pods.
- `exec client -- wget` — The same request that failed before. A Pod name in the reply proves the fix.

**Notes:** The Service selects `app=order`, but the Pods carry `app=orders`. So the EndpointSlice is empty, and kube-proxy refuses the connection. `kubectl set selector svc orders app=orders,tier=backend -n nw-svcfix` replaces the whole selector in one command, and `kubectl edit svc orders -n nw-svcfix` works too. Relabeling the Pods would only last until the Deployment replaced them. The question forbids touching the Deployment anyway.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-svcfix

[ "$(kubectl -n $ns get deploy orders -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)" = "orders" ] && p "deployment labels unchanged" || f "deployment labels unchanged"
[ "$(kubectl -n $ns get svc orders -o jsonpath='{.spec.ports[0].port}:{.spec.ports[0].targetPort}' 2>/dev/null)" = "80:8080" ] && p "service ports 80 -> 8080" || f "service ports 80 -> 8080"
ready=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=orders -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' 2>/dev/null | grep -c true)
[ "$ready" = "2" ] && p "service has 2 ready endpoints" || f "service has 2 ready endpoints (got $ready)"
pods=" $(kubectl -n $ns get pods -l app=orders -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) "
ok=""
for i in 1 2 3; do
  r=$(kubectl -n $ns exec client -- wget -qO- -T 3 http://orders/hostname 2>/dev/null)
  [ -n "$r" ] && case "$pods" in *" $r "*) ok=1; break;; esac
  sleep 2
done
[ -n "$ok" ] && p "client reaches an orders pod ($r)" || f "client reaches an orders pod"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
