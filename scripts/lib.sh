#!/usr/bin/env bash
# Shared helpers. Source me:  source "$(dirname "$0")/lib.sh"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
[[ -f "$ROOT/lab.env" ]] && set -a && source "$ROOT/lab.env" && set +a
source "$ROOT/scripts/versions.env"

: "${AWS_REGION:=ap-southeast-1}"
: "${CLUSTER_NAME:=eks-lab}"
export AWS_REGION CLUSTER_NAME

c_ok=$'\e[32m'; c_bad=$'\e[31m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
log()  { echo "${c_dim}[$(date +%H:%M:%S)]${c_off} $*"; }
die()  { echo "${c_bad}ERROR:${c_off} $*" >&2; exit 1; }

# Terraform outputs of the lab env, cached per run in .lab/outputs.json
tf_outputs() {
  mkdir -p "$ROOT/.lab"
  terraform -chdir="$ROOT/terraform/envs/lab" output -json > "$ROOT/.lab/outputs.json"
}
tfo() { jq -r --arg k "$1" '.[$k].value // "" | if type=="object" then tojson else . end' "$ROOT/.lab/outputs.json"; }

helm_repos() {
  helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
  helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ >/dev/null 2>&1 || true
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update >/dev/null
}

# ---- tiny test framework for verify.sh scripts --------------------------------
PASS=0; FAIL=0
check() {  # check "description" command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ${c_ok}✔${c_off} $desc"; PASS=$((PASS+1))
  else echo "  ${c_bad}✘${c_off} $desc"; FAIL=$((FAIL+1)); fi
}
summary() {
  echo; echo "Passed: $PASS   Failed: $FAIL"
  [[ $FAIL -eq 0 ]] && echo "${c_ok}Level complete!${c_off}" || { echo "${c_bad}Not there yet — see the ✘ lines.${c_off}"; exit 1; }
}
# Retry a command for up to N seconds (default 120)
eventually() { local t=${EVENTUALLY_TIMEOUT:-120}; local end=$((SECONDS+t)); until "$@"; do (( SECONDS > end )) && return 1; sleep 5; done; }
