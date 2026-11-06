# CoreDNS and service discovery

> **Module 3** · Lesson 3.3 · 40 minutes

How Services and Pods get DNS names, how a Pod looks them up, and how to change the Corefile safely.

## Learning Objectives

- You can predict the DNS name of any Service, headless Service or Pod, and look it up from a client Pod.
- You can set dnsPolicy and dnsConfig on a Pod, and check the result in its /etc/resolv.conf.
- You can read the CoreDNS Corefile and change it safely.


Inside a cluster, apps find each other by name. Your frontend calls `http://api`, and DNS turns `api` into the Service's IP. **CoreDNS** is the DNS server that answers. It runs as a Deployment in `kube-system`, behind a Service called `kube-dns`, and one ConfigMap holds its settings. The exam topic is **Understand and use CoreDNS**.

**How a Pod looks up a name**

*CoreDNS reads Services and Pods from the API, so a new Service has a name within seconds.*

`Your app` — looks up the name inventory → `/etc/resolv.conf` — in every Pod; says where to ask (`nameserver 10.96.0.10`) → `CoreDNS` — behind the kube-dns Service, at 10.96.0.10 → `The answer` — the ClusterIP of Service inventory

## The names CoreDNS answers

Every Service gets a name made of its own name, its namespace and `svc.cluster.local`. For Service `inventory` in namespace `nw-dns`, that is `inventory.nw-dns.svc.cluster.local`. In the table, an *A record* is a DNS answer that maps a name to an IP.

| Object | Name | DNS answers with |
| --- | --- | --- |
| Service (ClusterIP) | `..svc.cluster.local` | An A record: the ClusterIP |
| Headless Service | `..svc.cluster.local` | One A record per ready Pod IP |
| StatefulSet Pod behind a headless Service | `...svc.cluster.local` | An A record: that Pod's IP |
| ExternalName Service | `..svc.cluster.local` | A CNAME (an alias) to `spec.externalName` |
| Any Pod | `..pod.cluster.local` (its IP, with dashes) | An A record: that IP |

## What a Pod's resolver does

The kubelet writes a file called `/etc/resolv.conf` into every Pod. It tells the Pod where to send lookups, and how to finish short names.

```bash
kubectl -n nw-dns exec client -- cat /etc/resolv.conf
# search nw-dns.svc.cluster.local svc.cluster.local cluster.local
# nameserver 10.96.0.10
# options ndots:5

kubectl -n kube-system get svc kube-dns      # 10.96.0.10: the ClusterIP of CoreDNS
```

<details>
<summary>Line-by-line explanation</summary>

- `cat /etc/resolv.conf` — Prints the resolver config inside the Pod. The three comment lines below are what it shows on this lab.
- `# search` — The search list: a short name is tried with each suffix in turn, so `inventory` becomes `inventory.nw-dns.svc.cluster.local`.
- `# nameserver` — Where every lookup goes: the kube-dns Service.
- `# options ndots:5` — Names with fewer than five dots get the search suffixes tried first. Short cluster names resolve fast; external names pay for it, as the list below shows.
- `get svc kube-dns` — Confirms the nameserver IP. The CoreDNS Service is still called `kube-dns`, after the older DNS add-on it replaced, so existing setups keep working.

</details>

- `nameserver 10.96.0.10` is the ClusterIP of the `kube-dns` Service. Every lookup goes there.
- `search` lists the endings tried for a short name. That is why `inventory` works inside `nw-dns`, and `inventory.nw-dns` works from any namespace.
- `ndots:5` means a name with fewer than five dots gets each search ending tried *first*. So `api.example.com` costs three failed cluster lookups before the real one. A dot at the end (`api.example.com.`) skips the search list.

## dnsPolicy and dnsConfig

Two Pod fields change that file. `dnsPolicy` picks where lookups go. `dnsConfig` adds your own settings on top.

| dnsPolicy | Where the Pod's lookups go |
| --- | --- |
| `ClusterFirst` (the default) | To CoreDNS, with the cluster search list. CoreDNS passes names outside the cluster on to the upstream DNS servers. |
| `Default` | To the node's own DNS servers, from the node's resolv.conf. Despite its name, this is **not** the default. |
| `ClusterFirstWithHostNet` | To CoreDNS, for a Pod with `hostNetwork: true`. Without it, such a Pod falls back to `Default`. |
| `None` | Nowhere automatic. Everything comes from `dnsConfig`, which must then list at least one nameserver. |

**dnsConfig merges into what the policy generates**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resolver
  namespace: nw-dnscfg
spec:
  dnsPolicy: ClusterFirst      # dnsPolicy and dnsConfig are immutable: change the manifest and
  dnsConfig:                   # recreate the Pod (kubectl replace --force -f), or edit a Deployment template
    searches:
      - corp.internal          # appended after the cluster search domains
    options:
      - name: ndots
        value: "2"             # value is a string
      - name: timeout
        value: "2"
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sleep", "3600"]
```

<details>
<summary>Line-by-line explanation</summary>

- `dnsPolicy: ClusterFirst` — The default policy, written out: lookups go to CoreDNS with the cluster search list. `dnsConfig` below adds to that rather than replacing it.
- `dnsConfig:` — Extra resolver settings merged into the Pod's generated `/etc/resolv.conf`. It can hold `nameservers`, `searches` and `options`.
- `- corp.internal` — Each search domain is a list entry. A short name such as `db` is now also tried as `db.corp.internal`.
- `options:` — Each option is a `name` with an optional `value`, and each one ends up on the `options` line of resolv.conf.
- `value: "2"` — Quoted on purpose: the field is a string, and an unquoted `2` is a number the API rejects.
- `name: timeout` — Waits at most 2 seconds for an answer before trying again.

</details>

## The Corefile

CoreDNS reads its settings from a file called the **Corefile**, stored in the `coredns` ConfigMap in `kube-system`. Each line inside the block turns on one plugin. Here is the one in this lab:

**kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'**

```text
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
```

<details>
<summary>Line-by-line explanation</summary>

- `.:53 {` — A server block: `.` is the root zone, so every name, and `53` is the DNS port. Each line inside turns on a plugin, up to the matching `}` at the end.
- `errors` — Logs errors to the container's output, where `kubectl logs` shows them.
- `health {` — Serves `/health` on port 8080, which the CoreDNS Pods' liveness probe calls.
- `lameduck 5s` — On shutdown, keeps answering for 5 more seconds, so lookups in flight during a restart still succeed.
- `ready` — Serves `/ready` on port 8181 for the readiness probe. Until it reports ready, the Pod gets no traffic from the kube-dns Service.
- `kubernetes cluster.local` — The plugin that answers Service and Pod names from the API, for `cluster.local` plus the reverse zones (`in-addr.arpa` for IPv4, `ip6.arpa` for IPv6) that turn an IP back into a name.
- `pods insecure` — Answers `a-b-c-d..pod.cluster.local` with the IP written in the name, without checking that such a Pod exists. That missing check is the *insecure* part.
- `fallthrough in-addr.arpa` — A reverse lookup for an IP the cluster does not know is passed on to the next plugins instead of being answered with "no such name".
- `ttl 30` — Clients may cache these answers for 30 seconds.
- `prometheus :9153` — Exposes metrics for Prometheus on port 9153.
- `forward . /etc/resolv.conf {` — Sends every other name upstream, to the nameservers in the resolv.conf the CoreDNS Pod got from its node.
- `max_concurrent 1000` — Caps the queries waiting on upstream servers at 1000, so a slow upstream cannot pile up unlimited work.
- `cache 30 {` — Caches answers for up to 30 seconds.
- `disable success cluster.local` — Except positive answers for `cluster.local`: a changed Service resolves to its new address right away.
- `disable denial cluster.local` — And negative ones: a Service you just created is not stuck as "no such name" because of a lookup a moment earlier.
- `loop` — Detects CoreDNS forwarding queries back to itself and stops the process, so the Pod crash-loops with a clear log line. A common cause is a node resolv.conf that points at a local address such as 127.0.0.53.
- `reload` — Rereads the Corefile when it changes. ConfigMap updates reach the Pod's file with a delay, hence the minute or two.
- `loadbalance` — Shuffles the order of the A records in each answer, a simple round robin across a headless Service's Pod IPs.

</details>

You do not need every line. These are the ones exam tasks touch:

- `kubernetes` answers names in `cluster.local`, from the Services and Pods in the API.
- `forward . /etc/resolv.conf` sends every other name to the DNS servers of the node CoreDNS runs on.
- `cache 30` keeps answers for up to 30 seconds. Here it skips `cluster.local` names, so only outside names can lag behind a change.
- `hosts` is not there by default. It serves fixed name-to-IP entries. Always add `fallthrough`, so names it does not list still reach the next plugin.
- `reload` rereads the Corefile when the ConfigMap changes. That can take a minute or two, so restart CoreDNS instead of waiting.

Every Pod in the cluster depends on this file, and one typo breaks DNS everywhere. So change it in four steps: back it up, edit it, restart CoreDNS, and check the logs.

**Changing it safely**

```bash
# Keep a copy first. Every Pod in the cluster depends on this file.
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/cka/Corefile.bak

kubectl -n kube-system edit cm coredns      # e.g. add, inside .:53 { … }:
#    hosts {
#       10.10.10.10 legacy-db.corp.internal
#       fallthrough
#    }

# Apply now instead of waiting for reload, then make sure both replicas come back
kubectl -n kube-system rollout restart deploy coredns
kubectl -n kube-system rollout status deploy coredns --timeout=120s
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20     # a syntax error shows up here

# Roll back if it went wrong
kubectl -n kube-system create cm coredns --from-file=Corefile=/tmp/cka/Corefile.bak --dry-run=client -o yaml | kubectl replace -f -
kubectl -n kube-system rollout restart deploy coredns
```

<details>
<summary>Line-by-line explanation</summary>

- `> /tmp/cka/Corefile.bak` — Saves the current Corefile before you touch it. `{.data.Corefile}` prints that one key of the ConfigMap as plain text.
- `edit cm coredns` — Opens the ConfigMap in your editor. The Corefile is a multi-line string under `data`: keep its indentation, then save and quit (`:wq` in vim) to apply.
- `#    hosts {` — The `hosts` plugin serves fixed name-to-IP entries, in the same format as `/etc/hosts`.
- `#       fallthrough` — Without this line, `hosts` answers "no such name" for every name it does not list, and the rest of cluster DNS stops working.
- `rollout restart deploy coredns` — Replaces the CoreDNS Pods one by one, so the new ones load the edited Corefile now instead of whenever `reload` notices.
- `rollout status deploy coredns` — Waits until every replica is back and Ready. A new Pod that keeps crashing means the Corefile has an error.
- `logs -l k8s-app=kube-dns --tail=20` — The last 20 log lines of each CoreDNS Pod, picked by their label (still `kube-dns`, for history's sake). A Corefile error is reported here.
- `create cm coredns --from-file=Corefile=` — Rebuilds the ConfigMap from your backup: `Corefile=` names the key, `--dry-run=client -o yaml` prints it, and `kubectl replace -f -` overwrites the live ConfigMap with it.
- `rollout restart deploy coredns` — Restart once more so the Pods load the restored file.

</details>

## Running a lookup

To test DNS, run `nslookup` from a client Pod in the namespace you care about. The `busybox:1.36` image has it.

```bash
kubectl -n nw-dns run client --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n nw-dns wait --for=condition=Ready pod/client --timeout=60s

kubectl -n nw-dns exec client -- nslookup inventory.nw-dns.svc.cluster.local   # one Service
kubectl -n nw-dns exec client -- nslookup inventory-pods.nw-dns.svc.cluster.local   # headless: one line per Pod
kubectl -n nw-dns exec client -- nslookup kubernetes.default.svc.cluster.local      # the API: always exists
```

<details>
<summary>Line-by-line explanation</summary>

- `run client --image=busybox:1.36` — A busybox client that sleeps for an hour, so you can run lookups from inside the namespace.
- `nslookup inventory.nw-dns.svc.cluster.local` — The full name of a Service; the answer is its ClusterIP. The `Server:` line and the first `Address:` line are the DNS server itself, not the answer.
- `nslookup inventory-pods.nw-dns` — A headless Service has no ClusterIP, so you get one `Address:` line per ready Pod.
- `nslookup kubernetes.default` — The `kubernetes` Service in `default` exists on every cluster. If even this fails, DNS itself is broken, not your Service.

</details>

When a lookup fails, the error message tells you which part is broken. [Service and DNS failures](/cka/troubleshooting/service-and-dns-failures) walks through each case.

> [!TIP] **busybox nslookup has quirks**
> The `nslookup` in `busybox:1.36` uses the search list only for names without a dot. For each ending it tries, it prints *NXDOMAIN* ("no such name"). It also exits with an error, even when it found the answer. So `nslookup kubernetes.default` fails, while `wget http://kubernetes.default` works. Always look up the full name. Then read the `Name:` and `Address:` lines below the server lines.

> [!IMPORTANT] **What the grader reads**
> For lookup tasks, the grader reads only your answer file. Write the IP itself, one per line for a headless Service, without the `Server:` lines. For Pod DNS tasks, it reads `spec.dnsPolicy`, `spec.dnsConfig` and often the Pod's `/etc/resolv.conf`. For Corefile tasks, it runs a lookup from a Pod, so restart CoreDNS and test. A Corefile typo breaks DNS for the whole cluster, and can cost points on other questions.

## 📝 Key Takeaways

- A Service's full name is `..svc.cluster.local`. A headless Service answers with its Pods' IPs.
- The kubelet writes each Pod's `/etc/resolv.conf`. Its nameserver is the `kube-dns` Service, which is CoreDNS.
- `dnsPolicy: ClusterFirst` is the default. `dnsConfig` adds search domains and options on top.
- The Corefile is in ConfigMap `coredns` in `kube-system`. Back it up, edit it, restart CoreDNS, then test.
- A `hosts` block needs `fallthrough`, or every other name stops resolving.

**📖 Official documentation:**

- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) *(search: "dns for services and pods")*
- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) *(search: "debugging dns resolution")*
- [Customizing DNS Service](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/) *(search: "customizing dns service corefile")*

---

### 🎯 Task: Resolve a Service and a headless Service

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 4% |
| **Time** | 5 min |

**Question:**

In namespace `nw-dns`, start a temporary Pod with image `busybox:1.36`. From it, resolve the fully qualified DNS name of the Service `inventory` and write the address the lookup returns to `/tmp/cka/dns-inventory-ip.txt`. Then resolve the fully qualified name of the headless Service `inventory-pods` and write every address it returns, one per line, to `/tmp/cka/dns-inventory-pods.txt`. Delete the temporary Pod when you are done.

<details>
<summary>💡 Hints</summary>

- The full name (FQDN) is SERVICE.NAMESPACE.svc.cluster.local.
- A headless Service answers with the Pod IPs, not a ClusterIP. Expect as many addresses as there are ready Pods.

</details>

<details>
<summary>✅ Solution</summary>

```bash
ns=nw-dns
kubectl -n $ns run dnsutil --image=busybox:1.36 --restart=Never -- sleep 300
kubectl -n $ns wait --for=condition=Ready pod/dnsutil --timeout=90s
kubectl -n $ns exec dnsutil -- nslookup inventory.nw-dns.svc.cluster.local
kubectl -n $ns exec dnsutil -- nslookup inventory.nw-dns.svc.cluster.local | awk '/^Name:/{f=1} f && /^Address/{print $2}' | head -1 > /tmp/cka/dns-inventory-ip.txt
kubectl -n $ns exec dnsutil -- nslookup inventory-pods.nw-dns.svc.cluster.local | awk '/^Name:/{f=1} f && /^Address/{print $2}' | sort -u > /tmp/cka/dns-inventory-pods.txt
kubectl -n $ns delete pod dnsutil --now
cat /tmp/cka/dns-inventory-ip.txt /tmp/cka/dns-inventory-pods.txt
```

**Explanation:**

- `ns=nw-dns` — The namespace, reused as `$ns` below.
- `run dnsutil` — The temporary Pod: busybox sleeping for five minutes, long enough for several lookups.
- `exec dnsutil -- nslookup inventory.nw-dns.svc.cluster.local` — Run the lookup once by eye, so you see the shape of the output before you filter it.
- `| head -1` — `awk` raises a flag at the `Name:` line and prints the second word of each `Address` line after it, skipping the DNS server's own address above. `head -1` keeps the first, the ClusterIP.
- `nslookup inventory-pods` — The same filter on the headless Service: every Pod IP, sorted with duplicates removed (`sort -u`), one per line.
- `delete pod dnsutil --now` — Removes the temporary Pod, as asked.
- `cat /tmp/cka/dns-inventory-ip.txt` — Check: one ClusterIP in the first file, one Pod IP per line in the second.

**Notes:** On the exam, run `kubectl run tmp -n nw-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup inventory.nw-dns.svc.cluster.local`. Copy the address below `Name:` into the file with `echo`. Skip the `Address: 10.96.0.10:53` line above it: that is the DNS server, not the answer. Do the same for `inventory-pods`, which returns one address per ready Pod. Check both with `kubectl get svc,endpointslices -n nw-dns`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-dns
cip=$(kubectl -n $ns get svc inventory -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
want=$(kubectl -n $ns get pods -l app=inventory -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | grep . | sort)
got=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /tmp/cka/dns-inventory-pods.txt 2>/dev/null | sort -u)

[ -n "$cip" ] && [ "$(tr -d '[:space:]' < /tmp/cka/dns-inventory-ip.txt 2>/dev/null)" = "$cip" ] && p "dns-inventory-ip.txt = ClusterIP $cip" || f "dns-inventory-ip.txt holds the ClusterIP of inventory"
[ -n "$want" ] && [ "$got" = "$want" ] && p "dns-inventory-pods.txt lists every inventory pod IP" || f "dns-inventory-pods.txt lists every inventory pod IP"
[ "$(grep -c . /tmp/cka/dns-inventory-pods.txt 2>/dev/null)" = "$(echo "$want" | grep -c .)" ] && p "one address per line, nothing else" || f "one address per line, nothing else"
[ -z "$(kubectl -n $ns get pods --no-headers 2>/dev/null | grep -v '^inventory-')" ] && p "temporary pod removed" || f "temporary pod removed"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Give a Pod an extra search domain

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Create a Pod named `resolver` in namespace `nw-dnscfg` using image `busybox:1.36` that runs `sleep 3600`. It must keep using cluster DNS. Add `corp.internal` as an additional search domain and set the resolver option `ndots` to `2`. The Pod must be Running.

<details>
<summary>💡 Hints</summary>

- Keep dnsPolicy ClusterFirst. The extra settings go under spec.dnsConfig.
- Option values are strings: value: "2".

</details>

<details>
<summary>✅ Solution</summary>

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: resolver
  namespace: nw-dnscfg
spec:
  terminationGracePeriodSeconds: 1
  dnsPolicy: ClusterFirst
  dnsConfig:
    searches:
      - corp.internal
    options:
      - name: ndots
        value: "2"
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
kubectl -n nw-dnscfg wait --for=condition=Ready pod/resolver --timeout=90s
kubectl -n nw-dnscfg exec resolver -- cat /etc/resolv.conf
```

**Explanation:**

- `cat <<'YAML' | kubectl apply -f -` — A heredoc piped into `kubectl apply -f -`: the lines up to `YAML` go straight to kubectl, with no file. The quotes in `'YAML'` stop the shell from changing anything inside.
- `terminationGracePeriodSeconds: 1` — Lets the Pod stop within 1 second when deleted. Running as the container's main process, `sleep` ignores the polite stop signal, so the default would wait the full 30 seconds.
- `dnsPolicy: ClusterFirst` — Keeps cluster DNS, as the task requires. It is the default, but writing it shows the intent.
- `- corp.internal` — The extra search domain, appended after the cluster's own.
- `value: "2"` — `ndots` set to 2, written as a string.
- `kubectl -n nw-dnscfg wait` — Waits for the Pod to be Ready: the task wants it Running.
- `cat /etc/resolv.conf` — The proof: the search line ends with `corp.internal`, the options read `ndots:2`, and the nameserver is still the cluster DNS.

**Notes:** Make the skeleton with `kubectl run resolver -n nw-dnscfg --image=busybox:1.36 --dry-run=client -o yaml --command -- sleep 3600 > resolver.yaml`. Then add the `dnsConfig` block under `spec` in vim. The Pod's `/etc/resolv.conf` then keeps the cluster nameserver and search list, adds `corp.internal`, and reads `options ndots:2`. Do not use `dnsPolicy: None` here: the Pod would lose the cluster nameserver unless you listed it yourself.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-dnscfg
g="kubectl -n $ns get pod resolver -o jsonpath"
dnsip=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

kubectl -n $ns get pod resolver >/dev/null 2>&1 && p "pod resolver exists" || f "pod resolver exists"
[ "$($g='{.spec.containers[0].image}' 2>/dev/null)" = "busybox:1.36" ] && p "image busybox:1.36" || f "image busybox:1.36"
[ "$($g='{.status.phase}' 2>/dev/null)" = "Running" ] && p "pod is Running" || f "pod is Running"
pol="$($g='{.spec.dnsPolicy}' 2>/dev/null)"
[ "$pol" = "ClusterFirst" ] && p "dnsPolicy ClusterFirst" || f "dnsPolicy ClusterFirst (got '$pol')"
$g='{.spec.dnsConfig.searches}' 2>/dev/null | grep -q '"corp.internal"' && p "dnsConfig.searches has corp.internal" || f "dnsConfig.searches has corp.internal"
[ "$($g='{.spec.dnsConfig.options[?(@.name=="ndots")].value}' 2>/dev/null)" = "2" ] && p "dnsConfig option ndots=2" || f "dnsConfig option ndots=2"
rc=$(kubectl -n $ns exec resolver -- cat /etc/resolv.conf 2>/dev/null)
echo "$rc" | grep '^search' | grep -q 'corp.internal' && echo "$rc" | grep '^search' | grep -q "$ns.svc.cluster.local" && p "resolv.conf search keeps cluster domains and adds corp.internal" || f "resolv.conf search keeps cluster domains and adds corp.internal"
echo "$rc" | grep -q 'ndots:2' && p "resolv.conf has ndots:2" || f "resolv.conf has ndots:2"
[ -n "$dnsip" ] && echo "$rc" | grep -q "^nameserver $dnsip" && p "nameserver is cluster DNS $dnsip" || f "nameserver is cluster DNS"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Serve a static record from CoreDNS

| Detail | Value |
| --- | --- |
| **Domain** | networking |
| **Weight** | 6% |
| **Time** | 7 min |

**Question:**

A legacy database has no DNS record. Configure the cluster DNS so that every Pod resolves `legacy-db.corp.internal` to `10.10.10.10`. All existing names, including Services and names outside the cluster, must keep resolving. Confirm from Pod `client` in namespace `nw-dnshosts`.

<details>
<summary>💡 Hints</summary>

- The CoreDNS settings are the Corefile key of ConfigMap coredns in kube-system.
- The hosts plugin serves fixed entries. Without fallthrough, it answers NXDOMAIN for every name it does not list.
- Restart the coredns Deployment instead of waiting for the reload plugin.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/cka/Corefile
cp /tmp/cka/Corefile /tmp/cka/Corefile.bak
awk '/^ *kubernetes / && !done {print "    hosts {\n       10.10.10.10 legacy-db.corp.internal\n       fallthrough\n    }"; done=1} {print}' /tmp/cka/Corefile > /tmp/cka/Corefile.new
cat /tmp/cka/Corefile.new
kubectl -n kube-system create cm coredns --from-file=Corefile=/tmp/cka/Corefile.new --dry-run=client -o yaml \
  | kubectl apply --server-side --force-conflicts --field-manager=cka-lab -f -
kubectl -n kube-system rollout restart deploy coredns
kubectl -n kube-system rollout status deploy coredns --timeout=180s
sleep 3
kubectl -n nw-dnshosts exec client -- nslookup legacy-db.corp.internal
```

**Explanation:**

- `> /tmp/cka/Corefile` — Saves the live Corefile to a file, so you can change it with tools instead of an editor.
- `cp /tmp/cka/Corefile` — A backup copy, in case you need to roll back.
- `awk '/^ *kubernetes /` — Prints a `hosts` block just before the first `kubernetes` line, then every original line (`{print}`). `done` makes sure the block goes in only once; each `\n` is a line break in the printed text.
- `cat /tmp/cka/Corefile.new` — Read the result before applying it: a typo here breaks DNS for the whole cluster.
- `create cm coredns --from-file=Corefile=/tmp/cka/Corefile.new` — Builds a ConfigMap named `coredns` whose `Corefile` key holds the new file, printed as YAML and not sent. The trailing `\` carries the pipe onto the next line.
- `kubectl apply --server-side` — Applies it over the live ConfigMap. `--force-conflicts` lets server-side apply take over the field even if another manager owns it, and `--field-manager` records who changed it. `kubectl replace -f -` would work too.
- `rollout restart deploy coredns` — Restarts CoreDNS so the new Corefile is live now.
- `rollout status deploy coredns` — Waits until the new Pods are Ready. A crash loop here means a Corefile mistake.
- `nslookup legacy-db.corp.internal` — Should show `10.10.10.10` under `Name: legacy-db.corp.internal`. Also look up a Service name, to prove `fallthrough` kept the rest of DNS working.

**Notes:** On the exam, run `kubectl -n kube-system edit cm coredns`. Inside the `.:53` block, add a `hosts` block with `10.10.10.10 legacy-db.corp.internal` and `fallthrough`, one per line. Its position does not matter: CoreDNS runs plugins in a fixed order. Then restart the `coredns` Deployment, and test the new name plus a cluster name. Forget `fallthrough`, and every other name breaks. If the Pods crash, `kubectl -n kube-system logs -l k8s-app=kube-dns` names the bad line.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=nw-dnshosts
look() { kubectl -n $ns exec client -- nslookup "$1" 2>/dev/null | awk '/^Name:/{f=1} f && /^Address/{print $2}' | head -1; }

[ "$(kubectl -n kube-system get deploy coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "$(kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}' 2>/dev/null)" ] && p "coredns replicas all ready" || f "coredns replicas all ready"
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -q 'legacy-db.corp.internal' && p "Corefile has the legacy-db entry" || f "Corefile has the legacy-db entry"
ok=""; for i in 1 2 3 4 5 6; do [ "$(look legacy-db.corp.internal)" = "10.10.10.10" ] && { ok=1; break; }; sleep 5; done
[ -n "$ok" ] && p "legacy-db.corp.internal -> 10.10.10.10" || f "legacy-db.corp.internal -> 10.10.10.10"
[ "$(look kubernetes.default.svc.cluster.local)" = "$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}')" ] && p "cluster names still resolve" || f "cluster names still resolve"
[ "$(look kube-dns.kube-system.svc.cluster.local)" = "$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')" ] && p "kube-dns service resolves" || f "kube-dns service resolves"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 3: Services & networking*
