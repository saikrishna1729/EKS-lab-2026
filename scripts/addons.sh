#!/usr/bin/env bash
# Install in-cluster add-ons for a level (run by `make up`, or `make addons LEVEL=xxx`).
#   L100        nothing — you deploy by hand
#   L200        Helm: Gateway API CRDs, AWS LB Controller, ExternalDNS + cert-manager (if DOMAIN), platform-config
#   L300+       Helm: Argo CD only. Argo CD then installs EVERYTHING else from gitops/ (GitOps bridge pattern)
source "$(dirname "$0")/lib.sh"
LEVEL="${1:-100}"

tf_outputs
CLUSTER=$(tfo cluster_name); REGION=$(tfo region); VPC_ID=$(tfo vpc_id); DOMAIN=$(tfo domain)
ZONE_ID=$(tfo route53_zone_id); EFS_ID=$(tfo efs_id)

if (( LEVEL < 200 )); then
  log "L100: no add-ons to install. Follow levels/L100-foundations/README.md"
  exit 0
fi

install_l200() {
  helm_repos

  log "Gateway API CRDs $GATEWAY_API_VERSION (experimental channel: includes TCPRoute/TLSRoute for NLB)"
  kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml" >/dev/null

  log "AWS Load Balancer Controller $AWS_LBC_CHART"
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system --version "$AWS_LBC_CHART" \
    -f "$ROOT/k8s/platform/values/aws-load-balancer-controller.yaml" \
    --set clusterName="$CLUSTER" --set region="$REGION" --set vpcId="$VPC_ID" --wait

  if [[ -n "$DOMAIN" ]]; then
    log "ExternalDNS $EXTERNAL_DNS_CHART for $DOMAIN"
    helm upgrade --install external-dns external-dns/external-dns -n external-dns --create-namespace \
      --version "$EXTERNAL_DNS_CHART" -f "$ROOT/k8s/platform/values/external-dns.yaml" \
      --set "domainFilters[0]=$DOMAIN" --set txtOwnerId="$CLUSTER" --wait

    log "cert-manager $CERT_MANAGER_CHART"
    helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
      --version "$CERT_MANAGER_CHART" -f "$ROOT/k8s/platform/values/cert-manager.yaml" --wait
  else
    log "DOMAIN not set — skipping ExternalDNS / cert-manager (shop will be served on the ALB hostname over HTTP)"
  fi

  log "platform-config (gp3 default StorageClass, snapshot class, GatewayClasses${EFS_ID:+, EFS class})"
  helm upgrade --install platform-config "$ROOT/k8s/platform/charts/platform-config" -n kube-system \
    --set clusterName="$CLUSTER" --set region="$REGION" --set storage.efsId="$EFS_ID" \
    --set certManager.enabled="$([[ -n $DOMAIN ]] && echo true || echo false)" \
    --set certManager.domain="$DOMAIN" --set certManager.hostedZoneId="$ZONE_ID" \
    --set certManager.email="${ALERT_EMAIL:-}"

  # gp2 is the legacy default class created by EKS; demote it so gp3 is the only default
  kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=false --overwrite >/dev/null 2>&1 || true
}

install_gitops() {
  [[ -n "${GITHUB_REPO:-}" ]] || die "L300+ is GitOps-driven: set GITHUB_REPO in lab.env and push this repo to GitHub (see levels/L300-production-ops/README.md)"
  local repo_url="https://github.com/${GITHUB_REPO}.git" rev="${GITOPS_REVISION:-main}"
  helm_repos

  log "Argo CD $ARGOCD_CHART"
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version "$ARGOCD_CHART" \
    -f "$ROOT/k8s/platform/values/argo-cd.yaml" --wait

  log "Registering public.ecr.aws as an OCI Helm repo (Karpenter chart)"
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-public-ecr
  namespace: argocd
  labels: { argocd.argoproj.io/secret-type: repository }
stringData: { name: public-ecr, type: helm, url: public.ecr.aws, enableOCI: "true" }
EOF

  if [[ -n "${GITOPS_TOKEN:-}" ]]; then
    log "Registering private Git repo credentials"
    kubectl -n argocd create secret generic repo-gitops --from-literal=type=git \
      --from-literal=url="$repo_url" --from-literal=username=git --from-literal=password="$GITOPS_TOKEN" \
      --dry-run=client -o yaml | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | kubectl apply -f - >/dev/null
  fi

  # ---- GitOps bridge: Terraform facts -> Argo CD cluster secret (labels gate add-ons, annotations feed values)
  on() { [[ "$1" == true ]] && echo '"true"' || echo '"false"'; }
  local has_domain=false; [[ -n "$DOMAIN" ]] && has_domain=true
  local l400=false l500=false; (( LEVEL >= 400 )) && l400=true; (( LEVEL >= 500 )) && l500=true

  log "Writing the in-cluster Argo CD cluster secret (GitOps bridge)"
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: lab
    enable_lb_controller: "true"
    enable_platform_config: "true"
    enable_external_dns: $(on $has_domain)
    enable_cert_manager: $(on $has_domain)
    enable_karpenter: "true"
    enable_kube_prometheus_stack: "true"
    enable_tempo: "true"
    enable_otel_collector: "true"
    enable_keda: "true"
    enable_external_secrets: "true"
    enable_argo_rollouts: "true"
    enable_vpa: "true"
    enable_shop: "true"
    enable_kyverno: $(on $l400)
    enable_security_baseline: $(on $l400)
    enable_velero: $(on $l500)
    enable_opencost: $(on $l500)
  annotations:
    cluster_name: "$CLUSTER"
    aws_region: "$REGION"
    aws_account_id: "$(tfo account_id)"
    aws_vpc_id: "$VPC_ID"
    domain: "$DOMAIN"
    route53_zone_id: "$ZONE_ID"
    efs_id: "$EFS_ID"
    karpenter_queue: "$(tfo karpenter_queue_name)"
    velero_bucket: "$(tfo velero_bucket)"
    alert_email: "${ALERT_EMAIL:-}"
    gitops_repo: "$repo_url"
    gitops_revision: "$rev"
type: Opaque
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: '{"tlsClientConfig":{"insecure":false}}'
EOF

  log "Applying root app-of-apps -> gitops/platform and gitops/apps"
  export GITOPS_REPO="$repo_url" GITOPS_REVISION="$rev"
  envsubst '${GITOPS_REPO} ${GITOPS_REVISION}' < "$ROOT/gitops/bootstrap/root.yaml" | kubectl apply -f - >/dev/null

  log "Done. Watch it converge:  kubectl -n argocd get applications -w"
  log "UI: kubectl -n argocd port-forward svc/argocd-server 8080:80  (admin / \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d))"
}

if (( LEVEL >= 300 )); then install_gitops; else install_l200; fi
