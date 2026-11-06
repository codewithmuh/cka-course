# CKA Exam-Day Cheat Sheet

> Print or have this ready before you sit down. Every command here is allowed
> on the exam (they come from kubernetes.io/docs).

## 1. Environment Setup (First 60 Seconds)

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"

# Tab completion
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# vim settings for YAML
cat >> ~/.vimrc << 'EOF'
set tabstop=2
set shiftwidth=2
set expandtab
set autoindent
set number
set paste
EOF
```

## 2. Imperative Shortcuts

```bash
# Pod
k run nginx --image=nginx $do > pod.yaml

# Deployment
k create deploy web --image=nginx --replicas=3 $do > deploy.yaml

# Service (ClusterIP)
k expose deploy web --port=80 --target-port=80

# Service (NodePort)
k expose deploy web --port=80 --type=NodePort

# ConfigMap
k create cm my-config --from-literal=key=value

# Secret
k create secret generic my-secret --from-literal=pass=s3cret

# ServiceAccount
k create sa my-sa

# Role + RoleBinding
k create role pod-reader --verb=get,list,watch --resource=pods
k create rolebinding pod-reader-binding --role=pod-reader --serviceaccount=default:my-sa

# ClusterRole + ClusterRoleBinding
k create clusterrole node-reader --verb=get,list --resource=nodes
k create clusterrolebinding node-reader-binding --clusterrole=node-reader --serviceaccount=default:my-sa

# Job
k create job my-job --image=busybox -- echo "hello"

# CronJob
k create cronjob my-cron --image=busybox --schedule="*/5 * * * *" -- echo "hello"

# Ingress
k create ingress my-ing --rule="host/path=svc:80"

# NetworkPolicy (start from docs template, then edit)
```

## 3. Troubleshooting Flow

```bash
# 1. What's running?
k get pods -A -o wide
k get nodes -o wide
k get events -A --sort-by='.lastTimestamp' | tail -20

# 2. Describe the broken resource
k describe pod <pod> -n <ns>     # → Events section

# 3. Check logs
k logs <pod> -n <ns>
k logs <pod> -n <ns> --previous  # previous crashed container
k logs <pod> -n <ns> -c <container>  # specific container

# 4. Node-level
ssh <node>   # (exam) / docker exec -it <node> bash (kind lab)
systemctl status kubelet
journalctl -u kubelet --no-pager -n 50
crictl ps -a
crictl logs <container-id>

# 5. Control plane (static pods)
ls /etc/kubernetes/manifests/
cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

## 4. etcd Operations

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-from-backup

# Then update /etc/kubernetes/manifests/etcd.yaml:
#   hostPath.path → /var/lib/etcd-from-backup
```

## 5. Cluster Upgrades (kubeadm)

```bash
# Control plane node
apt update && apt-cache madison kubeadm
apt-get install -y kubeadm=1.XX.Y-*
kubeadm upgrade plan
kubeadm upgrade apply v1.XX.Y
apt-get install -y kubelet=1.XX.Y-* kubectl=1.XX.Y-*
systemctl daemon-reload && systemctl restart kubelet

# Worker node
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# (SSH to worker)
apt-get install -y kubeadm=1.XX.Y-*
kubeadm upgrade node
apt-get install -y kubelet=1.XX.Y-* kubectl=1.XX.Y-*
systemctl daemon-reload && systemctl restart kubelet
# (back on control plane)
kubectl uncordon <node>
```

## 6. Useful JSONPath & Sorting

```bash
# All pod images
k get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# Nodes sorted by CPU
k top nodes --sort-by=cpu

# Pods sorted by memory
k top pods -A --sort-by=memory

# Get specific field
k get node <node> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'

# Count ready nodes
k get nodes --no-headers | grep -c " Ready"
```

## 7. Common YAML Snippets

### Resource Requests & Limits
```yaml
resources:
  requests:
    cpu: "250m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "128Mi"
```

### Liveness & Readiness Probes
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### NodeAffinity
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: disktype
              operator: In
              values: ["ssd"]
```

### Toleration
```yaml
tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
```

### PersistentVolumeClaim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard
```

### NetworkPolicy (deny all, then allow specific)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: production
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
        - port: 80
```

---

> **Tip**: On exam day, bookmark these kubernetes.io pages:
> - [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
> - [kubeadm upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
> - [etcd backup](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)
> - [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
> - [PV/PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
