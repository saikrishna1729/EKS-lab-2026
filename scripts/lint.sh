#!/usr/bin/env bash
# Static checks — no AWS calls, nothing created.
#   terraform fmt + validate (all stacks) · tflint · kustomize builds · helm template of every
#   pinned chart with our values · kubeconform schema validation (if installed)
source "$(dirname "$0")/lib.sh"
cd "$ROOT"; rc=0
step() { echo; echo "== $*"; }

step "terraform fmt"
terraform fmt -check -recursive bootstrap terraform || rc=1

step "terraform validate"
for d in bootstrap terraform/envs/lab terraform/envs/dr; do
  terraform -chdir=$d init -backend=false -input=false >/dev/null && terraform -chdir=$d validate -no-color | sed "s#^#  $d: #" || rc=1
done

if command -v tflint >/dev/null; then
  step "tflint"
  for d in terraform/modules/* terraform/envs/*; do tflint --chdir=$d --minimum-failure-severity=error || rc=1; done
fi

step "kustomize builds"
for o in k8s/apps/shop/overlays/*; do
  kubectl kustomize "$o" >/dev/null && echo "  ok $o" || { echo "  FAIL $o"; rc=1; }
done

step "helm template (pinned versions + our values)"
OUT="$ROOT/.lab/rendered"; mkdir -p "$OUT"
render() { # name repo chart version namespace [extra args...]
  local n=$1 repo=$2 chart=$3 ver=$4 ns=$5; shift 5
  local ref="$repo/$chart"; [[ $repo == oci://* ]] && ref="$repo/$chart"
  if helm template "$n" "$ref" --version "$ver" -n "$ns" -f "k8s/platform/values/$n.yaml" "$@" > "$OUT/$n.yaml" 2>"$OUT/$n.err"; then
    echo "  ok $n $ver"
  else echo "  FAIL $n $ver: $(head -3 "$OUT/$n.err")"; rc=1; fi
}
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo add fairwinds https://charts.fairwinds.com/stable >/dev/null 2>&1 || true
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add opencost https://opencost.github.io/opencost-helm-chart >/dev/null 2>&1 || true
helm_repos
render aws-load-balancer-controller eks aws-load-balancer-controller "$AWS_LBC_CHART" kube-system --set clusterName=x --set region=x --set vpcId=vpc-1
render external-dns external-dns external-dns "$EXTERNAL_DNS_CHART" external-dns --set "domainFilters[0]=x.com" --set txtOwnerId=x
render cert-manager jetstack cert-manager "$CERT_MANAGER_CHART" cert-manager
render karpenter oci://public.ecr.aws/karpenter karpenter "$KARPENTER_CHART" kube-system --set settings.clusterName=x --set settings.interruptionQueue=x
render argo-cd argo argo-cd "$ARGOCD_CHART" argocd
render argo-rollouts argo argo-rollouts "$ARGO_ROLLOUTS_CHART" argo-rollouts
render kube-prometheus-stack prometheus-community kube-prometheus-stack "$KPS_CHART" monitoring
render tempo grafana-community tempo "$TEMPO_CHART" monitoring
render opentelemetry-collector open-telemetry opentelemetry-collector "$OTEL_COLLECTOR_CHART" monitoring
render keda kedacore keda "$KEDA_CHART" keda
render external-secrets external-secrets external-secrets "$EXTERNAL_SECRETS_CHART" external-secrets
render vpa fairwinds vpa "$VPA_CHART" vpa
render kyverno kyverno kyverno "$KYVERNO_CHART" kyverno
render velero vmware-tanzu velero "$VELERO_CHART" velero --set "configuration.backupStorageLocation[0].name=default" --set "configuration.backupStorageLocation[0].provider=aws" --set "configuration.backupStorageLocation[0].bucket=b" --set "configuration.backupStorageLocation[0].config.region=x"
render opencost opencost opencost "$OPENCOST_CHART" opencost
helm template pc k8s/platform/charts/platform-config --set karpenter.enabled=true --set externalSecrets.enabled=true >/dev/null && echo "  ok platform-config" || rc=1

if command -v kubeconform >/dev/null; then
  step "kubeconform (shop overlays; CRDs skipped)"
  for o in k8s/apps/shop/overlays/*; do
    kubectl kustomize "$o" | kubeconform -strict -ignore-missing-schemas -summary - || rc=1
  done
fi

echo; [[ $rc -eq 0 ]] && echo "${c_ok}lint passed${c_off}" || { echo "${c_bad}lint failed${c_off}"; exit 1; }
