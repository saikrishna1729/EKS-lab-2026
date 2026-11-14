#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
tf_outputs
C=$(tfo cluster_name)
echo "L100 checks for $C"

check "cluster is ACTIVE"                 test "$(aws eks describe-cluster --name "$C" --query cluster.status --output text)" = ACTIVE
check "authentication mode is API (access entries)" test "$(aws eks describe-cluster --name "$C" --query cluster.accessConfig.authenticationMode --output text)" = API
check "kubectl can reach the API"         kubectl get --raw /readyz
check "≥ 2 Ready nodes"                   bash -c "[ \$(kubectl get nodes --no-headers | grep -c ' Ready') -ge 2 ]"
check "nodes span ≥ 2 AZs"                bash -c "[ \$(kubectl get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print \$NF}' | sort -u | wc -l) -ge 2 ]"
check "core add-ons are ACTIVE"           bash -c "for a in vpc-cni coredns kube-proxy eks-pod-identity-agent; do [ \$(aws eks describe-addon --cluster-name $C --addon-name \$a --query addon.status --output text) = ACTIVE ] || exit 1; done"
for app in shop-web shop-api shop-worker; do
  check "$app has a Ready pod"            bash -c "kubectl -n shop get pods -l app.kubernetes.io/name=$app -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
done
# L100 exposes shop-web with a LoadBalancer Service; from L200 on it's behind the ALB Ingress
LB=$(kubectl -n shop get svc shop-web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
[[ -z "$LB" ]] && LB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
check "shop is exposed through a load balancer" test -n "$LB"
check "shop answers through the LB (web → api)" eventually bash -c "curl -sf --max-time 5 http://$LB/ | grep -q 'EKS Lab Shop'"
check "api reachable from web (no error banner)" bash -c "! curl -sf --max-time 5 http://$LB/ | grep -q 'class=err'"
summary
