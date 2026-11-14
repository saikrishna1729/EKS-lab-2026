#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
tf_outputs
C=$(tfo cluster_name); DOMAIN=$(tfo domain)
echo "L200 checks for $C"

ADDONS="vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver metrics-server"
[[ -n "$(tfo efs_id)" ]] && ADDONS="$ADDONS aws-efs-csi-driver"
check "managed add-ons ACTIVE ($ADDONS)" bash -c \
  "for a in $ADDONS; do [ \$(aws eks describe-addon --cluster-name $C --addon-name \$a --query addon.status --output text) = ACTIVE ] || exit 1; done"
check "prefix delegation on (node allocatable pods ≥ 100)" bash -c "kubectl get nodes -o jsonpath='{.items[*].status.allocatable.pods}' | tr ' ' '\n' | awk '\$1<100{bad=1} END{exit bad}'"
check "VPC endpoints exist (s3 gateway + interface)" bash -c "[ \$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$(tfo vpc_id) --query 'length(VpcEndpoints)') -ge 4 ]"
check "AWS Load Balancer Controller ready" kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=10s
check "gp3 is the default StorageClass"   bash -c "kubectl get sc gp3 -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q true"
check "Gateway API CRDs installed"        kubectl get crd httproutes.gateway.networking.k8s.io
check "Pod Identity associations exist for shop-api and LB controller" bash -c \
  "aws eks list-pod-identity-associations --cluster-name $C --query 'associations[].serviceAccount' --output text | grep -q shop-api && aws eks list-pod-identity-associations --cluster-name $C --query 'associations[].serviceAccount' --output text | grep -q aws-load-balancer-controller"

ALB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
check "shop Ingress has an ALB"           test -n "$ALB"
check "shop reachable through the ALB"    eventually bash -c "curl -sf --max-time 5 http://$ALB/ | grep -q 'EKS Lab Shop'"
check "pod reads S3 with Pod Identity (no keys)" eventually bash -c "curl -sf --max-time 10 http://$ALB/api/s3check | grep -q hello.txt"
check "orders go to SQS"                  bash -c "curl -sf -XPOST -H 'content-type: application/json' -d '{\"item_id\":\"1\"}' http://$ALB/api/orders | grep -q queued"
check "no AWS access keys in the shop namespace" bash -c "! kubectl -n shop get deploy -o yaml | grep -q AWS_SECRET_ACCESS_KEY"
check "pods cannot reach node IMDS credentials (hop limit 1)" bash -c \
  "! kubectl -n shop exec \$(kubectl -n shop get pod -l app.kubernetes.io/name=shop-api -o name | head -1) -- python -c \"import urllib.request as u; u.urlopen(u.Request('http://169.254.169.254/latest/api/token', method='PUT', headers={'X-aws-ec2-metadata-token-ttl-seconds':'60'}), timeout=2)\""
if [[ -n "$DOMAIN" ]]; then
  check "HTTPS on shop.$DOMAIN (ACM + ExternalDNS)" eventually bash -c "curl -sf --max-time 5 https://shop.$DOMAIN/ | grep -q 'EKS Lab Shop'"
  check "HTTP redirects to HTTPS"         bash -c "curl -s -o /dev/null -w '%{http_code}' http://shop.$DOMAIN/ | grep -q 301"
else
  echo "  (DOMAIN not set — TLS/DNS checks skipped)"
fi
summary
