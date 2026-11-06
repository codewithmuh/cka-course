# CKA Glossary

Key terms for the Certified Kubernetes Administrator exam.

### undefined

The command-line tool you use to talk to a cluster. You type a command, kubectl sends it to the API server, and shows you the answer.

### undefined

A machine in the cluster: a virtual machine or a physical server. Worker nodes run your apps; control plane nodes run the parts that manage the cluster.

### undefined

The brain of the cluster: the parts that store what you asked for and decide what should happen. Your apps run on worker nodes; the control plane manages them.

### undefined

The front door of the cluster. Every request goes through it: yours (through kubectl) and those of every other part of Kubernetes.

### undefined

The cluster's database. It stores every object you create: every Pod, Deployment, Service and Secret.

### undefined

Decides which node each new Pod runs on. It looks at free CPU and memory, and at any rules the Pod has, such as "only nodes with an SSD".

### undefined

Watches what you asked for and keeps fixing the difference. You ask for 3 replicas; if a Pod dies, it creates a new one.

### undefined

The agent that runs on every node. It starts the Pods the cluster assigns to its node, restarts them when they crash, and reports back to the API server.

### undefined

Runs on every node and makes Service addresses work: traffic sent to a Service is passed on to one of its Pods.

### undefined

The program that actually runs containers on a node, usually containerd. The kubelet tells it what to start.

### undefined

The container runtime on kind and most kubeadm clusters. It pulls images and starts containers when the kubelet asks.

### undefined

Container Network Interface: the standard for network plugins, which give every Pod its own IP address and connect Pods across nodes. This lab's plugin is Calico.

### undefined

Container Storage Interface: the plugin standard storage systems use to create and attach volumes.

### undefined

Container Runtime Interface: how the kubelet talks to the container runtime. `crictl` speaks it too.

### undefined

The CNI plugin in this lab. It wires up Pod networking and enforces NetworkPolicies.

### undefined

A Pod created from a YAML file on the node instead of through the API. The kubelet reads the file and runs the Pod itself: no scheduler and no API server needed.

### undefined

The majority of etcd members (2 of 3, 3 of 5) that must agree before the cluster accepts a write.

### undefined

The smallest thing Kubernetes runs. A Pod wraps one or more containers that always run together on the same node and share one IP address.

### undefined

A packaged program: your app plus everything it needs to run, started from an image such as `nginx:1.27`.

### undefined

A named area inside a cluster that keeps groups of objects apart, a bit like folders. Two teams can each have a Pod called `web` if they are in different namespaces.

### undefined

Runs your app as a set of identical Pods and keeps that many running. When you change the image or settings, it replaces the Pods a few at a time, so the app stays up.

### undefined

Keeps a fixed number of identical Pods running, and replaces any that disappear. You rarely create one yourself: a Deployment does it for you.

### undefined

Replacing a Deployment's Pods with new ones after you change it, for example with a new image. By default it happens a few Pods at a time, so the app stays up.

### undefined

Runs one copy of a Pod on every node, or on every node that matches a rule. When a new node joins, it gets its copy automatically.

### undefined

Like a Deployment, but for apps such as databases, where each Pod needs a fixed name and its own disk. Its Pods are numbered `db-0`, `db-1` and so on, and keep their name and storage when they are replaced.

### undefined

Runs a Pod until a task finishes successfully, then stops. If the Pod fails, the Job starts a new one, up to a retry limit.

### undefined

Creates a Job on a schedule, written in cron format. For example, `0 2 * * *` means every day at 2 a.m.

### undefined

A container that runs to completion before the app containers start, for example to wait for a database or prepare files.

### undefined

A helper container running next to the app in the same Pod, such as a log shipper.

### undefined

A regular health check the kubelet runs on a container. **Liveness** restarts a stuck container, **readiness** holds back traffic until it is ready, and **startup** gives a slow app time to start.

### undefined

A class Kubernetes gives each Pod from its CPU and memory requests and limits: **Guaranteed**, **Burstable** or **BestEffort**. When a node runs short of memory, the class decides which Pods are evicted first.

### undefined

Rules for the containers in one namespace: default CPU and memory requests and limits for containers that set none, and the smallest and largest values allowed.

### undefined

A cap on the total resources one namespace may use, such as 10 Pods, 4 CPUs of requests or 8 GiB of memory. Anything that would go over the cap is refused when it is created.

### undefined

Watches a number such as average CPU use, and adds or removes Pod replicas to keep it near a target. *Horizontal* means more or fewer Pods, not bigger ones.

### undefined

A small add-on that collects current CPU and memory use from the kubelet on every node. `kubectl top` and the HorizontalPodAutoscaler get their numbers from it.

### undefined

A rule that limits how many Pods of an app may be taken down on purpose at the same time, for example while a node is drained. It keeps enough copies running to serve users.

### undefined

A check inside the API server that can reject or change a request before it is stored.

### undefined

Built-in check that enforces the privileged, baseline or restricted Pod Security Standards, set per namespace with labels.

### undefined

Gives Pods a priority. When a node is full, the scheduler may evict lower-priority Pods to make room, which is called preemption.

### undefined

A short `key=value` tag you put on an object, such as `app=web` or `env=prod`. Kubernetes uses labels to find and group objects.

### undefined

A rule that picks objects by their labels, such as `app=web`. A Service uses one to find its Pods, and a Deployment uses one to know which Pods are its own.

### undefined

A mark on a node that keeps Pods away. Only Pods with a matching toleration may be scheduled there.

### undefined

A setting on a Pod that lets it run on a node with a matching taint. It allows the Pod onto that node; it does not send it there.

### undefined

Rules on a Pod that choose where it runs. **Node affinity** pulls it toward nodes with certain labels; **pod affinity** and **anti-affinity** place it near, or away from, other Pods.

### undefined

Marks a node so no new Pods are scheduled on it. Pods already running there keep running.

### undefined

Empties a node before maintenance. It cordons the node so nothing new arrives, then evicts its Pods so their controllers recreate them on other nodes.

### undefined

A fixed name and IP address in front of a group of Pods. Pods come and go and change IPs, but the Service stays the same and passes each request to one of them.

### undefined

The default kind of Service: a fixed virtual IP address that only works inside the cluster. Other Pods use it, usually through its DNS name, to reach your app.

### undefined

A kind of Service that opens the same port, between 30000 and 32767, on every node. Traffic to any node's IP on that port reaches your Pods, even from outside the cluster.

### undefined

A Service type that asks the cloud provider for an external load balancer pointing at the Service.

### undefined

The current list of Pod IPs and ports behind a Service. Kubernetes keeps it up to date as Pods start, stop and become ready.

### undefined

The cluster's DNS server. It turns names like `web` or `web.prod.svc.cluster.local` into a Service's IP address, so Pods can call each other by name.

### undefined

Rules that send web traffic from outside the cluster to Services, by host name and path, such as `shop.example.com/api` to the `api` Service. The rules only work when an Ingress controller is running.

### undefined

The Ingress controller in this lab: an nginx that reads Ingress objects and routes traffic the way they say.

### undefined

The successor to Ingress for routing outside traffic into the cluster. It splits the job into objects: a **GatewayClass** picks the controller, a **Gateway** opens the entry point, and an **HTTPRoute** sends requests to Services.

### undefined

Firewall rules for Pods: which Pods may talk to which, and on which ports. Once a policy selects a Pod, that Pod only accepts the traffic a policy allows.

### undefined

A piece of storage, such as a cloud disk or a folder on a node, that the cluster can give to Pods. It keeps its data when the Pods using it are deleted.

### undefined

Your app's request for storage: how much, and how it will be used, such as 1 GiB that one node can write to. Kubernetes finds or creates a matching PersistentVolume and binds the two together.

### undefined

A recipe for making storage on demand. When a PersistentVolumeClaim names a StorageClass, the class's provisioner creates a new PersistentVolume for it, so nobody has to make one by hand.

### undefined

Stores plain settings, such as a log level or a config file, outside your container image. Pods read them as environment variables or as files.

### undefined

Like a ConfigMap, but for sensitive values such as passwords, API keys and TLS certificates. The values are base64-encoded, which hides them from a quick look but is not encryption.

### undefined

Role-based access control: how Kubernetes decides who may do what. A **Role** lists allowed actions, such as "list Pods", and a **RoleBinding** gives that Role to a user, a group or a service account.

### undefined

An identity for a program running in a Pod, so it can call the API server with its own permissions. People log in as users; Pods run as service accounts.

### undefined

The file kubectl reads to know which clusters exist, how to log in to each one, and which one to use now. It is usually `~/.kube/config`.

### undefined

An API object that asks the cluster's certificate authority to sign a certificate, for example for a new user.

### undefined

A setup tool that builds a Kubernetes cluster. You run it once on each machine: `kubeadm init` on the first one, `kubeadm join` on the others.

### undefined

A package manager for Kubernetes. A **chart** is a package of manifests; installing it creates a **release** you can upgrade, roll back or remove with one command.

### undefined

A Helm package: templated manifests plus default values you can override.

### undefined

A tool built into kubectl that changes plain YAML files without templates. You keep one base set of manifests and add small changes per environment, such as more replicas in prod.

### undefined

Adds a new kind of object to the Kubernetes API. Once a CRD is installed, you can create and list objects of that kind with kubectl, just like Pods.

### undefined

A controller you install that manages an app through custom resources, automating what a human operator would do.

### undefined

A command-line tool for the container runtime on a node. It lists and inspects containers and images directly, so it still works when the API server, and so kubectl, does not.

### undefined

Reads service logs on a Linux node, e.g. `journalctl -u kubelet` to see why the kubelet fails.

### undefined

Controls services on a Linux node, e.g. `systemctl restart kubelet`.

### undefined

A temporary debug container added to a running Pod with `kubectl debug`, handy when the app image has no shell.

### undefined

A small query language for picking fields out of kubectl output, e.g. `-o jsonpath='{.spec.replicas}'`.

### undefined

A file, usually YAML, that describes an object you want in the cluster: what kind it is, its name and its settings. You send it to the cluster with `kubectl apply -f`.

### undefined

The text format manifests are written in. It uses indentation to show what belongs to what, and a `-` at the start of each list item.

### undefined

Telling Kubernetes what to do with a command (`kubectl create`, `scale`), instead of describing the end state in a file.

### undefined

Describing the state you want in a file and letting Kubernetes make it so with `kubectl apply`.

### undefined

A shell trick for typing a multi-line file in one command: `cat > file <<'EOF'`, the lines, then `EOF`.

