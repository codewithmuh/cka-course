# How the CKA exam works

> **Module 0** · Lesson 0.1 · 25 minutes

What the exam looks like, how it is graded, what you may use, how results and retakes work, and two study plans for this course.

## Learning Objectives

- You can describe the exam format, the pass mark and what the grader checks.
- You can say what you may use during the exam and what gets a session flagged.
- You can pick a study plan and say which modules you will finish each week.


The CKA is a two-hour exam where you solve real tasks on live Kubernetes clusters. Few people fail it because they do not know what a Pod is. They fail because they run out of time, misread a task, or get surprised by the exam setup. This lesson removes the surprises. Every fact here comes from the official Linux Foundation exam page and candidate handbook, checked in October 2026.

## The format

| Fact | What it means for you |
| --- | --- |
| 15 to 20 tasks | Every task is hands-on: you type commands in a terminal, on real clusters. There is no multiple choice. |
| 2 hours | The clock starts after a short tour of the exam screen. It warns you when 30, 15 and 5 minutes are left. It never pauses, not for a break and not for a lost connection. |
| Pass mark 66% | Each task shows its weight in percent, and all weights add up to 100. Your score is the weight you earned. |
| Kubernetes v1.37 | The exam version at the time of writing. The exam moves to each new version (v1.38, v1.39 …) within four to eight weeks of its release. Check the official page the week you book. |
| Three languages | Questions come in English, Simplified Chinese or Japanese. The terminal and your chat with the proctor (the person who watches you over the webcam) are always in English. |

## How your work is graded

A script grades your work after the exam. It looks only at the end result: the objects in the cluster and the files you wrote. The handbook says any method that gives the correct result is fine.

**What the grader sees**

`You` — type any commands you like → `The cluster` — objects and files change → `The grader` — checks the end result → `Your score` — the weight you earned

- **It cannot see how you got there.** vim or `kubectl edit`, one try or ten: only the result counts.
- **It checks exactly what the task asked.** Say a task wants a Deployment named `web` with 3 replicas in namespace `shop`. The grader looks for `web` in `shop`. If you made it in `default`, the grader finds nothing and the task scores zero.
- **Partial credit is not described** in the official pages. So work as if only finished tasks count. Finish what you start, or flag the task and come back to it.

## The exam environment

You take the exam at home, on your own computer. A company called PSI runs it for the Linux Foundation. You install the **PSI Secure Browser**, which shows a remote Linux desktop. That desktop has a terminal and a Firefox window for the allowed docs. Everything happens inside it: your own terminal, browser and notes are not allowed.

**Where your commands run**

*The infobox of each task names its host. `ssh` to it, do the task, then type `exit` to go back to the base host.*

`Base host` — where you start; no tools here ⟷ `Task host` — kubectl, k and Tab completion ready (`ssh <host>`) ⟷ `A cluster` — the one this task is about

- **The infobox.** Each task opens with a box that names the host to `ssh` to. Some also name a kubectl *context* (kubectl's saved setting for which cluster to talk to) or a namespace.
- **Ready tools.** On the task host, `kubectl` already has the `k` alias and Tab completion. You also get `yq`, `curl`, `wget` and man pages.
- **Root.** `sudo -i` makes you root, which work on a node needs.
- **Back to base.** When a task is done, type `exit` to return to the base host. Do not ssh from one task host to another, and never reboot the base host.
- **Several clusters.** The official pages do not say how many. Expect more than one, and treat the infobox as part of the question.

The rules on what you may use are strict:

| Allowed | Not allowed |
| --- | --- |
| kubernetes.io/docs, its search box and its translations | Opening a search result that leads to another site |
| kubernetes.io/blog | Any other website, including forums and GitHub |
| helm.sh/docs | Notes, books, a second screen, a phone or a smart watch |
| gateway-api.sigs.k8s.io (CKA only) | Headphones or earbuds, unless you need them for medical reasons |
| Links in a task's Quick Reference box, and man pages on the host | Reading questions aloud, or leaving the camera view without permission |
| Clear water in a glass or in a bottle with no label | Eating, chewing gum, or anyone else in the room |

> [!IMPORTANT] **The first step of every task**
> Before you change anything, do what the infobox says: `ssh` to the named host, and switch to the context or namespace if the task names one. A perfect answer on the wrong cluster scores zero, and nothing tells you why. [kubectl fluency](/cka/foundations/kubectl-fluency) shows the commands, and every mock in this course makes you practice the habit.

## Results, retakes and booking

| Topic | The rule |
| --- | --- |
| Results | Your score arrives by email within 24 hours (with rare exceptions) and also shows in My Portal. It does not say how you did on each task. |
| Retake | One retake comes with your registration. After a No Pass, you claim it from your Exam Preparation Checklist. You must use it inside your eligibility window. If you miss your slot (a no-show), you lose both the exam fee and the retake. |
| Validity | The certificate is valid for 2 years from the day you pass. To renew it, pass the exam again before it expires. |
| Booking | You have 12 months from registration to book and take the exam. You can book a slot from 90 days to 24 hours ahead. You can move or cancel it up to 24 hours before the start, not later. |
| Simulator | Standard registrations include two sessions of the Killer.sh practice simulator, 36 hours each. The exam-only SINGLE products do not. |
| Price | It changes with promotions and bundles. Check the official page. |

What to do the week before, on the day itself and after the exam is in the [final checklist](/cka/exam/final-checklist).

## The five domains

The exam covers five areas, called **domains**. Each has a weight: its share of the points. Troubleshooting alone is almost a third of the exam. Each domain has its own module in this course:

| Domain | Weight | Module in this course |
| --- | --- | --- |
| Troubleshooting | 30% | Module 5: a method, app failures, the control plane, nodes, Services and DNS, logs, metrics, kubectl debug |
| Cluster Architecture, Installation & Configuration | 25% | Module 1: components, kubeadm, upgrades, etcd, high availability, certificates, RBAC, Helm, Kustomize, CRDs, CNI/CSI/CRI |
| Services & Networking | 20% | Module 3: pod networking, Services, CoreDNS, Ingress, Gateway API, NetworkPolicies |
| Workloads & Scheduling | 15% | Module 2: Pods, Deployments, config, resources, scheduling, controllers, probes, HPA, admission |
| Storage | 10% | Module 4: volumes, PV and PVC, StorageClasses, StatefulSets |

**The readiness meter** on [/cka](/cka) grows as you pass tasks, and each domain counts by its exam weight. Pass every troubleshooting task and it rises by 30 points; pass every storage task and it rises by 10.

## Two study plans

Pick the plan that fits your time. Both cover the whole course: every module, the lightning lab and both mock exams.

| 4 weeks, about 1.5 h per day | Modules |
| --- | --- |
| Week 1 | Module 0: all four lessons, and your lab built. Module 1, lessons 1 to 6: components to certificates. |
| Week 2 | Module 1, lessons 7 to 11: RBAC, Helm, Kustomize, CRDs, extension interfaces. Module 2: all nine lessons. |
| Week 3 | Module 3: all six lessons. Module 4: all four. Module 5, lessons 1 to 4. |
| Week 4 | Module 5, lessons 5 to 8. The lightning lab. Mock 1. Redo the weakest domain on the meter. Mock 2. The cheat sheet and the final checklist. |

| 8 weeks, about 45 min per day | Modules |
| --- | --- |
| Week 1 | Module 0: the exam, the lab, kubectl fluency, exam-day habits |
| Week 2 | Module 1, lessons 1 to 6: components, kubeadm install, upgrades, etcd, high availability, certificates |
| Week 3 | Module 1, lessons 7 to 11: RBAC, Helm, Kustomize, CRDs, CNI/CSI/CRI |
| Week 4 | Module 2: all nine workloads and scheduling lessons |
| Week 5 | Module 3: all six networking lessons |
| Week 6 | Module 4: storage. Module 5, lessons 1 to 3. |
| Week 7 | Module 5, lessons 4 to 8. The lightning lab. |
| Week 8 | Mock 1. Redo the weakest domain. Mock 2. The cheat sheet and the final checklist. |

## 📝 Key Takeaways

- 15 to 20 hands-on tasks in 2 hours. You pass with 66%.
- A script grades the end result: the objects in the cluster and the files you wrote. It never sees your commands.
- Start every task with the infobox: `ssh` to the named host, switch context or namespace if asked, and `exit` when done.
- Only kubernetes.io, helm.sh/docs and the Gateway API site are allowed. No notes, no second screen, no phone.
- Troubleshooting (30%) and architecture (25%) are more than half of the points.

**📖 Official documentation:**

- [CKA exam page (Linux Foundation)](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) *(search: "certified kubernetes administrator")*
- [Important Instructions: CKA and CKAD](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) *(search: "important instructions cka")*
- [Candidate Handbook (PSI Bridge)](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2) *(search: "candidate handbook")*
- [Resources allowed during the exam](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed) *(search: "resources allowed")*

---

### 🎯 Task: Write the domain weights to a file

| Detail | Value |
| --- | --- |
| **Domain** | architecture |
| **Weight** | 2% |
| **Time** | 2 min |

**Question:**

Write the five CKA exam domains and their weights to `/tmp/cka/domains.txt`, one per line, in the form `domain=weight`. Use the lowercase single-word domain names this course uses: `troubleshooting`, `architecture`, `networking`, `workloads`, `storage`. Example line: `troubleshooting=30`. The file must contain exactly those five lines and nothing else.

<details>
<summary>💡 Hints</summary>

- The weights are in the domains table above. The lines can be in any order.
- A heredoc (`cat > file <<'EOF'`, the five lines, then `EOF`) or five `echo` lines both work. Check the result with `cat`.

</details>

<details>
<summary>✅ Solution</summary>

```bash
mkdir -p /tmp/cka
cat > /tmp/cka/domains.txt <<'EOF'
troubleshooting=30
architecture=25
networking=20
workloads=15
storage=10
EOF
cat /tmp/cka/domains.txt
```

**Explanation:**

- `mkdir -p /tmp/cka` — Creates the folder `/tmp/cka`. `-p` means no error if it already exists, and any missing parent folders are created too.
- `cat > /tmp/cka/domains.txt` — Writes the lines that follow into `domains.txt`, up to the line `EOF`. This is a *heredoc*: a way to type a whole file in one command, with no editor.
- `troubleshooting=30` — One line per exam domain with its weight in percent. The grader reads the file, so spelling and format must match the task exactly.
- `EOF` — Ends the heredoc. It must be alone on its line, with nothing before it.
- `cat /tmp/cka/domains.txt` — Prints the file so you can check it before moving on.

**Notes:** Every "write a file" task on the exam looks like this: an exact path, an exact format, no extra lines. Always `cat` the file before you move on. The usual ways to lose these points are a blank line at the end, or a stray prompt character pasted into the file.

</details>

<details>
<summary>🔍 Verification script</summary>

```bash
fails=0
p() { echo "PASS  $1"; }
f() { echo "FAIL  $1"; fails=$((fails+1)); }
file=/tmp/cka/domains.txt

[ -f "$file" ] && p "file exists" || f "file exists"
[ "$(grep -c . "$file" 2>/dev/null)" = "5" ] && p "exactly five non-empty lines" || f "exactly five non-empty lines"
for line in troubleshooting=30 architecture=25 networking=20 workloads=15 storage=10; do
  grep -qx "$line" "$file" 2>/dev/null && p "line $line" || f "line $line"
done

[ $fails -eq 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL ($fails)"; exit 1; }
```

</details>

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 0: Start here*
