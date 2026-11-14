#!/usr/bin/env bash
source "$(dirname "$0")/../../scripts/lib.sh"
tf_outputs
C=$(tfo cluster_name)
echo "L300 checks for $C"

check "Argo CD running"                    kubectl -n argocd rollout status deploy/argocd-server --timeout=10s
check "all Argo CD applications Synced + Healthy" bash -c \
  "kubectl -n argocd get applications -o json | jq -e '[.items[] | select(.status.sync.status!=\"Synced\" or .status.health.status!=\"Healthy\")] | length==0'"
check "Karpenter NodePool ready"           bash -c "kubectl get nodepool default -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
check "Karpenter interruption queue configured" bash -c "kubectl -n kube-system get deploy karpenter -o yaml | grep -q '$(tfo karpenter_queue_name)'"

# Scale-up test: a pod that only fits on a new node
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: karpenter-probe, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: karpenter-probe } }
  template:
    metadata: { labels: { app: karpenter-probe } }
    spec:
      nodeSelector: { karpenter.sh/nodepool: default }
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.10
          resources: { requests: { cpu: "1", memory: 1Gi } }
EOF
EVENTUALLY_TIMEOUT=300 check "Karpenter launches a node for a pending pod" eventually bash -c \
  "kubectl get pod -l app=karpenter-probe -o jsonpath='{.items[0].status.phase}' | grep -q Running"
kubectl delete deploy karpenter-probe -n default --wait=false >/dev/null

check "HPA for shop-web reports metrics"   bash -c "kubectl -n shop get hpa shop-web -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' | grep -q '[0-9]'"
check "KEDA ScaledObject Ready"            bash -c "kubectl -n shop get scaledobject shop-worker -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
check "Rollout shop-api Healthy"           bash -c "kubectl -n shop get rollout shop-api -o jsonpath='{.status.phase}' | grep -q Healthy"
check "ExternalSecret synced"              bash -c "kubectl -n shop get externalsecret shop-secrets -o jsonpath='{.status.conditions[0].status}' | grep -q True"
check "Prometheus scrapes shop pods"       bash -c \
  "kubectl -n monitoring exec sts/prometheus-kps-prometheus -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=up{namespace=\"shop\"}' | jq -e '.data.result|length>0'"
check "SLO recording rule evaluates"       bash -c \
  "kubectl -n monitoring exec sts/prometheus-kps-prometheus -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/rules' | grep -q ShopApiErrorBudgetFastBurn"
check "Alertmanager running + Watchdog firing (alert pipeline works)" bash -c \
  "kubectl -n monitoring exec sts/alertmanager-kps-alertmanager -c alertmanager -- wget -qO- http://localhost:9093/api/v2/alerts | grep -q Watchdog"

ALB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
for i in $(seq 1 20); do curl -s "http://$ALB/" >/dev/null || true; done
EVENTUALLY_TIMEOUT=90 check "traces from shop-web are in Tempo" eventually bash -c \
  "kubectl -n monitoring run tq-\$RANDOM --rm -i --restart=Never --image=public.ecr.aws/docker/library/busybox:1.37 -- wget -qO- 'http://tempo:3200/api/search?tags=service.name%3Dshop-web&limit=1' 2>/dev/null | grep -q traceID"
check "Container Insights add-on ACTIVE"   test "$(aws eks describe-addon --cluster-name "$C" --addon-name amazon-cloudwatch-observability --query addon.status --output text)" = ACTIVE
check "application logs in CloudWatch"     bash -c "aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/$C/application --query 'length(logGroups)' | grep -q 1"
check "AMP workspace exists"               test -n "$(tfo amp_endpoint)"
summary
