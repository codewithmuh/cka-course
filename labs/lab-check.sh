#!/usr/bin/env bash
# CKA lab health check — https://codewithmuh.com/cka
# Prints PASS/FAIL for each lab component. Exit 0 only when everything passes.
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails + 1)); }

kubectl config get-contexts kind-cka >/dev/null 2>&1 && p "context kind-cka exists" || f "context kind-cka exists"
[ "$(kubectl --context kind-cka get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "3" ] && p "3 nodes" || f "3 nodes"
nodes="$(kubectl --context kind-cka get nodes --no-headers 2>/dev/null)"
[ -n "$nodes" ] && [ -z "$(printf '%s\n' "$nodes" | grep -v -E ' Ready(,SchedulingDisabled)? ')" ] && p "all nodes Ready" || f "all nodes Ready"
[ -n "$nodes" ] && [ -z "$(printf '%s\n' "$nodes" | grep SchedulingDisabled)" ] && p "no node cordoned" || f "no node cordoned (a task left one cordoned: kubectl uncordon <node>)"
kubectl --context kind-cka -n kube-system get ds calico-node >/dev/null 2>&1 && p "Calico installed" || f "Calico installed"
kubectl --context kind-cka top nodes >/dev/null 2>&1 && p "metrics-server serving (kubectl top)" || f "metrics-server serving (kubectl top)"
kubectl --context kind-cka -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1 && p "ingress-nginx installed" || f "ingress-nginx installed"
code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:8080/ 2>/dev/null)"
[ "$code" = "404" ] || [ "$code" = "200" ] && p "ingress reachable on localhost:8080" || f "ingress reachable on localhost:8080 (got '${code:-no answer}'; re-run lab-up.sh)"
kubectl --context kind-cka get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 && p "Gateway API CRDs installed" || f "Gateway API CRDs installed"
pool="$(kubectl --context kind-cka get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.cidr}' 2>/dev/null)"
[ "$pool" = "10.244.0.0/16" ] && p "pod network 10.244.0.0/16" || f "pod network 10.244.0.0/16 (got '${pool:-none}'; an old lab, run lab-reset.sh)"
ipip="$(kubectl --context kind-cka get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.ipipMode}' 2>/dev/null)"
[ "$ipip" = "Never" ] && p "pod routing without a tunnel" || f "pod routing without a tunnel (ipipMode '${ipip:-none}'; re-run lab-up.sh)"
docker exec cka-control-plane true >/dev/null 2>&1 && p "node shell works (docker exec cka-control-plane)" || f "node shell works (docker exec cka-control-plane)"
mkdir -p /tmp/cka 2>/dev/null && p "/tmp/cka answers dir" || f "/tmp/cka answers dir"

if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fails)"; exit 1; fi
