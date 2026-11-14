#!/usr/bin/env bash
# L100/L200: deploy the shop app with kubectl + kustomize (from L300 Argo CD does this).
#   scripts/deploy-shop.sh l100     # Service type LoadBalancer (Classic LB)
#   scripts/deploy-shop.sh l200     # ALB Ingress (+ HTTPS on shop.$DOMAIN when DOMAIN is set)
source "$(dirname "$0")/lib.sh"
OVERLAY="${1:-l100}"

tf_outputs
export ECR_REGISTRY=$(tfo ecr_registry)
export IMAGE_TAG="${IMAGE_TAG:-$(cat "$ROOT/.lab/image-tag" 2>/dev/null || true)}"
export DEMO_BUCKET=$(tfo demo_bucket) ORDERS_QUEUE_URL=$(tfo orders_queue_url) DOMAIN=$(tfo domain)
[[ -n "$IMAGE_TAG" ]] || die "No image tag. Run 'make images' first (or export IMAGE_TAG=...)"
[[ "$OVERLAY" == l200 && -n "$DOMAIN" ]] && OVERLAY=l200-tls

log "Deploying overlay $OVERLAY with images $ECR_REGISTRY/eks-lab/shop-*:$IMAGE_TAG"
kubectl kustomize "$ROOT/k8s/apps/shop/overlays/$OVERLAY" |
  envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${DEMO_BUCKET} ${ORDERS_QUEUE_URL} ${DOMAIN}' |
  kubectl apply -f -

kubectl -n shop rollout status deploy/shop-api --timeout=180s
kubectl -n shop rollout status deploy/shop-web --timeout=180s
