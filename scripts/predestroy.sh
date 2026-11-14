#!/usr/bin/env bash
# Delete everything Kubernetes created *in AWS* before `terraform destroy`:
# load balancers (Ingress / Service / Gateway), EBS volumes (PVCs), Karpenter EC2 instances,
# Route 53 records. Otherwise they are orphaned, keep billing, and block VPC deletion.
source "$(dirname "$0")/lib.sh"

if ! kubectl version --request-timeout=10s >/dev/null 2>&1; then
  log "Cluster not reachable — nothing to clean in-cluster (nuke-check will look for leftovers)"
  exit 0
fi

# 1. Stop GitOps from recreating what we delete
if kubectl get ns argocd >/dev/null 2>&1; then
  log "Pausing Argo CD reconciliation"
  kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 >/dev/null 2>&1 || true
  kubectl -n argocd scale deployment argocd-applicationset-controller --replicas=0 >/dev/null 2>&1 || true
fi

# 2. Load balancers (the AWS LB Controller / cloud provider must still be running)
log "Deleting Ingresses, Gateways and LoadBalancer Services"
kubectl delete ingress --all -A --wait=false >/dev/null 2>&1 || true
kubectl delete gateways.gateway.networking.k8s.io --all -A --wait=false >/dev/null 2>&1 || true
kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
  while read -r ns name; do kubectl -n "$ns" delete svc "$name" --wait=false >/dev/null; done

# 3. Persistent volumes (reclaimPolicy Delete => EBS volumes are removed by the CSI driver)
log "Deleting PVCs (and their EBS volumes)"
kubectl delete pvc --all -A --wait=false >/dev/null 2>&1 || true
kubectl delete volumesnapshots --all -A >/dev/null 2>&1 || true

# 4. Karpenter capacity
if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then
  log "Deleting Karpenter NodePools (terminates the EC2 instances it launched)"
  kubectl delete nodepools --all --wait=false >/dev/null 2>&1 || true
fi

log "Waiting for LBs, volumes and Karpenter nodes to be released (max 5 min)"
end=$((SECONDS+300))
while (( SECONDS < end )); do
  ing=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l)
  lbs=$(kubectl get svc -A -o json | jq '[.items[]|select(.spec.type=="LoadBalancer")]|length')
  pvs=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
  ncs=$(kubectl get nodeclaims --no-headers 2>/dev/null | wc -l || echo 0)
  (( ing + lbs + pvs + ncs == 0 )) && break
  echo "   ingress=$ing lb-services=$lbs pv=$pvs nodeclaims=$ncs"; sleep 10
done
log "In-cluster cleanup finished. ExternalDNS had a minute to delete DNS records."
sleep 30
