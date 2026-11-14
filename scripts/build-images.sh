#!/usr/bin/env bash
# Build multi-arch (arm64 + amd64) images for shop-{web,api,worker} and push to ECR.
# Tag = git short SHA (immutable-friendly), or a timestamp before the first commit.
source "$(dirname "$0")/lib.sh"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M)}"

log "Logging in to $REGISTRY"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

docker buildx inspect eks-lab >/dev/null 2>&1 || docker buildx create --name eks-lab --use >/dev/null
docker buildx use eks-lab

for svc in web api worker; do
  log "Building shop-$svc:$TAG (linux/arm64,linux/amd64)"
  docker buildx build --platform linux/arm64,linux/amd64 \
    --build-arg SERVICE="$svc" \
    --provenance=false \
    -t "$REGISTRY/eks-lab/shop-$svc:$TAG" \
    --push "$ROOT/apps/shop"
done

mkdir -p "$ROOT/.lab" && echo "$TAG" > "$ROOT/.lab/image-tag"
log "Pushed tag $TAG (saved to .lab/image-tag). Scan results:"
for svc in web api worker; do
  aws ecr wait image-scan-complete --region "$AWS_REGION" --repository-name "eks-lab/shop-$svc" --image-id imageTag="$TAG" 2>/dev/null || true
  aws ecr describe-image-scan-findings --region "$AWS_REGION" --repository-name "eks-lab/shop-$svc" --image-id imageTag="$TAG" \
    --query 'imageScanFindings.findingSeverityCounts' --output json 2>/dev/null | tr -d '\n ' ; echo "  <- shop-$svc"
done
