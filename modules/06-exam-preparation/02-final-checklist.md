# Final checklist and readiness

> **Module 6** · Lesson 6.2 · 15 minutes

When to book, what to do in the last two weeks, on exam day and after it, and a self-check for each domain.

## Learning Objectives

- You can decide whether you are ready to book, using the readiness meter, the mocks and the self-check table.
- You can arrive on exam day with the ID, room and computer checks already done.
- You can say what happens after the exam and when to use the retake.


You can measure whether you are ready. The [readiness meter](/cka) shows how much of the course you have proved, weighted like the exam. The [mocks](/cka/mock/mock-1) show whether you can do it against the clock. Book the exam when Mock 2 is well above the pass mark with time left over, not when you have finished reading.

**When to book**

`Course tasks` — the readiness meter fills up → `Mock 1` — two hours, exam rules → `Mock 2` — well above 66%, time left over → `Book the exam` — you are ready

The facts about the exam process on this page come from the Linux Foundation handbook and the CKA instructions page. The format and the rules are in [How the CKA exam works](/cka/foundations/how-the-exam-works).

## Two weeks out

- Do the [lightning lab](/cka/mock/lightning) again, cold. If a task takes longer than its weight in minutes, put its lesson on your list for the next step.
- Do [Mock 1](/cka/mock/mock-1) under exam rules: two hours, one terminal, kubernetes.io only, no pauses. Reset the lab first with `lab-reset.sh`.
- Open the [readiness meter](/cka). Pick the weakest domain and redo its tasks from scratch, not from your notes. Troubleshooting (30%) and architecture (25%) pay back the time fastest.
- If you have never done a kubeadm upgrade on real VMs, do it once now ([Upgrading clusters and draining nodes](/cka/architecture/cluster-upgrades)). kind cannot practice it, and it is a regular exam task.
- Read the [cheat sheet](/cka/exam/cheat-sheet) from top to bottom. Try every block you cannot yet type from memory.

## One week out

- **Book,** if you have not yet. My Portal shows the exam, and its Schedule button takes you to PSI. You can book a slot from 90 days to 24 hours ahead. You can change a booking only until 24 hours before the start.
- **Check your ID.** The name on it must match your Linux Foundation account exactly. The ID must be an original, unexpired, government-issued document with your photo and signature. Fix a mismatch with support now, not on the day.
- **Check your computer.** Run PSI's system check and the Secure Browser test from the handbook, on the computer you will use. You need one monitor only, no virtual machine, a webcam you can pick up to show the room, a microphone, and your most reliable network.
- **Check your room.** A private room with walls and a door. A desk with no papers or electronics on it. Good light, with no window or bright light behind you. Nobody else in the room for two hours.
- **Do [Mock 2](/cka/mock/mock-2)** under exam rules, after a `lab-reset.sh`. Compare the score and the time left with Mock 1. If you are under the pass mark, move the booking instead of hoping. The course will still be here.
- **Pick the question language:** English, Simplified Chinese or Japanese. The terminal and the proctor stay in English either way.

## The day before and the morning of

- **Day before:** no new topics. Do the lightning lab one last time and read the trap list in [Exam-day habits](/cka/foundations/exam-day-habits). Put your ID, a clear bottle of water with no label and the computer charger on the desk. Clear everything else off it. Sleep.
- **Day before:** remove or turn off anything the Secure Browser may flag: a second display, screen-sharing or remote-control tools, virtual cameras. Close every other app before you launch the exam.
- **Morning:** eat first, because eating and gum are not allowed during the exam. Use the restroom before check-in. The handbook does not describe breaks, you may not leave the camera view without the proctor's permission, and the timer never pauses.
- **Morning:** phone, watch and notes go out of the room. Click Take Exam up to 30 minutes before your slot. If you start more than 30 minutes late, you are a no-show and lose the fee and the retake.
- **Check-in:** an ID photo, a selfie, the agreement, then a live scan of your room and desk with a check-in specialist. The wait should not be more than 15 minutes. Then the proctor releases the exam.

**Exam day, step by step**

*Starting more than 30 minutes after your slot makes you a no-show.*

`Take Exam` — click up to 30 minutes early → `Check-in` — ID, selfie, room scan → `Interface tour` — watch it or hide it → `2 hours` — the clock starts and never pauses

## During the exam

- **Host and context first.** Follow the infobox on every task: `ssh` in, switch context or namespace if the task names one, and `exit` when done.
- **Read twice, copy names.** Note the namespace, names, images, counts and paths before you type. Paste names from the question.
- **One minute per percent.** Over budget? Flag the task and move on. Come back in the last 20 minutes, highest weight first.
- **Check the end state.** `get -o wide`, `rollout status`, `cat` the file, `auth can-i`, `curl`. The grader reads the object, not what you meant to do.
- **Search the docs by phrase, do not browse.** Type the phrase from the cheat sheet's table into the kubernetes.io search box. Copy the YAML, run `:set paste` in vim, paste, adapt, apply. Never open a search result outside the allowed sites.

## After the exam

- **Finish:** click End Exam, then End Session. A script scores the exam. The score report arrives by email within 24 hours (with rare exceptions) and shows in My Portal. It does not show how you did on each task.
- **On a pass:** within three business days you get the certificate notice, with your Certificate ID and the PDF, and a Credly digital badge. Add it to LinkedIn. The certification is valid for two years from the day you pass.
- **On a No Pass:** if you are eligible, your checklist shows a Claim Your Retake button. You must take the retake inside your 12-month eligibility window. Do not book it the same week. First redo the two weakest domains on the readiness meter. Then do both mocks again, with a lab reset before each. Book when Mock 2 is well above the pass mark.
- **Rescore:** you can ask for one within two days, for a fee. For a hands-on exam graded by a script, it is rarely worth it.
- **Either way,** once the exam is over, write down which task types cost you the most time. That list is the best study guide you will get, for this exam or for the CKS (the Kubernetes security exam).

> [!IMPORTANT] **A quick readiness test**
> Take a task you have not seen, from any domain. You are ready if you can do three things. Know within 30 seconds which docs page or `kubectl explain` path you need. Finish the task within its weight in minutes. Prove the end state with one command before you move on. If any of these still feels like guessing in a domain, that domain gets your next study hour.

## Self-check: three yes answers per domain

Answer each question with an honest yes or no. Every no shows you what to study next.

| Domain | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Troubleshooting (30%) | A Pod is not Running. Can I find the cause (image, probe, mount, scheduling, config) from describe and logs in under three minutes? | A node is NotReady, or the control plane does not answer. Can I find the broken service or static Pod on the node with systemctl, journalctl and crictl, and fix it? | A Service returns nothing. Can I check the selector, endpoints, targetPort, DNS and NetworkPolicy in that order? Can I read kubectl top to spot a resource problem? |
| Architecture (25%) | Can I write a Role, a ClusterRole and both kinds of binding, for a user and for a ServiceAccount, and prove them with auth can-i? | Can I do a kubeadm minor upgrade in order (packages, upgrade plan, apply or node, drain, kubelet, uncordon)? Can I save and restore an etcd snapshot with the certificate flags? | Can I install and upgrade a Helm release with a values file, render a Kustomize overlay, and read a CRD's fields with kubectl explain? |
| Networking (20%) | Can I create each Service type, explain port, targetPort and nodePort, and reach the Service by its DNS name from a Pod? | Can I write an Ingress with host and path rules, and a Gateway plus an HTTPRoute with a backendRef? Can I test the Ingress with curl and a Host header? | Can I write a default-deny NetworkPolicy, then allow exactly one source and one port, plus DNS egress? Do I know when two selectors mean AND and when they mean OR? |
| Workloads (15%) | Can I update an image, watch the rollout, roll back to a named revision, and set maxSurge and maxUnavailable for an update with no downtime? | Can I place a Pod with nodeSelector, node affinity, pod anti-affinity, a toleration or a topology spread? Can I read the FailedScheduling event when it does not land? | Can I add the three probes, requests and limits, a ConfigMap or Secret (as env and as a volume), a sidecar, and an autoscaling/v2 HPA? |
| Storage (10%) | Can I create a PV and a PVC that bind, and explain why a claim stays Pending (class, size, access mode, WaitForFirstConsumer)? | Can I write a StorageClass, make it the default, and say what Retain and Delete do to the PV when the claim is deleted? | Can I mount a PVC in a Pod and through a StatefulSet's volumeClaimTemplates, and check that the data survives a Pod restart? |

## 📝 Key Takeaways

- Book the exam when Mock 2 is well above 66% with time to spare, not when you finish reading.
- A week before: the name on your ID must match your account exactly, and the system check must pass on the computer you will use.
- The day before: no new topics. The lightning lab, the trap list, then sleep.
- During the exam: infobox first, read twice, one minute per percent, check the end state.
- Results arrive within 24 hours. A No Pass comes with one retake: study your weakest domains before you use it.

**📖 Official documentation:**

- [Candidate Handbook: Taking the Exam](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/taking-the-exam) *(search: "taking the exam")*
- [Candidate Handbook: Exam Scoring and Notification](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/exam-scoring-and-notification) *(search: "exam scoring")*
- [CKA, CKAD and CKS FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks) *(search: "faq cka")*
- [CKA exam page (Linux Foundation)](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) *(search: "certified kubernetes administrator")*

---

*Course: [codewithmuh.com/cka](https://codewithmuh.com/cka) · Module 6: Exam preparation*
