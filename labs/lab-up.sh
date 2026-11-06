#!/usr/bin/env bash
# CKA lab — https://codewithmuh.com/cka
#
# Creates a three-node kind cluster named "cka" and installs what the course
# tasks need: Calico (so NetworkPolicies enforce), metrics-server (kubectl top),
# ingress-nginx and the Gateway API CRDs. Safe to re-run; every step is idempotent.
#
#   curl -fsSL https://codewithmuh.com/labs/cka/lab-up.sh | bash
#
set -euo pipefail

CALICO_VERSION="${CALICO_VERSION:-v3.33.0}"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-v0.9.0}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-controller-v1.15.1}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.3}"
BASE="${CKA_LAB_BASE:-https://codewithmuh.com/labs/cka}"
CLUSTER="cka"

say() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
# wait_ok <what> <max seconds> <command...>: retry until the command succeeds.
# First runs download images, which can take a while on a slow connection.
wait_ok() {
  local what="$1" limit="$2" start; shift 2
  start=$(date +%s)
  until "$@" >/dev/null 2>&1; do
    if [ $(( $(date +%s) - start )) -ge "$limit" ]; then
      echo "Timed out waiting for $what. Images may still be downloading."
      echo "Re-run this script; it is safe to repeat and continues where it stopped."
      exit 1
    fi
    echo "  waiting for $what ($(( $(date +%s) - start ))s)"
    sleep 15
  done
}
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'. Install guide: https://codewithmuh.com/cka/foundations/build-your-lab"; exit 1; }; }

need docker; need kind; need kubectl
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker Desktop (or the docker service) and re-run."; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  say "kind cluster '$CLUSTER' already exists, reusing it"
else
  say "Creating kind cluster '$CLUSTER' (1 control plane, 2 workers)"
  cfg="$(mktemp)"
  if [ -f "./kind-config.yaml" ]; then cp ./kind-config.yaml "$cfg"; else curl -fsSL "$BASE/kind-config.yaml" -o "$cfg"; fi
  kind create cluster --config "$cfg"
  rm -f "$cfg"
fi

kubectl config use-context "kind-$CLUSTER" >/dev/null

say "Calico $CALICO_VERSION (pod network + NetworkPolicy enforcement)"
# Two changes to Calico's defaults for a kind lab:
#  - the pool matches kind's podSubnet (10.244.0.0/16) instead of 192.168.0.0/16;
#  - plain routing instead of IP-in-IP. All kind nodes share one Docker network,
#    so no tunnel is needed, and on Docker Desktop the tunnel drops NodePort
#    traffic from your laptop to pods on worker nodes.
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml" \
  | sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
        -e 's|#   value: "192.168.0.0/16"|  value: "10.244.0.0/16"|' \
        -e '/name: CALICO_IPV4POOL_IPIP/{n;s|"Always"|"Never"|;}' \
  | kubectl apply -f - >/dev/null
# Labs built before this change: switch the existing pool to plain routing too.
kubectl patch ippools.crd.projectcalico.org default-ipv4-ippool --type merge -p '{"spec":{"ipipMode":"Never"}}' >/dev/null 2>&1 || true
wait_ok "Calico on every node" 900 kubectl -n kube-system rollout status ds/calico-node --timeout=60s
wait_ok "nodes to be Ready" 600 kubectl wait --for=condition=Ready nodes --all --timeout=60s
# Let any pods scheduled before the CNI was up recover.
wait_ok "CoreDNS" 600 kubectl -n kube-system rollout status deploy/coredns --timeout=60s

say "metrics-server $METRICS_SERVER_VERSION (kubectl top)"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml" >/dev/null
if ! kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q kubelet-insecure-tls; then
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
fi
# What matters is that the metrics API answers; the old replica can take a while to go away.
for _ in $(seq 1 48); do kubectl top nodes >/dev/null 2>&1 && break; sleep 5; done
kubectl top nodes >/dev/null 2>&1 && echo "kubectl top is serving" || echo "note: metrics-server is not serving yet; kubectl top usually works within another minute"

say "ingress-nginx $INGRESS_NGINX_VERSION (Ingress tasks; http://localhost:8080)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/kind/deploy.yaml" >/dev/null
# kind maps host port 8080 to port 80 on the control-plane node only, so the
# controller (which binds hostPort 80) must run there. Recent manifests no
# longer pin it, so pin it here.
kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","ingress-ready":"true"}}}}}' >/dev/null
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s >/dev/null || true
kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=300s >/dev/null \
  || echo "note: the ingress controller is still starting; re-run lab-check.sh in a minute"

say "Gateway API $GATEWAY_API_VERSION standard CRDs"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml" >/dev/null

mkdir -p /tmp/cka

say "Lab is ready"
kubectl get nodes -o wide
cat <<MSG

  context      kind-$CLUSTER
  node shell   docker exec -it $CLUSTER-control-plane bash   (the exam uses: ssh <node>)
  answers dir  /tmp/cka
  check        curl -fsSL $BASE/lab-check.sh | bash
  reset        curl -fsSL $BASE/lab-reset.sh | bash

  Next lesson: https://codewithmuh.com/cka/foundations/kubectl-fluency
MSG
