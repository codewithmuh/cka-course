#!/usr/bin/env bash
# Deletes the CKA lab cluster. Nothing else on your machine is touched.
set -euo pipefail
kind delete cluster --name cka
