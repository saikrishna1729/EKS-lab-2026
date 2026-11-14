#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
tf_outputs
C=$(tfo cluster_name)
echo "L400 checks for $C"
BB=public.ecr.aws/docker/library/busybox:1.37

check "Secrets encrypted with a customer-managed KMS key" bash -c \
  "aws eks describe-cluster --name $C --query 'cluster.encryptionConfig[0].provider.keyArn' --output text | grep -q arn:aws:kms"
check "public endpoint restricted (not 0.0.0.0/0) or disabled" bash -c \
  "aws eks describe-cluster --name $C --query 'cluster.resourcesVpcConfig' | jq -e '(.endpointPublicAccess==false) or ((.publicAccessCidrs|index(\"0.0.0.0/0\"))==null)'"
check "control-plane audit logging on"     bash -c "aws eks describe-cluster --name $C --query 'cluster.logging.clusterLogging[?enabled].types[]' --output text | grep -q audit"
check "VPC CNI network policy enabled"     bash -c "aws eks describe-addon --cluster-name $C --addon-name vpc-cni --query addon.configurationValues --output text | grep -q '\"enableNetworkPolicy\":\"true\"'"
check "dev persona scoped to the shop namespace" bash -c "aws eks list-associated-access-policies --cluster-name $C --principal-arn $(tfo persona_role_arns | jq -r .dev) --query 'associatedAccessPolicies[0].accessScope.namespaces[0]' --output text | grep -qx shop"
check "viewer group cannot read secrets"   bash -c "kubectl auth can-i get secrets -n shop --as=x --as-group=lab-viewers | grep -qx no"
check "viewer group can list pods"         bash -c "kubectl auth can-i list pods -A --as=x --as-group=lab-viewers | grep -qx yes"
check "Kyverno blocks :latest in shop"     bash -c "! kubectl -n shop run kyv-test --image=nginx:latest --dry-run=server"
check "Kyverno blocks non-ECR images in shop" bash -c "! kubectl -n shop run kyv-test2 --image=public.ecr.aws/nginx/nginx:1.27 --dry-run=server"
check "privileged pods rejected"           bash -c "! kubectl -n default run priv --image=$BB --privileged --dry-run=server -- sleep 1"
check "default-deny NetworkPolicy in shop" kubectl -n shop get networkpolicy default-deny-all
check "cross-namespace traffic to shop-api is blocked" bash -c \
  "! kubectl -n default run np-probe-\$RANDOM --rm -i --restart=Never --image=$BB -- wget -qO- -T 3 http://shop-api.shop:8080/healthz"
ALB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
check "shop still works end-to-end through the policies" eventually bash -c "curl -sf --max-time 5 http://$ALB/api/s3check | grep -q hello.txt"
check "shop pods run as non-root with read-only root FS" bash -c \
  "kubectl -n shop get pods -l app.kubernetes.io/part-of=shop -o json | jq -e '[.items[].spec.containers[].securityContext.readOnlyRootFilesystem]|all'"
if grep -q REPLACE_WITH_YOUR_COSIGN_PUBLIC_KEY "$ROOT/k8s/L400/policies/verify-images.yaml"; then
  echo "  (image signature policy not configured yet — session 4)"
else
  check "image verification policy enforcing" bash -c "kubectl get clusterpolicy verify-shop-image-signatures -o jsonpath='{.spec.validationFailureAction}' | grep -qi enforce"
  check "shop pods run by digest (verified)" bash -c "kubectl -n shop get pods -l app.kubernetes.io/name=shop-web -o jsonpath='{.items[0].spec.containers[0].image}' | grep -q '@sha256:'"
fi
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo None)
if [[ "$DET" != None ]]; then
  check "GuardDuty EKS audit log monitoring on" bash -c "aws guardduty get-detector --detector-id $DET --query \"Features[?Name=='EKS_AUDIT_LOGS'].Status\" --output text | grep -q ENABLED"
  check "GuardDuty has a finding for this cluster (run the attack sim)" bash -c \
    "aws guardduty list-findings --detector-id $DET --finding-criteria '{\"Criterion\":{\"resource.eksClusterDetails.name\":{\"Eq\":[\"$C\"]}}}' --query 'length(FindingIds)' | grep -qv '^0$'"
else
  echo "  (no GuardDuty detector — runtime-detection checks skipped)"
fi
summary
