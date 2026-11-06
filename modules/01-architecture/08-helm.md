# Helm: install, upgrade, roll back

> **Module 1** · Lesson 1.8 · 40 minutes

Install an app from a Helm chart at a fixed version, then upgrade it, roll it back and remove it.

## Learning Objectives

- You can add a chart repository, list a chart's versions and read its default values.
- You can install a fixed chart version into a namespace with your own values, then upgrade it and roll it back.
- You can find a release in any namespace, read its history and its values, and uninstall it.


**Helm** installs apps on Kubernetes the way `apt` or `brew` installs programs on a computer. One command creates every object an app needs: its Deployments, Services, ConfigMaps and more. Many cluster add-ons ship this way, such as ingress controllers and monitoring tools.

On the exam, a Helm task names everything you need: the repository, chart, chart version, release name, namespace and values. The grader checks every one. The helm.sh docs are allowed in the exam, but `helm  --help` is faster: it lists every flag with an example.

## Four words: chart, repository, release, revision

| Word | What it is | Example |
| --- | --- | --- |
| **Chart** | A package: templates for an app's objects, plus default settings called *values* | `podinfo/podinfo` |
| **Repository** | A website that hosts charts. You add it once, under a short name. | `https://stefanprodan.github.io/podinfo`, added as `podinfo` |
| **Release** | One installed copy of a chart. It has a name and lives in one namespace. | `web` in `arx-demo` |
| **Revision** | A numbered version of a release. Every install, upgrade and rollback adds one. | 1 (install), 2 (upgrade), 3 (rollback) |

**From a chart to a release**

*Helm fills the chart's templates with your values and applies the result. Each change to the release is saved as a new numbered revision.*

`Chart + your values`
  - `Chart` — the package (`podinfo/podinfo`)
  - `Values` — your settings (`replicaCount=2`) → `helm install` — fills the templates and applies them → `Release web` — the installed copy
  - `Revision 1` — install
  - `Revision 2` — upgrade
  - `Revision 3` — rollback

- A chart has two version numbers. The **chart version** is the package's own version, and `--version` picks it. The **app version** is the version of the software inside. On the exam, "version" means the chart version.
- Helm is a program on your computer. Nothing of Helm runs in the cluster: it uses your kubeconfig, just like kubectl. [Build your lab](/cka/foundations/build-your-lab) installs it.
- Helm keeps each release's history in the release's namespace. That is why most Helm commands need the same `-n` you installed with.

## Read a chart before you install it

Before you install, add the repository and check which chart versions exist. Then look up the exact names of the values you need to set.

**Repositories, versions and values**

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update                                   # refresh every index (or: helm repo update podinfo)
helm repo list
helm search repo podinfo                           # newest chart version only
helm search repo podinfo/podinfo --versions | head # every chart version with its app version
helm show chart podinfo/podinfo --version 6.14.0
helm show values podinfo/podinfo --version 6.14.0 > /tmp/cka/podinfo-values.yaml   # every key and its default

# Render locally: no release is created and nothing reaches the cluster
helm template web podinfo/podinfo --version 6.14.0 -n arx-demo --set replicaCount=3 > /tmp/cka/web.yaml
grep -nE 'replicas:|image:' /tmp/cka/web.yaml
```

<details>
<summary>Line-by-line explanation</summary>

- `helm repo add podinfo` — Saves the repository URL on your machine under the short name `podinfo`. Its charts are then called `podinfo/`.
- `helm repo update` — Downloads each repository's latest index, the list of charts and versions it offers. Without it, Helm only knows what the repo had when you added it.
- `helm repo list` — Shows the repositories you have added and their URLs.
- `helm search repo podinfo` — Searches your added repositories for charts matching `podinfo`. CHART VERSION and APP VERSION appear side by side; a task's version means the chart version.
- `--versions | head` — `--versions` lists every published version, newest first, and `| head` keeps the first 10 lines.
- `helm show chart` — Prints the chart's `Chart.yaml`: its name, version, appVersion and description.
- `helm show values` — Prints the chart's default `values.yaml`, every setting you can override, and saves it to a file. This is how you find a value's exact key name.
- `helm template web podinfo/podinfo` — Renders the chart as release `web` in `arx-demo` with 3 replicas and saves the YAML. A safe way to see what a `--set` changes before installing anything.
- `grep -nE 'replicas:|image:'` — Shows just the replica and image lines, with line numbers, to confirm the override took effect.

</details>

## Install and inspect a release

**Install, then look at what Helm did**

```bash
helm install web podinfo/podinfo --version 6.14.0 \
  -n arx-demo --create-namespace \
  --set replicaCount=2 --set ui.message="hello" \
  --wait --timeout 5m

helm list -n arx-demo                     # NAME, REVISION, STATUS, CHART (<name>-<chart version>), APP VERSION
helm list -A                              # every namespace; plain "helm list" shows the current namespace only
helm status web -n arx-demo
helm get values web -n arx-demo           # only the values you supplied
helm get values web -n arx-demo --all     # merged with the chart defaults
helm get manifest web -n arx-demo | grep -n 'kind:'
```

<details>
<summary>Line-by-line explanation</summary>

- `helm install web podinfo/podinfo --version 6.14.0` — Installs chart `podinfo/podinfo` at chart version 6.14.0 as a release named `web`. The order is always release name first, then chart.
- `--create-namespace` — Puts the release and its objects in `arx-demo`, creating the namespace if it does not exist yet.
- `--set replicaCount=2` — Overrides two values from the chart's `values.yaml`. The dot in `ui.message` means the key `message` inside `ui`.
- `--wait --timeout 5m` — Waits until the release's Pods are ready before reporting success, and gives up after 5 minutes.
- `helm list -n arx-demo` — Lists the releases in `arx-demo`. Like kubectl, Helm looks in one namespace only unless you say otherwise.
- `helm list -A` — `-A` means all namespaces: the quickest way to find a release when you do not know where it lives.
- `helm status web` — Shows the release's status (`deployed`, `failed` and so on), its current revision and when it was last deployed.
- `helm get values web -n arx-demo` — Prints only the overrides you passed with `--set` or `-f`. This is the answer when a task asks which values a release was installed with.
- `--all` — Adds every chart default to your overrides: the full set of values the templates were rendered with.
- `helm get manifest` — Prints the YAML Helm rendered and applied for the current revision; the grep lists which kinds of objects the chart created.

</details>

## Upgrade, roll back, uninstall

An upgrade changes a release in place and adds a revision. Two habits save points. Repeat `--version`, or Helm moves to the newest chart. Add `--reuse-values` to keep the values you set before; without it, an upgrade with new `--set` values forgets the old ones.

**Upgrade, go back, remove**

```bash
# Upgrade. Repeat --version, or Helm moves you to the newest chart in the repo.
helm upgrade web podinfo/podinfo --version 6.14.0 -n arx-demo \
  --reuse-values --set replicaCount=3 --wait --timeout 5m
# Install if it is missing, upgrade it if it exists, with values from a file
helm upgrade --install web podinfo/podinfo --version 6.14.0 -n arx-demo -f /tmp/cka/web-values.yaml

helm history web -n arx-demo
helm rollback web 1 -n arx-demo --wait --timeout 5m   # writes a NEW revision with revision 1's content
helm uninstall web -n arx-demo                        # deletes the objects and the release history
```

<details>
<summary>Line-by-line explanation</summary>

- `helm upgrade web podinfo/podinfo --version 6.14.0` — Changes the existing release in place and records a new revision. The chart is named again because an upgrade always takes a chart.
- `--reuse-values --set replicaCount=3` — Starts from the last revision's values, so `ui.message` stays `hello`, and changes only the replica count.
- `helm upgrade --install` — Upgrades `web` if it exists and installs it if not, so it works on every run. `-f` reads values from a file; without `--reuse-values`, earlier `--set` overrides are dropped.
- `helm history web` — Lists every revision with its status, chart version and a description such as `Install complete` or `Rollback to 1`.
- `helm rollback web 1` — Goes back to revision 1's chart and values. The number is the revision to return to, taken from `helm history`.
- `helm uninstall web` — There is no undo. Add `--keep-history` if you want the release records kept for inspection afterwards.

</details>

A rollback never deletes revisions. `helm rollback web 1` copies revision 1 into a *new* revision. So after an install, an upgrade and a rollback, `helm history` shows three revisions.

| Flag | What it does | Trap |
| --- | --- | --- |
| `--version 6.14.0` | Picks the chart version, not the app version | Leave it off an upgrade and Helm takes the newest chart in the repository |
| `--set k=v`, `-f values.yaml` | Change values. A dot reaches a nested key, as in `ui.message`. If both are given, `--set` wins. | `--set` turns `4` and `true` into a number and a true/false value. Use `--set-string` when the chart expects text. |
| `--reuse-values` | Starts from the last revision's values, then applies your new ones | Upgrade with `--set` or `-f` but without it, and every earlier value you do not repeat is reset |
| `-n NS --create-namespace` | Sets the release's namespace, and creates it if it is missing | `helm list` does not show the release without the same `-n` (or `-A`) |
| `--wait --timeout 5m` | Waits until the release's Pods are ready, for at most 5 minutes | Without it, Helm reports success as soon as the objects are accepted, even if no Pod ever starts |

> [!NOTE] **Helm 3 or Helm 4**
> Every command in this lesson works the same on Helm 3 and Helm 4; for any other flag, check `helm  --help` first.

> [!IMPORTANT] **What the grader reads**
> The grader reads the release itself. `helm list -n ` gives its name, STATUS and CHART (`podinfo-6.14.0` means chart version 6.14.0). `helm get values` gives your values, and the live objects show what the chart created. A perfect install in `default` scores zero when the question named another namespace. If you go wrong early, uninstall and install again, unless the question is about revisions.

## 📝 Key Takeaways

- A chart is the package. A release is one installed copy of it, with a name, in a namespace.
- `--version` picks the chart version. Repeat it on every upgrade, or Helm moves to the newest chart.
- Every install, upgrade and rollback adds a revision. `helm rollback web 1` copies revision 1 into a new revision.
- Helm looks in one namespace at a time. Use the same `-n` every time, or `-A` to search them all.
- `helm get values` shows only the values you set. Add `--all` to see the chart defaults too.

**📖 Official documentation:**

- [Installing Helm](https://helm.sh/docs/intro/install/) *(search: "installing helm")*
- [Using Helm](https://helm.sh/docs/intro/using_helm/) *(search: "using helm")*
- [helm upgrade](https://helm.sh/docs/helm/helm_upgrade/) *(search: "helm upgrade")*
- [helm rollback](https://helm.sh/docs/helm/helm_rollback/) *(search: "helm rollback")*

---

### 🎯 Task: Install a pinned chart, upgrade it, roll it back

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 7% |
| **Time** | 8 min |

**Question:**

Using Helm and the chart repository `https://stefanprodan.github.io/podinfo` (add it as `podinfo`): first, install a release named `web` of chart `podinfo/podinfo`, chart version `6.14.0`, into namespace `arx-helm` (create the namespace) with `replicaCount` set to 2. Next, upgrade `web` so it runs 4 replicas and shows the UI message `release two` (value `ui.message`), keeping chart version 6.14.0. Finally, the message was not approved: roll `web` back to its first revision. The release must end with exactly three revisions and the Deployment must run 2 replicas.

<details>
<summary>💡 Hints</summary>

- `helm search repo podinfo/podinfo --versions` lists the chart versions. `--version` picks one.
- `helm upgrade` without `--version` takes the newest chart, so pass `--version 6.14.0` again.
- `helm history web -n arx-helm` shows the revisions, and `helm rollback web 1 -n arx-helm` goes back. If you made extra revisions by mistake, run `helm uninstall web -n arx-helm` and start again.

</details>

<details>
<summary>✅ Solution</summary>

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update podinfo
helm install web podinfo/podinfo --version 6.14.0 -n arx-helm --create-namespace \
  --set replicaCount=2 --wait --timeout 5m
helm upgrade web podinfo/podinfo --version 6.14.0 -n arx-helm \
  --reuse-values --set replicaCount=4 --set ui.message="release two" --wait --timeout 5m
helm rollback web 1 -n arx-helm --wait --timeout 5m
helm history web -n arx-helm
```

**Explanation:**

- `helm repo add podinfo` — Registers the repository under the name the task asked for. If it is already there with the same URL, Helm skips it.
- `helm repo update podinfo` — Refreshes just this repository's index, so chart version 6.14.0 is known.
- `helm install web` — Revision 1: the pinned chart version, in a new namespace, with 2 replicas, waiting until the Pods are ready.
- `helm upgrade web` — Revision 2. `--version 6.14.0` is repeated because without it Helm would move to the newest chart.
- `--reuse-values --set replicaCount=4` — Starts from revision 1's values and sets 4 replicas and the new message. The quotes keep `release two` one value despite the space.
- `helm rollback web 1` — Revision 3: a copy of revision 1, so the Deployment goes back to 2 replicas and the default message.
- `helm history web` — Should show exactly three revisions, the last described as `Rollback to 1`.

**Notes:** `helm list -n arx-helm` should show REVISION 3, STATUS deployed and CHART podinfo-6.14.0. Revision 3 is a copy of revision 1. `helm get values web -n arx-helm --revision 2` still shows what the upgrade set. `--reuse-values` is optional here, but keep the habit: it saves you when a question changes one value and expects the others to stay. The Deployment is called `web-podinfo`, because this chart names objects `-`.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-helm

rel=$(helm list -n $ns --filter '^web$' -o json 2>/dev/null)
echo "$rel" | grep -q '"name":"web"' && p "release web exists in $ns" || f "release web exists in $ns"
echo "$rel" | grep -q '"status":"deployed"' && p "status deployed" || f "status deployed"
echo "$rel" | grep -q '"chart":"podinfo-6.14.0"' && p "chart podinfo-6.14.0" || f "chart podinfo-6.14.0"
echo "$rel" | grep -Eq '"revision":"?3"?[,}]' && p "current revision is 3" || f "current revision is 3"
hist=$(helm history web -n $ns -o json 2>/dev/null)
echo "$hist" | grep -o '"revision":2,[^}]*' | grep -q '"chart":"podinfo-6.14.0"' && p "upgrade kept chart 6.14.0" || f "upgrade kept chart 6.14.0"
echo "$hist" | grep -o '"revision":3,[^}]*' | grep -q 'Rollback to 1' && p "revision 3 is a rollback to 1" || f "revision 3 is a rollback to 1"
v2=$(helm get values web -n $ns --revision 2 -o json 2>/dev/null)
echo "$v2" | grep -q '"replicaCount":4' && p "revision 2 set replicaCount 4" || f "revision 2 set replicaCount 4"
echo "$v2" | grep -q '"message":"release two"' && p "revision 2 set ui.message" || f "revision 2 set ui.message"
cur=$(helm get values web -n $ns -o json 2>/dev/null)
echo "$cur" | grep -q '"replicaCount":2' && ! echo "$cur" | grep -q 'release two' && p "current values are revision 1's" || f "current values are revision 1's"
d="kubectl -n $ns get deploy web-podinfo -o jsonpath"
[ "$($d='{.spec.replicas}' 2>/dev/null)" = "2" ] && p "deployment web-podinfo replicas = 2" || f "deployment web-podinfo replicas = 2"
[ "$($d='{.status.availableReplicas}' 2>/dev/null)" = "2" ] && p "2 pods available" || f "2 pods available"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Audit releases: remove the failed one, save the values of another

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 5% |
| **Time** | 6 min |

**Question:**

One Helm release in the cluster is in the `failed` state. Write its namespace and name as `/` to `/tmp/cka/helm/failed-release.txt`, then uninstall it. Next, save the values that were supplied when release `catalog` in namespace `arx-helm-audit` was installed (only the user-supplied values, not the chart defaults) to `/tmp/cka/helm/catalog-values.yaml`. Do not change `catalog`.

<details>
<summary>💡 Hints</summary>

- `helm list -A` shows every namespace, and `--failed` shows only failed releases.
- `helm get values` prints only the values someone supplied. `--all` would add every chart default.

</details>

<details>
<summary>✅ Solution</summary>

```bash
helm list -A --failed
echo "arx-helm-audit/checkout" > /tmp/cka/helm/failed-release.txt
helm uninstall checkout -n arx-helm-audit
helm get values catalog -n arx-helm-audit -o yaml > /tmp/cka/helm/catalog-values.yaml
cat /tmp/cka/helm/catalog-values.yaml
```

**Explanation:**

- `helm list -A --failed` — Lists releases in every namespace, filtered to status `failed`. The NAMESPACE and NAME columns are your answer.
- `echo "arx-helm-audit/checkout"` — Writes `namespace/name` to the file exactly as the task formats it.
- `helm uninstall checkout` — Removes the failed release and everything it created. `-n` is needed because Helm looks for the release only in the namespace you give.
- `helm get values catalog` — Prints only the values supplied at install time. `-o yaml` drops the `USER-SUPPLIED VALUES:` header, so the file is pure YAML.
- `cat /tmp/cka/helm/catalog-values.yaml` — Check the file: the three values set at install (`replicaCount`, `ui.message`, `ui.color`) and no chart defaults.

**Notes:** Without `-o yaml`, `helm get values` prints a `USER-SUPPLIED VALUES:` header line first. That file still works with `helm upgrade -f`, and it passes here. To see why the release failed before you remove it, run `helm status checkout -n arx-helm-audit` and `kubectl -n arx-helm-audit get pods`. The Pods show ImagePullBackOff.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=arx-helm-audit
vf=/tmp/cka/helm/catalog-values.yaml

[ "$(tr -d ' \n' < /tmp/cka/helm/failed-release.txt 2>/dev/null)" = "arx-helm-audit/checkout" ] && p "failed-release.txt names arx-helm-audit/checkout" || f "failed-release.txt names arx-helm-audit/checkout"
helm status checkout -n $ns >/dev/null 2>&1 && f "release checkout uninstalled" || p "release checkout uninstalled"
kubectl -n $ns get deploy checkout-podinfo >/dev/null 2>&1 && f "checkout objects removed" || p "checkout objects removed"
rel=$(helm list -n $ns --filter '^catalog$' -o json 2>/dev/null)
echo "$rel" | grep -q '"status":"deployed"' && echo "$rel" | grep -Eq '"revision":"?1"?[,}]' && p "catalog untouched (revision 1, deployed)" || f "catalog untouched (revision 1, deployed)"
grep -Eq '^replicaCount: 2$' $vf 2>/dev/null && p "values file has replicaCount: 2" || f "values file has replicaCount: 2"
grep -Eq 'message: catalog v1' $vf 2>/dev/null && p "values file has ui.message" || f "values file has ui.message"
[ -s $vf ] && ! grep -q 'logLevel' $vf && p "values file holds user-supplied values only" || f "values file holds user-supplied values only"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 1: Cluster architecture, installation & configuration*
