#!/usr/bin/env bash
# L300, once: render your account-specific values into the GitOps shop overlay, then commit.
# Names are deterministic (no VPC IDs etc.), so this survives the daily destroy/rebuild.
source "$(dirname "$0")/lib.sh"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
TAG="${IMAGE_TAG:-$(cat "$ROOT/.lab/image-tag" 2>/dev/null || true)}"
[[ -n "$TAG" ]] || die "Run 'make images' first"
BUCKET="$CLUSTER_NAME-demo-$ACCOUNT-$AWS_REGION"
QUEUE="https://sqs.$AWS_REGION.amazonaws.com/$ACCOUNT/$CLUSTER_NAME-orders"
D="$ROOT/k8s/apps/shop/overlays/gitops"

sed -i.bak \
  -e "s#ECR_REGISTRY#$REGISTRY#g" -e "s#IMAGE_TAG#$TAG#g" \
  -e "s#DEMO_BUCKET#$BUCKET#g" -e "s#ORDERS_QUEUE_URL#$QUEUE#g" \
  -e "s#AWS_REGION#$AWS_REGION#g" -e "s#CLUSTER_NAME#$CLUSTER_NAME#g" \
  "$D"/*.yaml && rm -f "$D"/*.bak

if [[ -n "${DOMAIN:-}" ]] && ! grep -q "shop.$DOMAIN" "$D/kustomization.yaml"; then
  log "Adding HTTPS + host shop.$DOMAIN to the gitops overlay"
  export TLS_PATCH="- { op: add, path: /metadata/annotations/alb.ingress.kubernetes.io~1listen-ports, value: '[{\"HTTP\": 80}, {\"HTTPS\": 443}]' }
- { op: add, path: /metadata/annotations/alb.ingress.kubernetes.io~1ssl-redirect, value: \"443\" }
- { op: add, path: /metadata/annotations/external-dns.alpha.kubernetes.io~1hostname, value: shop.$DOMAIN }
- { op: add, path: /spec/rules/0/host, value: shop.$DOMAIN }"
  yq -i '.patches += [{"target": {"kind": "Ingress", "name": "shop"}, "patch": strenv(TLS_PATCH)}]' "$D/kustomization.yaml"
fi

kubectl kustomize "$D" >/dev/null && log "Rendered $D — review with 'git diff', then commit and push."
