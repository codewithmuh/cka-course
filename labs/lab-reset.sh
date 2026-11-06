#!/usr/bin/env bash
# Resets the CKA lab to a clean state by deleting and recreating the cluster.
# Takes two to four minutes. Use it between mock exams.
set -euo pipefail
BASE="${CKA_LAB_BASE:-https://codewithmuh.com/labs/cka}"
kind delete cluster --name cka || true
curl -fsSL "$BASE/lab-up.sh" | bash
