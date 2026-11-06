# Service and DNS failures

> **Module 5** · Lesson 5.5 · 40 minutes

A step-by-step check for "the app is not reachable": test each stop between the client and the Pod, in order.

## Learning Objectives

- You can follow a request from the client to the Pod and name one command that checks each stop.
- You can tell a wrong selector, a wrong targetPort and a blocking NetworkPolicy apart from the error the client prints.
- You can tell when DNS or kube-proxy is the cause, and you know where to look next.
- You can fix a broken Service or NetworkPolicy in place, without changing anything else the grader checks.


This exam skill is called **Troubleshoot services and networking**. The task is usually one sentence: *the frontend cannot reach the backend, fix it*. The Pods are Running and nothing crashes. The fault is somewhere between the client and the app. Do not guess. Check each stop on the path in order. The first stop that fails is your fault.

## The path of one request

Say a client Pod calls `http://orders`. Before the request reaches the app, it passes these stops:

**A request to a Service, stop by stop**

*The Service IP is not a real machine. kube-proxy, on every node, sends the request on to one Ready Pod from the EndpointSlice.*

`Client Pod` — calls http://orders → `DNS` — CoreDNS turns the name into the Service's IP → `Service` — sends the request to one of its Pods
  - `Selector` — which Pods
  - `EndpointSlice` — the Ready Pods it found → `Backend Pod` — the app, listening on the targetPort
  - `NetworkPolicy` — lets the client in, or drops it

| Stop | How to check it | What broken looks like |
| --- | --- | --- |
| DNS | `nslookup orders.shop.svc.cluster.local` from a busybox Pod prints the Service's IP | `NXDOMAIN`: the name or namespace is wrong. `no servers could be reached`: CoreDNS is down or blocked. |
| Service | `kubectl get svc orders -o wide` shows the port and selector you expect | A typo in the name, the wrong namespace, or the wrong port |
| Selector | `kubectl get pods -l ` lists the backend Pods | No Pods listed, so the EndpointSlice is empty |
| Ready Pods | The READY column is full, and the EndpointSlice shows the Pods as ready | Pods are listed as not ready, so they get no traffic |
| targetPort | It equals the port the container listens on, by number or by name | The EndpointSlice lists Pods, but the client still gets `Connection refused` |
| NetworkPolicy | `kubectl get netpol`, then check that the policy's `from` matches the client | The client waits, then gives up: `download timed out` |
| kube-proxy | One Running kube-proxy Pod on every node | The Service IP fails from one node, while Pod IPs still work |

## Read the error first

The client's error tells you which stop to look at, so read it before any YAML. These are the errors `wget` prints in a busybox Pod on this lab:

| The client sees | The EndpointSlice | The likely cause |
| --- | --- | --- |
| `Connection refused` | Empty | The selector matches no Pod, or no Pod is Ready |
| `Connection refused` | Lists the Pods | The `targetPort` is wrong: nothing listens on that port |
| No answer, then `download timed out` | Lists the Pods | A NetworkPolicy drops the request (or the network is broken) |
| `bad address` | Any | DNS failed: the name is wrong, or CoreDNS is not answering |

- **Refused, with an empty slice:** on this lab kube-proxy runs in iptables mode. For a Service with no Pods, it adds a rule that rejects the call at once.
- **Refused, with Pods listed:** the request reaches a Pod, but nothing listens on that port, so the Pod refuses it.
- **A hang:** a NetworkPolicy drops the request and sends no answer at all, so the client waits until its timeout.

## The checklist as commands

Here is the same check as commands, for a Service `orders` in namespace `shop`. Run them top to bottom and stop at the first surprise.

**The checklist as commands (namespace shop, Service orders)**

```bash
# 1. Does the Service exist, and what does it select and forward to?
kubectl -n shop get svc orders -o wide
kubectl -n shop get svc orders -o jsonpath='{.spec.selector}{"\n"}{.spec.ports}{"\n"}'

# 2. Do Pods match that selector exactly, and are they Ready?
kubectl -n shop get pods -l app=orders -o wide --show-labels

# 3. Did the selector find Pods? The EndpointSlice lists them.
kubectl -n shop get endpointslices -l kubernetes.io/service-name=orders -o wide

# 4. Which port does the container say it listens on?
kubectl -n shop get pod -l app=orders -o jsonpath='{.items[0].spec.containers[*].ports}{"\n"}'

# 5. Is any NetworkPolicy selecting the backend Pods?
kubectl -n shop get netpol
kubectl -n shop describe netpol

# 6. Test from inside the cluster, by name and by Pod IP, with a short timeout.
kubectl -n shop run probe --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n shop exec probe -- wget -qO- -T 3 http://orders.shop.svc.cluster.local/
kubectl -n shop exec probe -- wget -qO- -T 3 http://<pod-ip>:8080/
```

<details>
<summary>Line-by-line explanation</summary>

- `get svc orders -o wide` — Checks that the Service exists in `shop` and shows its ClusterIP and ports. `-o wide` adds the SELECTOR column. `NotFound` means a typo in the name, or the wrong namespace.
- `get svc orders -o jsonpath` — Prints just two fields: the selector, such as `{"app":"orders"}`, and the ports, with `port` and `targetPort`. You compare these with the Pods next. `{"\n"}` adds a line break.
- `get pods -l app=orders` — Lists only the Pods that carry the selector's label. `No resources found` means the selector matches nothing. `--show-labels` shows every label, and `-o wide` adds the Pod IPs you use in step 6.
- `get endpointslices` — An **EndpointSlice** is the list of Pod IPs and ports a Service sends traffic to. You find it by its `kubernetes.io/service-name` label. No addresses under ENDPOINTS means no Ready Pod matched the selector.
- `get pod -l app=orders -o jsonpath` — Prints the ports declared by the containers of the first matching Pod (`items[0]`): each `containerPort` and its `name`. The Service's `targetPort` must equal one of those numbers or names.
- `get netpol` — Lists the namespace's NetworkPolicies. If there are none, nothing in `shop` filters traffic, and you can skip this stop.
- `describe netpol` — With no name given, it describes every policy in the namespace in plain words: which Pods it protects, and which sources and ports it allows. Compare those labels with the client's.
- `run probe` — Starts a test Pod named `probe`. `--restart=Never` means it is not restarted. Everything after `--` is its command: sleep for an hour, so you can exec into it. busybox has `wget` and `nslookup`.
- `wget -qO- -T 3 http://orders` — Calls the Service by its full DNS name from inside the cluster. `-q` is quiet, `-O-` prints the reply, and `-T 3` gives up after 3 seconds. `bad address` means DNS failed.
- `http://<pod-ip>:8080/` — The same call straight to one Pod's IP and container port, skipping DNS and the Service. If this works but the name does not, the app is fine and the fault is in the Service or DNS.

</details>

## Selector, targetPort and readiness

These three cause most Service faults. The first two tasks below test the selector and the targetPort.

- **Selector.** Every label in the selector must match a Pod label exactly, so `tier: backed` finds no Pod with `tier: backend`. Compare it with `kubectl get pods --show-labels`.
- **targetPort.** `port` is what clients call, and `targetPort` is the port the app listens on inside the Pod. If you leave `targetPort` out, it copies `port`. It can also be the container port's *name*, such as `http`. [Services](/cka/networking/services) shows how.
- **Readiness.** A Pod that fails its readiness probe stays in the EndpointSlice as not ready, and gets no traffic.

## NetworkPolicy, DNS and kube-proxy

- **NetworkPolicy.** Once a policy selects a Pod for ingress, only traffic that a policy allows gets in. Check that `podSelector` picks the backend, that `from` matches the client's labels, and that `ports` lists the *container* port. The policy sees the request after the Service has changed port 80 into 8080. So a rule for port 80 does nothing for an app on 8080.
- **DNS.** Test with the full name, `..svc.cluster.local`, from a busybox Pod. An egress policy that does not allow port 53 also breaks every lookup. [CoreDNS and service discovery](/cka/networking/coredns) explains DNS errors and fixes.
- **kube-proxy.** It runs one Pod per node and does the Service forwarding. So a broken kube-proxy Pod breaks Service IPs only for clients on its node.
- **NodePort.** The same Service, also opened on a port of every node. [Services](/cka/networking/services) shows how to test one.

**DNS and kube-proxy: the quick checks**

```bash
# The Pod's DNS settings
kubectl -n shop exec probe -- cat /etc/resolv.conf

# Look up the full name, then a name that always exists
kubectl -n shop exec probe -- nslookup orders.shop.svc.cluster.local
kubectl -n shop exec probe -- nslookup kubernetes.default.svc.cluster.local

# CoreDNS: its Pods, then their logs
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50

# kube-proxy: one Running Pod per node
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
```

<details>
<summary>Line-by-line explanation</summary>

- `cat /etc/resolv.conf` — Shows the Pod's DNS settings, which the kubelet wrote when the Pod started. The `nameserver` line should be the kube-dns Service IP, `10.96.0.10` on this lab.
- `nslookup orders.shop` — Asks CoreDNS for the full name, `..svc.cluster.local`. Success prints an Address equal to the Service's ClusterIP. `NXDOMAIN` means no such Service in that namespace. A timeout means CoreDNS cannot be reached.
- `nslookup kubernetes.default` — A control test: the `kubernetes` Service in `default` always exists. If it resolves but yours does not, DNS works and your name or namespace is wrong. If it fails too, DNS itself is broken.
- `get pods -l k8s-app=kube-dns` — CoreDNS Pods still carry the old label `k8s-app=kube-dns`. You want them Running and Ready, usually two. If none is Ready, every lookup in the cluster fails.
- `logs -l k8s-app=kube-dns --tail=50` — The last 50 lines from each CoreDNS Pod at once, since `-l` picks them by label. Look for `[ERROR]` or `[FATAL]` lines, such as timeouts to the upstream DNS server.
- `get pods -l k8s-app=kube-proxy -o wide` — Lists each kube-proxy Pod with its node. A missing or crashing one tells you which node's Service IPs stop working.

</details>

> [!IMPORTANT] **Fix only the object the question names**
> The grader reads the live objects. A task that says "fix the Service" often also checks that the Deployment is unchanged. A task that says "fix the NetworkPolicy" checks that the policy still exists and still blocks other Pods. Deleting the policy, or opening it to every Pod, makes the call work but fails the task. Change only the broken field with `kubectl edit` or `kubectl patch`. Then prove the fix with `wget -qO- -T 3` from a client Pod.

## 📝 Key Takeaways

- Check the path in order: DNS, Service, selector, Ready Pods, targetPort, NetworkPolicy. The first stop that fails is your fault.
- `Connection refused` with an empty EndpointSlice means the selector or readiness. Refused with Pods listed means the targetPort.
- A request that hangs until it times out usually means a NetworkPolicy drops it.
- `port` is what clients call. `targetPort` must be the port the app listens on.
- Fix only the object the question names, then test with a real request from a Pod.

**📖 Official documentation:**

- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) *(search: "debug services")*
- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) *(search: "debugging dns resolution")*
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) *(search: "network policy")*
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/) *(search: "service targetPort")*

---

### 🎯 Task: A Service that refuses connections

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

In namespace `tsx-svc`, requests from Pod `shell` to `http://orders.tsx-svc.svc.cluster.local/hostname` fail with *Connection refused*, although both `orders` Pods are Running. Find the fault and fix the Service `orders` so the request returns an `orders` Pod's hostname. Clients must keep using port 80. Do not modify the Deployment.

<details>
<summary>💡 Hints</summary>

- The error is refused, not timed out, so something answered. Does the EndpointSlice list Pods? Then check which port it points to.
- Compare the Service's targetPort with the containerPort in the Pod template. That container port has a name you can use.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n tsx-svc get svc orders -o wide
kubectl -n tsx-svc get endpointslices -l kubernetes.io/service-name=orders -o wide
kubectl -n tsx-svc get deploy orders -o jsonpath='{.spec.template.spec.containers[0].ports}'; echo
kubectl -n tsx-svc patch svc orders --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]'
for i in $(seq 1 15); do
  if kubectl -n tsx-svc exec shell -- wget -qO- -T 3 http://orders.tsx-svc.svc.cluster.local/hostname; then echo; break; fi
  sleep 2
done
```

**Explanation:**

- `get svc orders -o wide` — Start with the Service: it exists and its SELECTOR, `app=orders`, matches the Pods. PORT(S) shows only `80/TCP`, not the targetPort, so keep going.
- `get endpointslices` — Both Pod IPs are listed, so the selector and readiness are fine. But the PORTS column says 80, and that is where each request lands inside the Pods.
- `get deploy orders -o jsonpath` — Reads the container ports from the Deployment's Pod template: `containerPort` 8080, named `http`. Nothing listens on 80, hence *Connection refused*.
- `patch svc orders --type=json` — A JSON patch changes one exact path: the first port's (`/0/`, counting from zero) `targetPort` becomes the name `http`. `port: 80`, which clients dial, is untouched. `kubectl edit` does the same by hand.
- `for i in $(seq 1 15); do` — Retries up to 15 times, two seconds apart, because the change takes a moment to reach the EndpointSlice and kube-proxy. `seq 1 15` just counts 1 to 15 for the loop.
- `exec shell -- wget` — Fetches `/hostname` through the Service from Pod `shell`. agnhost replies with the serving Pod's name, such as `orders-…`; then `echo` adds a line break and `break` leaves the loop.

**Notes:** The EndpointSlice lists both Pod IPs, but on port 80. agnhost listens on 8080, so each Pod refuses the connection. On the exam, run `kubectl edit svc orders -n tsx-svc` and change `targetPort: 80` to `targetPort: http`. `8080` is also correct here. Leave `port: 80` alone, because that is the port clients call. Do not change the container's port instead. The question forbids changing the Deployment, and agnhost's port comes from its `--http-port=8080` argument anyway.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-svc

kubectl -n $ns get svc orders >/dev/null 2>&1 && p "service orders exists" || f "service orders exists"
tp=$(kubectl -n $ns get svc orders -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
{ [ "$tp" = "8080" ] || [ "$tp" = "http" ]; } && p "targetPort is the container port ($tp)" || f "targetPort is the container port (got '$tp')"
[ "$(kubectl -n $ns get svc orders -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)" = "80" ] && p "service port still 80" || f "service port still 80"
[ "$(kubectl -n $ns get deploy orders -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null)" = "8080" ] && p "deployment containerPort unchanged (8080)" || f "deployment containerPort unchanged (8080)"
out=""
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec shell -- wget -qO- -T 3 http://orders.tsx-svc.svc.cluster.local/hostname 2>/dev/null) && break
  out=""; sleep 2
done
echo "$out" | grep -q '^orders-' && p "shell reaches orders through the Service ($out)" || f "shell reaches orders through the Service"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A Service with no endpoints

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `tsx-sel`, the Service `catalog` sends no traffic anywhere, even though the two Pods of Deployment `catalog` are Running and Ready. Fix the Service so that both `catalog` Pods become its endpoints and `http://catalog.tsx-sel.svc.cluster.local/hostname` answers from Pod `shell`. Do not modify the Deployment.

<details>
<summary>💡 Hints</summary>

- kubectl get endpointslices -l kubernetes.io/service-name=catalog shows whether the selector found any Pod.
- Put the Service's selector next to the output of kubectl get pods --show-labels. Compare every letter.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n tsx-sel get endpointslices -l kubernetes.io/service-name=catalog
kubectl -n tsx-sel get svc catalog -o jsonpath='{.spec.selector}'; echo
kubectl -n tsx-sel get pods --show-labels
kubectl -n tsx-sel patch svc catalog --type=merge -p '{"spec":{"selector":{"app":"catalog","tier":"backend"}}}'
for i in $(seq 1 15); do
  n=$(kubectl -n tsx-sel get endpointslices -l kubernetes.io/service-name=catalog -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' | grep -c . || true)
  [ "$n" = "2" ] && break
  sleep 2
done
for i in $(seq 1 15); do
  if kubectl -n tsx-sel exec shell -- wget -qO- -T 3 http://catalog.tsx-sel.svc.cluster.local/hostname; then echo; break; fi
  sleep 2
done
```

**Explanation:**

- `get endpointslices -l kubernetes.io/service-name=catalog` — The slice exists but lists no addresses: the selector matched no Pod. The question says the Pods are Ready, so suspect the selector.
- `get svc catalog -o jsonpath` — Prints the selector as JSON: `{"app":"catalog","tier":"backed"}`.
- `get pods --show-labels` — The Pods carry `tier=backend`. One missing letter is enough: every pair in a selector must match, so no Pod is selected.
- `patch svc catalog --type=merge` — A merge patch merges this JSON into the live Service: keys you list are set, others are kept. Here it overwrites `tier` with the right value; the Deployment is not touched.
- `for i in $(seq 1 15); do` — Waits up to 30 seconds for both Pods to appear in the EndpointSlice before testing traffic.
- `n=$(kubectl` — Prints the first address of every endpoint, one per line, and `grep -c .` counts the non-empty lines. `|| true` stops grep's failure status, which it returns when the count is 0, from counting as an error.
- `[ "$n" = "2" ] && break` — Leaves the loop as soon as both Pods are endpoints.
- `exec shell -- wget` — The real test: the Service name now answers from Pod `shell` with a `catalog-…` Pod name.

**Notes:** The selector says `tier: backed`, but the Pods carry `tier: backend`. Every pair in a selector must match, so one wrong letter empties the EndpointSlice. Then kube-proxy rejects every call to the Service. On the exam, run `kubectl edit svc catalog -n tsx-sel` and correct the value. A merge patch only sets the keys you list. So it fixes a wrong *value*, but it leaves a wrong extra *key* in place. To remove a key, use `kubectl edit`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-sel

kubectl -n $ns get svc catalog >/dev/null 2>&1 && p "service catalog exists" || f "service catalog exists"
[ "$(kubectl -n $ns get deploy catalog -o jsonpath='{.spec.template.metadata.labels.tier}' 2>/dev/null)" = "backend" ] && p "pod template labels unchanged" || f "pod template labels unchanged"
names=$(kubectl -n $ns get endpointslices -l kubernetes.io/service-name=catalog -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.targetRef.name}{"\n"}{end}' 2>/dev/null | grep . | sort)
[ "$(echo "$names" | grep -c '^catalog-')" = "2" ] && p "2 ready endpoints, both catalog Pods" || f "2 ready endpoints, both catalog Pods"
[ -z "$(echo "$names" | grep -v '^catalog-' | grep .)" ] && p "no other Pods selected" || f "no other Pods selected"
out=""
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec shell -- wget -qO- -T 3 http://catalog.tsx-sel.svc.cluster.local/hostname 2>/dev/null) && break
  out=""; sleep 2
done
echo "$out" | grep -q '^catalog-' && p "shell reaches catalog through the Service ($out)" || f "shell reaches catalog through the Service"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: A NetworkPolicy that blocks the frontend

| Detail | Value |
| --- | --- |
| **Domain** | troubleshooting |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `tsx-netpol`, Pod `frontend` must be able to call Service `api` on port 80, but its requests hang until they time out. Pod `reports` must stay blocked from `api`. Fix this by correcting the existing NetworkPolicy `api-ingress`. Do not delete it, do not add other policies and do not change any Pod's labels.

<details>
<summary>💡 Hints</summary>

- A hang, not a refusal, points at a NetworkPolicy. Read api-ingress with kubectl describe netpol.
- Compare the policy's from.podSelector with kubectl get pod frontend --show-labels.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n tsx-netpol get netpol
kubectl -n tsx-netpol describe netpol api-ingress
kubectl -n tsx-netpol get pods --show-labels
kubectl -n tsx-netpol patch netpol api-ingress --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/from/0/podSelector/matchLabels","value":{"app":"frontend"}}]'
for i in $(seq 1 15); do
  if kubectl -n tsx-netpol exec frontend -- wget -qO- -T 3 http://api.tsx-netpol.svc.cluster.local/hostname; then echo; break; fi
  sleep 2
done
```

**Explanation:**

- `get netpol` — One policy, `api-ingress`. Its POD-SELECTOR column, `app=api`, says it guards the backend Pods.
- `describe netpol api-ingress` — Spells out the rule: ingress to `app=api` Pods is allowed only from Pods labeled `app=front-end`, on TCP 8080. Everything else is dropped.
- `get pods --show-labels` — The client is labeled `app=frontend`, without the dash, so no rule allows it. Dropped packets get no reply, which is why the request hangs instead of being refused.
- `patch netpol api-ingress --type=json` — Edits only the policy, as the question demands. The trailing `\` continues the command on the next line.
- `-p='[{"op":"replace"` — Replaces the `matchLabels` of the first source in the first ingress rule with `app: frontend`. Port 8080 and the policy's target stay the same, and `reports` still matches no rule, so it stays blocked.
- `exec frontend -- wget` — Retries the call from `frontend` until it returns an `api-…` Pod name; a policy change takes a few seconds to reach the nodes.

**Notes:** The policy allows `app: front-end`, but the Pod is labeled `app: frontend`. On the exam, run `kubectl edit netpol api-ingress -n tsx-netpol` and fix the value. Keep `port: 8080`. The policy sees the Pod's port, after the Service has turned 80 into 8080. Allowing `tier: web` instead would also let only the frontend in. But this task checks for `app: frontend`, so correct the label the author meant.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=tsx-netpol
np="kubectl -n $ns get netpol api-ingress -o jsonpath"

kubectl -n $ns get netpol api-ingress >/dev/null 2>&1 && p "policy api-ingress still exists" || f "policy api-ingress still exists"
[ "$(kubectl -n $ns get netpol --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "1" ] && p "no extra policies" || f "no extra policies"
[ "$($np='{.spec.podSelector.matchLabels.app}' 2>/dev/null)" = "api" ] && p "policy still selects app=api" || f "policy still selects app=api"
$np='{.spec.ingress[*].from[*].podSelector.matchLabels.app}' 2>/dev/null | tr ' ' '\n' | grep -qx frontend && p "from.podSelector allows app=frontend" || f "from.podSelector allows app=frontend"
[ "$(kubectl -n $ns get pod frontend -o jsonpath='{.metadata.labels.app}' 2>/dev/null)" = "frontend" ] && p "frontend labels unchanged" || f "frontend labels unchanged"
out=""
for i in 1 2 3 4 5; do
  out=$(kubectl -n $ns exec frontend -- wget -qO- -T 3 http://api.tsx-netpol.svc.cluster.local/hostname 2>/dev/null) && break
  out=""; sleep 2
done
echo "$out" | grep -q '^api-' && p "frontend reaches api ($out)" || f "frontend reaches api"
kubectl -n $ns exec reports -- wget -qO- -T 3 http://api.tsx-netpol.svc.cluster.local/hostname >/dev/null 2>&1 && f "reports is still blocked" || p "reports is still blocked"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 5: Troubleshooting*
