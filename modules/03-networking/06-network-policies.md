# NetworkPolicies

> **Module 3** · Lesson 3.6 · 45 minutes

How NetworkPolicies control which Pods may talk, how peers and ports combine, why egress breaks DNS, and how to test a policy.

## Learning Objectives

- You can write default-deny policies for incoming and outgoing traffic, then open exactly the connections a question asks for.
- You can tell an AND peer from an OR peer at a glance, and select Pods in other namespaces by namespace label.
- You can test a policy from an allowed Pod and a denied Pod, with timeouts, in under a minute.


By default, every Pod can connect to every other Pod. A **NetworkPolicy** is a firewall rule for Pods: it says who may connect to them, or where they may connect to. For example: only the `frontend` Pods may reach the `backend` Pods, and only on port 8080. The exam topic is **Define and enforce Network Policies**.

It is a common task, and easy to get almost right. The API accepts any well-formed policy. Whether it does what the question meant depends on one dash in the YAML, on remembering DNS, and on testing it. Also, a policy only works if the CNI plugin enforces it. Calico in this lab does; Flannel on its own ignores policies without any warning.

## The rules of isolation

Five rules explain how every NetworkPolicy behaves:

- **A policy picks Pods in its own namespace.** Its `podSelector` chooses them, and `podSelector: {}` means every Pod in the namespace.
- **No policy means open.** A Pod that no policy selects allows all traffic. Once a policy selects it for `Ingress` (or `Egress`), the Pod is **isolated** in that direction. Then only traffic that some policy allows gets through.
- **Policies only add.** There are no deny rules. A Pod allows everything that any of its policies allows, added together.
- **Set `policyTypes` yourself.** It says which directions the policy controls. If you leave it out, `Ingress` is always included, but `Egress` only when the policy has an `egress` section.
- **Replies are always allowed.** A policy only decides who may *open* a connection. For Pod A to reach Pod B, A's egress and B's ingress must both allow it.

**Both ends must say yes**

*Each end checks only if a policy selects it for that direction. A Pod with no policy says yes to everything.*

`Pod A` — opens the connection → `A's egress rules` — may A connect to B? → `B's ingress rules` — may B accept A? → `Pod B` — receives it

Most tasks start from a **default deny**: a policy that selects every Pod and allows nothing. Here are the common starting points:

**The three baseline policies**

```yaml
# Deny all incoming traffic to every Pod in the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: nw-netpol
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
# Deny all traffic in both directions (remember DNS, see below)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nw-netpol
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
# Allow all incoming traffic (overrides an isolation for the Pods it selects)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: nw-netpol
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress:
    - {}
```

<details>
<summary>Line-by-line explanation</summary>

- `apiVersion: networking.k8s.io/v1` — NetworkPolicy is in the `networking.k8s.io` group, like Ingress.
- `podSelector: {}` — Which Pods in `nw-netpol` this policy applies to. `{}` is an empty selector, and empty means all of them.
- `policyTypes: ["Ingress"]` — Isolates the selected Pods for incoming traffic. With no `ingress` rules to allow anything, every incoming connection is dropped.
- `policyTypes: ["Ingress", "Egress"]` — Isolates both directions with no rules at all: nothing in, nothing out, not even DNS lookups.
- `ingress:` — This time there is a rule list, so the policy allows traffic instead of only isolating.
- `- {}` — One empty rule: no `from` and no `ports`, so it matches every source on every port. Because policies add up, it cancels any ingress deny for the Pods it selects.

</details>

## Peers: who is allowed

A **peer** is an allowed source (under `from`) or destination (under `to`). You can pick peers in four ways:

| Peer in from / to | Selects |
| --- | --- |
| `podSelector` alone | Matching Pods in the policy's own namespace |
| `namespaceSelector` alone | Every Pod in the namespaces whose labels match |
| `namespaceSelector` and `podSelector` in one entry | Matching Pods in matching namespaces: both must match (AND) |
| `ipBlock` (`cidr`, `except`) | A range of IPs, for traffic to or from outside the cluster. Do not use it for Pods, because their IPs change. |

The classic trap is the third row. The two rules below differ by one dash, and they mean different things:

**One dash changes the meaning**

```yaml
ingress:
  - from:
      - namespaceSelector:          # ONE peer: Pods labeled role=monitor
          matchLabels:              # AND in namespace "observability"
            kubernetes.io/metadata.name: observability
        podSelector:
          matchLabels:
            role: monitor
---
ingress:
  - from:
      - namespaceSelector:          # TWO peers: every Pod in "observability"
          matchLabels:
            kubernetes.io/metadata.name: observability
      - podSelector:                # OR Pods labeled role=monitor in this namespace
          matchLabels:
            role: monitor
```

<details>
<summary>Line-by-line explanation</summary>

- `- from:` — `from` is the list of allowed sources. What matters is how many entries it has, and the dashes decide that.
- `- namespaceSelector:` — The only dash in this list, so `namespaceSelector` and the `podSelector` below sit in one entry and must both match.
- `kubernetes.io/metadata.name: observability` — Selects the namespace by name, using the label the API server puts on every namespace automatically.
- `podSelector:` — No dash, and indented level with `namespaceSelector`: it belongs to the same entry. Together they mean Pods labeled `role=monitor` inside `observability`.
- `- namespaceSelector:` — Here it is the first of two entries: every Pod in `observability`, whatever its labels.
- `- podSelector:` — A second dash, so a second, separate entry: Pods labeled `role=monitor` in the policy's own namespace. Matching either entry is enough to get in.

</details>

Every namespace gets the label `kubernetes.io/metadata.name=` automatically, and it cannot be changed. Use it to pick a namespace by name, without labeling anything. If the question names its own label, such as `team=payments`, check it with `kubectl get ns --show-labels`. Add it with `kubectl label ns` only if the question says to.

## Ports

`ports` sits next to `from` (or `to`) in the same rule. Four things to know:

- It matches the **Pod's** port. kube-proxy has already turned the Service address into a Pod address. So a Service on port 80 with `targetPort: 8080` needs a policy that allows 8080.
- `protocol` is TCP when you leave it out.
- `port` can also be the name of a container port, such as `http`.
- A rule with `from` but no `ports` allows every port. A rule with `ports` but no `from` allows every source on those ports.

**How an allow rule is built**

*Start from a default deny, then open one door at a time. This is the policy below.*

`Protect these Pods` — the top-level podSelector (`app: backend`) → `Allow from` — a podSelector or namespaceSelector (`app: frontend`) → `On these ports` — the Pod's own port (`8080/TCP`)

**frontend may reach backend on 8080, nothing else may**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: nw-netpol
spec:
  podSelector:
    matchLabels:
      app: backend               # the policy protects the backend Pods
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
```

<details>
<summary>Line-by-line explanation</summary>

- `podSelector:` — The Pods this policy protects, chosen by label in the policy's own namespace. The rules below say who may reach them.
- `policyTypes: ["Ingress"]` — Only incoming traffic is restricted; what the backend Pods send out stays open.
- `- from:` — One rule. Its sources and its ports must both match for a connection to be allowed.
- `app: frontend` — The allowed source: Pods labeled `app=frontend` in this same namespace, since there is no namespaceSelector.
- `port: 8080` — The Pod's port, not a Service port. Anything else, even from frontend, is dropped, because the backend Pods are now isolated.

</details>

## Egress and the DNS exception

Once a Pod is isolated for egress, it cannot reach CoreDNS either. Every connection by name then fails with *bad address* before it even starts. So almost every egress policy needs a DNS rule: port 53, over UDP *and* TCP. Allow it to the CoreDNS Pods, as below. Allowing port 53 to any destination is simpler, and also accepted unless the question says otherwise.

**Egress: DNS plus one destination**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
  namespace: nw-egress
spec:
  podSelector:
    matchLabels:
      role: client
  policyTypes: ["Egress"]
  egress:
    - to:                                   # DNS, to the CoreDNS Pods only
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:                                   # the api Pods, on their container port
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 8080
```

<details>
<summary>Line-by-line explanation</summary>

- `role: client` — The policy applies to the client Pods, so it controls what *they* may connect to.
- `policyTypes: ["Egress"]` — Isolates outgoing traffic only. From now on the clients can open only the connections an `egress` rule allows.
- `- to:` — Rule one, the DNS rule. `to` lists destinations, the egress twin of `from`.
- `- namespaceSelector:` — One entry with both selectors (a single dash), so it means the kube-dns Pods inside `kube-system`, not every Pod there.
- `k8s-app: kube-dns` — The label the CoreDNS Pods carry. Check it with `kubectl -n kube-system get pods --show-labels`.
- `protocol: UDP` — DNS uses UDP port 53 for most lookups and TCP port 53 for large answers, so allow both.
- `- to:` — Rule two: the api Pods, chosen by label in this namespace.
- `port: 8080` — The container port. A Service in front of these Pods may listen on 80, but the policy sees the Pod's port, after kube-proxy has translated the address.

</details>

## Prove it works

Never trust a policy you have not tested. Test from one Pod that should get in, and from one that should not. Use `wget -T 3`, so a blocked connection fails after 3 seconds instead of hanging.

**Prove it: one allowed client, one denied client**

```bash
kubectl -n nw-netpol get netpol
kubectl -n nw-netpol describe netpol allow-frontend      # reads the selectors back in plain English

# -T 3 makes a blocked connection fail in 3 seconds instead of hanging
kubectl -n nw-netpol exec frontend -- wget -qO- -T 3 http://backend:8080/hostname   # expect a name
kubectl -n nw-netpol exec intruder -- wget -qO- -T 3 http://backend:8080/hostname   # expect "download timed out"

# Blocked looks like a timeout; "connection refused" means the policy allowed it and nothing listens
kubectl -n nw-egress exec client -- nslookup api.nw-egress.svc.cluster.local         # DNS still works?
```

<details>
<summary>Line-by-line explanation</summary>

- `get netpol` — `netpol` is the short name for NetworkPolicies. The POD-SELECTOR column shows which Pods each policy covers.
- `describe netpol allow-frontend` — Spells the policy out in words: which Pods it applies to, who is allowed in, and on which ports.
- `exec frontend --` — From the allowed client: a Pod name comes back.
- `exec intruder --` — From a client the policy does not allow: the connection is dropped, so wget gives up after 3 seconds.
- `nslookup api.nw-egress` — After an egress policy, check DNS on its own. If this fails while connections by IP work, the DNS rule is missing or wrong.

</details>

| What you see | What it means |
| --- | --- |
| A reply | The connection is allowed |
| *download timed out* | A policy blocks it |
| *connection refused* | The traffic got through, but nothing listens on that port, or the Service has no Pods |
| *bad address* | The name did not resolve. After an egress policy, the DNS rule is missing or wrong. |

> [!IMPORTANT] **What the grader reads**
> The grader usually checks two things: the policy fields (`podSelector`, `policyTypes`, peers, ports) and real connections. So test from an allowed Pod and a denied Pod. Put the policy in the namespace of the Pods it protects, not the clients' namespace. If the task says "only", look for an old allow-all policy there. Policies add up, so it would stop your new one from blocking anything.

## 📝 Key Takeaways

- A Pod with no policy accepts everything. Once a policy selects it, only what some policy allows gets in (or out).
- Policies only add up. There are no deny rules, so start from a default deny and open what you need.
- One entry with `namespaceSelector` and `podSelector` means AND. Two entries (two dashes) mean OR.
- Ports in a policy are the Pod's ports, such as 8080, not the Service's port.
- Every egress policy needs DNS: UDP and TCP port 53. Then test from an allowed Pod and a denied Pod.

**📖 Official documentation:**

- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) *(search: "network policies")*
- [Declare Network Policy](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/) *(search: "declare network policy")*
- [Well-Known Labels: kubernetes.io/metadata.name](https://kubernetes.io/docs/reference/labels-annotations-taints/#kubernetes-io-metadata-name) *(search: "kubernetes.io/metadata.name")*

---

### 🎯 Task: Default deny, then allow one client

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `nw-netpol`, create a NetworkPolicy named `default-deny-ingress` that blocks all incoming traffic to every Pod in the namespace. Then create a NetworkPolicy named `allow-frontend` that lets Pods labeled `app=frontend` connect to Pods labeled `app=backend` on TCP port 8080, and nothing else. Afterwards `frontend` must reach `http://backend:8080/hostname` and `intruder` must not.

<details>
<summary>💡 Hints</summary>

- Default deny: an empty podSelector, policyTypes [Ingress], and no ingress rules.
- allow-frontend selects the backend Pods. The frontend goes under ingress.from.

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: nw-netpol
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: nw-netpol
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
YAML
sleep 3
kubectl -n nw-netpol exec frontend -- wget -qO- -T 3 http://backend:8080/hostname; echo
kubectl -n nw-netpol exec intruder -- wget -qO- -T 3 http://backend:8080/hostname || echo "intruder blocked, as intended"
```

**Explanation:**

- `cat <<'YAML' | kubectl apply -f -` — Both policies in one heredoc, applied together.
- `podSelector: {}` — The deny policy covers every Pod in `nw-netpol`.
- `policyTypes: ["Ingress"]` — Isolates incoming traffic and lists no rules, so nothing gets in until another policy allows it.
- `app: backend` — The second policy protects the backend Pods: the top-level `podSelector` picks the destination, not the client.
- `app: frontend` — The client that may connect, under `ingress.from`.
- `port: 8080` — And only on TCP 8080, the backend's port.
- `sleep 3` — Gives Calico a moment to program the rules before you test.
- `exec frontend --` — The allowed client: prints `backend`, the Pod's name.
- `exec intruder --` — The denied client times out. `||` runs the `echo` only when wget fails, so the expected failure prints a friendly line.

**Notes:** Copy the default-deny example from the Network Policies docs page, then write a second policy for the allow rule. One policy could do both, but the question names two. The frontend can still look up `backend`: only incoming traffic is restricted, and CoreDNS lives in another namespace. Test from both Pods. A policy with `app: frontend` in the wrong place (say, as the top-level `podSelector`) applies without error and protects nothing.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-netpol
d="kubectl -n $ns get netpol default-deny-ingress -o jsonpath"
a="kubectl -n $ns get netpol allow-frontend -o jsonpath"

kubectl -n $ns get netpol default-deny-ingress >/dev/null 2>&1 && p "default-deny-ingress exists" || f "default-deny-ingress exists"
[ "$($d='{.spec.podSelector}' 2>/dev/null)" = "{}" ] && p "default-deny selects every pod" || f "default-deny selects every pod"
$d='{.spec.policyTypes}' 2>/dev/null | grep -q Ingress && [ -z "$($d='{.spec.ingress}' 2>/dev/null)" ] && p "default-deny isolates ingress with no rules" || f "default-deny isolates ingress with no rules"
[ "$($a='{.spec.podSelector.matchLabels.app}' 2>/dev/null)" = "backend" ] && p "allow-frontend protects app=backend" || f "allow-frontend protects app=backend"
[ "$($a='{.spec.ingress[*].from[*].podSelector.matchLabels.app}' 2>/dev/null)" = "frontend" ] && p "allow-frontend admits app=frontend only" || f "allow-frontend admits app=frontend only"
[ "$($a='{.spec.ingress[*].ports[*].port}' 2>/dev/null)" = "8080" ] && p "allow-frontend limited to port 8080" || f "allow-frontend limited to port 8080"
ok=""; for i in 1 2 3; do kubectl -n $ns exec frontend -- wget -qO- -T 3 http://backend:8080/hostname 2>/dev/null | grep -q '^backend$' && { ok=1; break; }; sleep 2; done
[ -n "$ok" ] && p "frontend reaches backend:8080" || f "frontend reaches backend:8080"
blocked=""; for i in 1 2 3; do kubectl -n $ns exec intruder -- wget -qO- -T 3 http://backend:8080/hostname >/dev/null 2>&1 || { blocked=1; break; }; sleep 2; done
[ -n "$blocked" ] && p "intruder is blocked" || f "intruder is blocked"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Lock down egress except DNS and one Service

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

In namespace `nw-egress`, create a NetworkPolicy named `client-egress` for Pods labeled `role=client`. Those Pods may make DNS lookups (UDP and TCP port 53) and may connect to the Pods behind Service `api`. All other outgoing traffic from them must be blocked. Afterwards Pod `client` must get an answer from `http://api/hostname` and must not reach `http://other/hostname`.

<details>
<summary>💡 Hints</summary>

- policyTypes: [Egress]. Two egress rules: one for port 53, one for the api Pods.
- The Service listens on 80, but the policy sees the Pod's port. Check the Service's targetPort.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n nw-egress get svc api -o jsonpath='{.spec.ports[0].port} -> {.spec.ports[0].targetPort}'; echo
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
  namespace: nw-egress
spec:
  podSelector:
    matchLabels:
      role: client
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - podSelector:
            matchLabels:
              app: api
      ports:
        - protocol: TCP
          port: 8080
YAML
sleep 3
kubectl -n nw-egress exec client -- wget -qO- -T 3 http://api/hostname; echo
kubectl -n nw-egress exec client -- wget -qO- -T 3 http://other/hostname || echo "other blocked, as intended"
```

**Explanation:**

- `get svc api -o jsonpath` — Prints the Service's port and targetPort side by side (`80 -> 8080`). The policy must allow the targetPort, 8080.
- `cat <<'YAML' | kubectl apply -f -` — The egress policy, applied from a heredoc.
- `role: client` — Applies to the client Pods only.
- `policyTypes: ["Egress"]` — Isolates their outgoing traffic; incoming stays open.
- `- namespaceSelector:` — First rule: DNS, to the CoreDNS Pods in `kube-system`. Both selectors sit in one entry, so both must match.
- `protocol: UDP` — Port 53 over UDP and, in the next entry, over TCP.
- `app: api` — Second rule: the Pods behind Service `api`, selected by the same label the Service uses.
- `port: 8080` — Their container port, the Service's targetPort.
- `sleep 3` — A moment for the policy to take effect.
- `http://api/hostname; echo` — Must print `api`: DNS worked and the api rule let the connection through.
- `|| echo "other blocked` — Must fail, because no rule allows `other`. The `echo` after `||` runs only on that failure.

**Notes:** Two traps. First, allowing port 80 because the Service says 80: a NetworkPolicy sees the Pod's port, 8080. Second, forgetting DNS: then `wget http://api` fails with *bad address*, even though the api rule is right. Select the api Pods by label (`app: api`, as the Service does), not with an `ipBlock`: Pod IPs change. A plain `ports: [53/UDP, 53/TCP]` rule with no `to` also counts as "DNS lookups" here.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-egress
n="kubectl -n $ns get netpol client-egress -o jsonpath"

kubectl -n $ns get netpol client-egress >/dev/null 2>&1 && p "client-egress exists" || f "client-egress exists"
[ "$($n='{.spec.podSelector.matchLabels.role}' 2>/dev/null)" = "client" ] && p "selects role=client" || f "selects role=client"
$n='{.spec.policyTypes}' 2>/dev/null | grep -q Egress && p "isolates egress" || f "isolates egress"
$n='{.spec.egress[*].ports[?(@.port==53)].protocol}' 2>/dev/null | grep -q UDP && p "allows DNS over UDP 53" || f "allows DNS over UDP 53"
$n='{.spec.egress[*].ports[?(@.port==53)].protocol}' 2>/dev/null | grep -q TCP && p "allows DNS over TCP 53" || f "allows DNS over TCP 53"
ok=""; for i in 1 2 3; do kubectl -n $ns exec client -- wget -qO- -T 3 http://api/hostname 2>/dev/null | grep -q '^api$' && { ok=1; break; }; sleep 2; done
[ -n "$ok" ] && p "client reaches api by name" || f "client reaches api by name"
blocked=""; for i in 1 2 3; do kubectl -n $ns exec client -- wget -qO- -T 3 http://other/hostname >/dev/null 2>&1 || { blocked=1; break; }; sleep 2; done
[ -n "$blocked" ] && p "client cannot reach other" || f "client cannot reach other"
oip=$(kubectl -n $ns get pod other -o jsonpath='{.status.podIP}' 2>/dev/null)
blocked=""; [ -n "$oip" ] && for i in 1 2 3; do kubectl -n $ns exec client -- wget -qO- -T 3 "http://$oip:8080/hostname" >/dev/null 2>&1 || { blocked=1; break; }; sleep 2; done
[ -n "$blocked" ] && p "client cannot reach other by pod IP" || f "client cannot reach other by pod IP"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
