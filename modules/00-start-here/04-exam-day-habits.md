# Exam-day habits: vim, docs, time

> **Module 0** · Lesson 0.4 · 30 minutes

Set up vim, budget your time, read tasks twice, search the docs fast, and avoid the traps that turn right answers into zero.

## Learning Objectives

- You can set up vim in ten seconds, so YAML indents correctly and pasted text stays in place.
- You can budget time by task weight, and decide in under a minute whether to flag a task and move on.
- You can name the common ways a correct-looking answer scores zero, and check for each before you leave a task.


Most people who fail the CKA know enough Kubernetes. They lose points in small ways: the wrong namespace, a tab in a YAML file, twenty minutes on a 4% task, or a question answered from memory. This lesson builds the habits that stop those losses. They are cheap to build in the lab. The two tasks at the end are small on purpose: the routine is the point.

## vim that behaves

vim is the text editor you will use in the exam terminal. Out of the box, its Tab key types a tab character, and YAML refuses tabs. One line in vim's settings file, `~/.vimrc`, fixes that.

**First thing on each exam host, right after the kubectl aliases**

```bash
cat > ~/.vimrc <<'EOF'
set ts=2 sw=2 et nu
EOF
# ts=2  tabstop: a tab displays as two columns
# sw=2  shiftwidth: > and < indent by two spaces
# et    expandtab: the Tab key inserts spaces, never a tab character (YAML rejects tabs)
# nu    line numbers, so error messages like "line 23" mean something

# Inside vim:
#   :set paste        before pasting from the docs (stops auto-indent from staircasing the text)
#   :set nopaste      after, or your Tab key and indentation stop working
#   Ctrl+v  j j j  >  select a block of lines, indent them one shiftwidth; . repeats it
#   Ctrl+v  j j j  <  outdent
#   :%s/old/new/g     replace everywhere; :%s/\t/  /g turns tabs into two spaces
#   :set list         show tabs as ^I so you can find them; :set nolist to hide again
#   u / Ctrl+r        undo / redo;  :w  save;  :q!  quit without saving
```

<details>
<summary>Line-by-line explanation</summary>

- `cat > ~/.vimrc` — Writes vim's settings file in your home folder with a heredoc: everything up to the line `EOF` goes into the file. Faster than opening vim to configure vim.
- `set ts=2 sw=2 et nu` — Four settings in one line, explained in the comments below. The one that saves YAML is `et`: the Tab key inserts spaces, because YAML refuses tab characters.
- `# Inside vim:` — The lines below are typed inside vim, not in the shell. Press Esc first; commands that start with `:` appear at the bottom of the screen.

</details>

The exam desktop has its own keyboard rules:

- **Terminal:** copy with `Ctrl+Shift+C` and paste with `Ctrl+Shift+V`, or use the right-click menu.
- **Firefox:** the usual `Ctrl+C` and `Ctrl+V`. `Ctrl+W` closes the browser tab, so close a terminal tab with `Ctrl+Alt+W` instead.
- **No Insert key:** it is blocked in the exam. In vim, press `i` to start typing and `Esc` to stop.
- **tmux is optional.** It can show a second pane that watches `kubectl get pods -w`. If you do not already use it every day, a second terminal tab does the same job.

## Time: one minute per percentage point

Give each task as many minutes as its weight in percent: a 4% task gets 4 minutes. All tasks together then take about 100 of your 120 minutes. The 20 minutes left are for flagged tasks and a last check.

**How to spend the two hours**

`About 100 minutes` — every task once, one minute per point → `Last 20 minutes` — flagged tasks, highest weight first → `Final pass` — check names, namespaces and files

| Task weight | Budget | When the budget runs out |
| --- | --- | --- |
| 2% | 2 minutes | Not done? Leave what you have, flag it, move on. |
| 4% | 4 minutes | The same rule. Most 4% tasks are two commands and a check. |
| 6 to 8% | 6 to 8 minutes | Usually several steps, such as an RBAC chain, an Ingress plus a Service, or a broken node. Do the parts you are sure of first. |
| Any task, after 12 minutes | Stop | Flag it and move on. No single task is worth more of your time than that. |
| Last 20 minutes | Reserve | Go back to flagged tasks, highest weight first. Then do one final check pass. |
| Order | As given | Work the tasks in order, unless one is clearly long. Jumping around means reading tasks twice. Flag tasks in the exam screen, not in your head. |

## Read twice, check once

- **Read the whole task before you type.** Then read it again and note the nouns: namespace, names, image tag, replica count, file path, label keys. Many tasks hide one more requirement in the last sentence.
- **Copy names from the question, never retype them.** Select the name in the question, then paste it into the terminal. After 90 minutes, `web-api` and `web-apl` both look right.
- **Host and context first.** Follow the infobox: `ssh` to the named host, and switch context or namespace if the task names one. When you finish, `exit` back to the base host.
- **Set the namespace once** if the whole task is in one: `k config set-context --current --namespace=`. The setting stays for the next task on the same host, so remember you changed it.
- **Check the result, not what you meant to do.** The table below has one quick check for each kind of task.
- **Grep the live object** when the question lists fields: `k get pod web -o yaml | grep -E 'image:|serviceAccountName|nodeName|tier'`. It takes five seconds. It catches a wrong tag, a missing label or a Pod on the wrong node.
- **Leave the cluster as you found it,** apart from what the task asked. Uncordon a node you cordoned to test something, delete a test Pod, undo a namespace switch. Leftovers can break the grading of a later task.

| To check | Run |
| --- | --- |
| Replicas and image of a Deployment | `k get deploy web -n ns -o wide` |
| The Pods are Running | `k get pods -n ns -l app=web` |
| A rollout has finished | `k rollout status deploy/web -n ns` |
| An answer file | `cat` the file |
| RBAC | `k auth can-i   --as= -n ns` |
| A Service or an Ingress | `curl` its address |

## Finding things in the docs

You may open kubernetes.io during the exam, but browsing it is slow. Two habits make it fast:

- **Try `kubectl explain` first.** `k explain deploy.spec.strategy` prints what each field means, right in the terminal. It is faster than any search.
- **Search by phrase.** When you need a full YAML example, type a short phrase into the kubernetes.io search box and open the page with the matching title. Do not click through the menus.

| Topic | Type into the search box | Open the page titled |
| --- | --- | --- |
| Roles, bindings, verbs | rbac | Using RBAC Authorization |
| etcd snapshot save and restore | etcd backup | Operating etcd clusters for Kubernetes |
| NetworkPolicy YAML, default deny | network policies | Network Policies |
| Helm commands | (search helm.sh/docs instead, for example `helm upgrade`) | Helm Upgrade |

The [cheat sheet](/cka/exam/cheat-sheet) has the full table: one search phrase for every exam topic.

## The trap list

Each of these turns a correct-looking answer into zero points. Check for them before you leave a task.

- **Wrong namespace.** Your object works, but the grader looks in the namespace the question named, so use `-n` on every command or set it in the context.
- **Wrong host or context.** Your work is on another cluster, so read the infobox first, always.
- **Skipping `rollout status`.** A wrong image tag means the new Pods never start, and you only see it if you wait for the rollout.
- **Editing a Pod field that cannot change.** Most of a running Pod's spec is fixed; [kubectl fluency](/cka/foundations/kubectl-fluency) shows the `replace --force` way around it.
- **A NodePort outside its range.** NodePorts are 30000 to 32767 by default, so a number like 3080 is probably the Service port ([Services](/cka/networking/services)).
- **maxSurge and maxUnavailable rounding.** Their percentages round in opposite directions, so write a whole number when a task needs an exact count ([Deployments](/cka/workloads/deployments-rollouts-rollbacks)).
- **Secret values.** If you base64-encode by hand, use `echo -n`, or a hidden newline becomes part of the value ([ConfigMaps and Secrets](/cka/workloads/configmaps-and-secrets)).
- **Tabs in YAML.** YAML refuses tab characters, so set `expandtab` in vim and fix a bad paste with `:%s/\t/  /g`.
- **Selector and labels that do not match.** You get a Service with no endpoints or a policy that selects nothing ([Service and DNS failures](/cka/troubleshooting/service-and-dns-failures)).
- **The container name in `set image`.** In `k set image deploy/web nginx=nginx:1.26`, the part before `=` is the container's name, not the image's name.
- **A file in the wrong place.** The grader does not search for your file, so write it to the exact path (`mkdir -p` the folder first) and check it with `cat`.
- **Forgetting `sudo -i` on a node.** Without root you cannot read the files in `/etc/kubernetes/manifests`, and `journalctl -u kubelet` may show nothing.

> [!IMPORTANT] **What a task really costs**
> A 4% task done right is 4 points. The same task done perfectly in the wrong namespace is 0 points, and it usually cost you 6 minutes. Twenty seconds spent checking the namespace, the name and the image against the question is the best trade in the exam. Every task in this course ends with a check script to build that habit. On the exam, the check script is you.

## The first two minutes

On the first task host, set up your shell (the aliases from [kubectl fluency](/cka/foundations/kubectl-fluency)) and write the vimrc above. Run `k get nodes` to make sure the terminal works. Then start task one, and read it twice. What to do the night before and on the morning of the exam is in the [final checklist](/cka/exam/final-checklist).

## 📝 Key Takeaways

- One minute per percentage point. Over budget? Flag the task and move on.
- Read every task twice, and paste names from the question instead of typing them.
- Infobox first: the right host, the right context, the right namespace.
- Check the end result before you leave a task: `get`, `rollout status`, `cat`.
- `set ts=2 sw=2 et` in `~/.vimrc` keeps tab characters out of your YAML.

**📖 Official documentation:**

- [Exam Rules and Policies (handbook)](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/exam-rules-and-policies) *(search: "exam rules and policies")*
- [ExamUI: Performance Based Exams (handbook)](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/exam-user-interface/examui-performance-based-exams) *(search: "examui performance based")*
- [Candidate Identification and Authentication (handbook)](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/candidate-identification-and-authentication) *(search: "candidate identification")*
- [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) *(search: "cheat sheet")*

---

### 🎯 Task: Write your exam vimrc

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 2% |
| **Time** | 2 min |

**Question:**

Write the vim configuration you will use on the exam to `/tmp/cka/vimrc`. It must set `tabstop` to 2, `shiftwidth` to 2 and enable `expandtab`. Short option names are fine. You may add other settings.

<details>
<summary>💡 Hints</summary>

- One line is enough: `set ts=2 sw=2 et`
- To test it, run `vim -u /tmp/cka/vimrc somefile` and press Tab in insert mode. Then type `:set list`: a tab character would show as `^I`, spaces show as blanks.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
printf 'set ts=2 sw=2 et nu\n' > /tmp/cka/vimrc
cat /tmp/cka/vimrc
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the folder if it is not there yet.
- `printf` — Writes the settings line to the file. `printf` is a one-line alternative to a heredoc, and `\n` adds the final newline.
- `cat /tmp/cka/vimrc` — Shows the file so you can check every character.

**Notes:** On the exam the file is `~/.vimrc` on each host you work on. The base host has no tools, so write it on the task host after you `ssh` in. A one-line heredoc or `printf` is faster than opening vim to set up vim. Add `nu` for line numbers, so a YAML error that names a line is easy to find.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/vimrc

[ -s "$file" ] && p "file exists and is not empty" || f "file exists and is not empty"
grep -qE '(^|[[:space:]])(ts|tabstop)=2([[:space:]]|$)' "$file" 2>/dev/null && p "tabstop=2" || f "tabstop=2"
grep -qE '(^|[[:space:]])(sw|shiftwidth)=2([[:space:]]|$)' "$file" 2>/dev/null && p "shiftwidth=2" || f "shiftwidth=2"
grep -qE '(^|[[:space:]])(et|expandtab)([[:space:]]|$)' "$file" 2>/dev/null && p "expandtab" || f "expandtab"
! grep -qE '(^|[[:space:]])(noet|noexpandtab)([[:space:]]|$)' "$file" 2>/dev/null && p "expandtab not disabled" || f "expandtab not disabled"

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

### 🎯 Task: Read it twice: scale exactly one Deployment

| Detail | Value |
| --- | --- |
| **Domain** | workloads |
| **Weight** | 3% |
| **Time** | 4 min |

**Question:**

Namespace `fd-habits` contains several Deployments with similar names. Scale the Deployment `billing-api` to 3 replicas and add the label `tier=backend` to that Deployment. Do not modify any other Deployment in the namespace.

<details>
<summary>💡 Hints</summary>

- Run `kubectl get deploy -n fd-habits` first. Then copy the name from the question instead of typing it.
- Use `kubectl scale` and `kubectl label`. Then run `kubectl get deploy -n fd-habits --show-labels` to check that only one Deployment changed.

</details>

<details>
<summary>✅ Solution</summary>

```bash
kubectl -n fd-habits get deploy
kubectl -n fd-habits scale deploy billing-api --replicas=3
kubectl -n fd-habits label deploy billing-api tier=backend
kubectl -n fd-habits rollout status deploy/billing-api --timeout=120s
kubectl -n fd-habits get deploy --show-labels
```

**Explanation:**

- `get deploy` — Look before you change anything: confirm the Deployment's exact name and its current state.
- `scale deploy billing-api` — Sets the number of replicas, the copies of the Pod, to 3. Kubernetes starts or stops Pods to match.
- `label deploy billing-api` — Adds the label `tier=backend` to the Deployment object itself, not to its Pods.
- `rollout status` — Waits until all 3 replicas are up.
- `--show-labels` — Final check: replica count and labels exactly as the task asked.

**Notes:** The namespace holds three Deployments with almost the same name: `billing-api`, `billing-app` and `biling-api`. Each look-alike is one letter away from `billing-api`. Tab completion is a trap here, because `billing-ap` matches two names. Paste the name from the question. The check script makes sure the other two Deployments are untouched, which is what a grader does when a question says "do not modify".

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
ns=fd-habits
g() { kubectl -n $ns get deploy "$1" -o jsonpath="$2" 2>/dev/null; }

kubectl -n $ns get deploy billing-api >/dev/null 2>&1 && p "deployment billing-api exists" || f "deployment billing-api exists"
[ "$(g billing-api '{.spec.replicas}')" = "3" ] && p "billing-api replicas = 3" || f "billing-api replicas = 3"
[ "$(g billing-api '{.status.availableReplicas}')" = "3" ] && p "billing-api 3 pods available" || f "billing-api 3 pods available"
[ "$(g billing-api '{.metadata.labels.tier}')" = "backend" ] && p "billing-api label tier=backend" || f "billing-api label tier=backend"
for other in billing-app biling-api; do
  [ "$(g $other '{.spec.replicas}')" = "1" ] && p "$other still has 1 replica" || f "$other still has 1 replica"
  [ -z "$(g $other '{.metadata.labels.tier}')" ] && p "$other has no tier label" || f "$other has no tier label"
done

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 0: Start here*
