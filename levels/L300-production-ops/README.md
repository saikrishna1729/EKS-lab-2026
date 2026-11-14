# L300 — Production operations

**Goal:** run the cluster the way a platform team does. Everything is declared in Git, capacity
follows demand, deploys are progressive, and you can see metrics, logs and traces with alerts
tied to SLOs.
**Time:** 6 sessions · **Cost:** ≈ $5–9 per session (Container Insights and AMP are usage-based; still cents)

## One-time setup for L300+
1. Push this repo to GitHub. A **public** repo is easiest: it contains no secrets. For a private
   repo, export `GITOPS_TOKEN=<fine-grained PAT, read-only contents>` before `make up`.
2. In `lab.env` set `GITHUB_REPO=<you>/EKS-lab-2026`, then re-run `make bootstrap` to create the
   GitHub OIDC role `eks-lab-github-ci`.
3. Render your account-specific values into the GitOps overlay, then commit:
   ```bash
   make images
   scripts/gitops-init.sh
   git add -A && git commit -m "gitops: render lab values" && git push
   ```
4. In the GitHub repo → Settings → Variables, add `AWS_REGION` and `AWS_ACCOUNT_ID`.

Then every session:
```bash
make up LEVEL=300       # Terraform → Argo CD → Argo CD installs ~15 add-ons + the shop (~20 min)
kubectl -n argocd get applications      # wait for all Synced/Healthy
export ALB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

## How L300 is wired (read this first)
```
Terraform ──outputs──► scripts/addons.sh ──► Secret argocd/in-cluster
   (IAM, SQS, Karpenter queue,                labels:  enable_karpenter=true, enable_keda=true …
    Pod Identity associations)                annotations: cluster_name, vpc_id, karpenter_queue …
                                                    │
                       Argo CD root app ──► gitops/platform/*.yaml (ApplicationSets)
                                              └─► one Application per add-on, values from Git + annotations
                                           gitops/apps/shop.yaml ──► k8s/apps/shop/overlays/gitops
```
This is the **GitOps bridge** pattern. Terraform knows the AWS facts and Git knows the desired
state; the cluster secret connects the two. Nothing is `kubectl apply`'d by hand.

---

## Session 1 — Autoscaling: HPA, Karpenter, KEDA, VPA

**Concepts**
- **HPA** scales pods on metrics (metrics-server). It needs CPU *requests* to compute utilization.
- **Karpenter** watches *unschedulable pods* and launches the cheapest EC2 instance that fits
  them (NodePool requirements: arch, Spot/On-Demand, families). It then **consolidates**: it
  removes or replaces under-used nodes. Spot interruptions arrive through SQS + EventBridge, and
  Karpenter drains the node before it is reclaimed.
- The core managed node group runs Karpenter itself and the critical controllers. Karpenter never manages the nodes it runs on.
- **KEDA** scales on external events (SQS depth here), down to zero if you allow it.
- **VPA** in recommend-only mode tells you what requests *should* be.

**Lab**
```bash
kubectl get nodepool,ec2nodeclass
eks-node-viewer 2>/dev/null || watch -n2 'kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type,kubernetes.io/arch'
# 1. HPA + Karpenter: CPU load on the api
kubectl apply -f k8s/tools/load-test.yaml
kubectl -n shop get hpa -w                   # replicas climb
kubectl get nodeclaims -w                    # Karpenter launches nodes for the Pending pods
kubectl -n kube-system logs deploy/karpenter -f | grep -E 'launched|disrupt|consolidat'
# After the job ends (5 min), watch consolidation remove the nodes.

# 2. KEDA: flood the queue
for i in $(seq 1 300); do curl -s -XPOST -H 'content-type: application/json' -d '{"item_id":"1"}' http://$ALB/api/orders >/dev/null & done; wait
kubectl -n shop get scaledobject,hpa keda-hpa-shop-worker
aws sqs get-queue-attributes --queue-url $(terraform -chdir=terraform/envs/lab output -raw orders_queue_url) --attribute-names ApproximateNumberOfMessages

# 3. VPA recommendation
kubectl apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: shop-web, namespace: shop }
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: shop-web }
  updatePolicy: { updateMode: "Off" }
EOF
kubectl -n shop describe vpa shop-web | sed -n '/Recommendation/,$p'
```
Exercise: create a second NodePool `on-demand-critical` with `capacity-type: on-demand` and a
taint, then make `shop-api` tolerate it and select it. Why might you want this?

## Session 2 — GitOps with Argo CD + progressive delivery

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
argocd login localhost:8080 --username admin --insecure \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
argocd app list
```
Drills:
1. **Drift**: `kubectl -n shop scale deploy shop-web --replicas=7`. Argo CD's self-heal reverts it. Watch it happen in the UI.
2. **Change through Git**: edit `k8s/apps/shop/base/shop.yaml` (e.g. `PROCESS_MS: "500"`), push, and watch the sync.
3. **Add-on upgrade**: bump `targetRevision` of a small add-on (e.g. `vpa.yaml`) and push. Rolling it back is `git revert`.
4. **Canary with Argo Rollouts**:
   ```bash
   kubectl argo rollouts get rollout shop-api -n shop --watch    # brew install argoproj/tap/kubectl-argo-rollouts
   ```
   Change `APP_VERSION` to `v2` in `overlays/gitops/cluster-values.yaml` and push. The ALB weights move
   10 → 30 → 60 → 100 while the `success-rate` analysis queries Prometheus.
   Now make a **bad release**: add `ERROR_RATE: "0.3"` to the same ConfigMap patch, push, and
   generate traffic (`hey -z 3m http://$ALB/api/items`). The analysis fails, the rollout **aborts
   and shifts traffic back**, and `ShopApiErrorBudgetFastBurn` may fire.

## Session 3 — CI with GitHub Actions (OIDC, no keys)
Read [.github/workflows/shop.yaml](../../.github/workflows/shop.yaml). Then:
```bash
# change something visible in apps/shop/web/main.py, then:
git commit -am "web: new banner" && git push
gh run watch                        # build → Trivy scan → push → tag bump commit
argocd app get shop-in-cluster      # new image tag syncs → rollout starts
```
Questions: Which IAM trust condition limits *which* workflow can assume the role? What happens if
Trivy finds a CRITICAL vulnerability?

## Session 4 — Observability: metrics, logs, traces

| Signal | Collected by | Stored in | Look at it |
|---|---|---|---|
| Metrics | Prometheus (kube-prometheus-stack), PodMonitor for the shop | in-cluster Prometheus (2d) → **AMP** in part B | Grafana |
| Logs | CloudWatch Observability add-on (Fluent Bit) | CloudWatch Logs `/aws/containerinsights/eks-lab/application` | Logs Insights |
| Traces | OpenTelemetry auto-instrumentation → OTel Collector | Tempo | Grafana → Explore → Tempo |
| Control plane | EKS control-plane logging (api, audit, authenticator) | CloudWatch `/aws/eks/eks-lab/cluster` | Logs Insights |
| Container Insights | CloudWatch agent | CloudWatch metrics | Console → Container Insights |

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80 &     # admin / eks-lab-admin
kubectl -n monitoring port-forward svc/kps-prometheus 9090 &
```
Part A, in-cluster:
- Grafana → Dashboards → *Kubernetes / Compute Resources / Namespace (Pods)*, select `shop`.
- Prometheus: `sum by (route,status) (rate(http_requests_total{service="shop-api"}[1m]))`.
- Explore → Tempo → *Search* `service.name=shop-web`. Open a trace and follow web → api → SQS (botocore span).
- Explore → Tempo → **Service graph** (built by Tempo's metrics-generator).
- CloudWatch Logs Insights on the application log group:
  ```
  fields @timestamp, kubernetes.pod_name, log
  | filter kubernetes.namespace_name = "shop" and log like /order/
  | sort @timestamp desc | limit 50
  ```
- Who deleted that pod? Run audit logs on `/aws/eks/eks-lab/cluster`:
  ```
  fields @timestamp, user.username, verb, objectRef.resource, objectRef.name
  | filter verb = "delete" and objectRef.resource = "pods" | sort @timestamp desc
  ```

Part B, Amazon Managed Prometheus (agentless):
```bash
# set enable_amp_managed_scraper = true in levels/L300-production-ops/lab.tfvars, then
make up LEVEL=300
kubectl apply -f levels/L300-production-ops/amp-scraper-rbac.yaml
terraform -chdir=terraform/envs/lab output amp_endpoint
```
In Grafana, add a *Prometheus* datasource: URL = `amp_endpoint`, **SigV4 auth** on, default
credentials, region = yours. Grafana's Pod Identity role (`eks-lab-grafana-amp`) allows queries.
Run the same PromQL against AMP. What do you gain? (HA, 150-day retention, nothing to operate.)
What does it cost? (per sample ingested; check the AMP bill after a session.)

## Session 5 — SLOs and alerting
Read [overlays/gitops/observability.yaml](../../k8s/apps/shop/overlays/gitops/observability.yaml):
- SLI = the ratio of non-5xx requests. SLO = 99.5 % over 30 days, which leaves an error budget of 0.5 %.
- **Burn rate** = observed error ratio / budget. A 14.4× burn over 1h pages someone, because at that rate a month's budget is gone in about 2 days.

```bash
kubectl -n monitoring port-forward svc/kps-alertmanager 9093 &
# GitOps way: add  ERROR_RATE: "0.2"  to overlays/gitops/cluster-values.yaml, push
# (the canary from session 2 would abort it — so for this drill promote it straight through:)
kubectl argo rollouts promote shop-api -n shop --full
hey -z 10m -q 20 http://$ALB/api/items        # sustained traffic
# Prometheus → Alerts: ShopApiErrorBudgetFastBurn goes pending → firing; check http://localhost:9093
```
Exercise: wire a real receiver. Create a Slack incoming webhook, store the URL in Secrets Manager
at `eks-lab/eks-lab/alertmanager-slack`, add an ExternalSecret into `monitoring`, and set
`alertmanager.alertmanagerSpec.secrets` + `slack_configs` in the values. Do it all through Git.

## Session 6 — Config, secrets and workload resilience
- **External Secrets**: `kubectl -n shop get externalsecret,secret shop-secrets`. Change the value in Secrets
  Manager and watch it sync within `refreshInterval`. `kubectl -n shop exec deploy/shop-api -- env | grep API_TOKEN` (pods only pick up the change on restart: why?).
- **Resilience drills**:
  ```bash
  kubectl -n shop get pdb
  NODE=$(kubectl -n shop get pod -l app.kubernetes.io/name=shop-web -o jsonpath='{.items[0].spec.nodeName}')
  kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data   # respects the PDB
  kubectl -n shop get pod -o wide -l app.kubernetes.io/name=shop-web   # spread across zones?
  kubectl uncordon $NODE
  ```
- Try exceeding the ResourceQuota (`kubectl -n shop scale deploy shop-web --replicas=80`). What stops it, and where do you see the error?
- `services.loadbalancers: "0"` in the quota: why would a platform team do that?

## 🔧 Break it
| Scenario | Cause | Clue |
|---|---|---|
| Pods Pending, no new nodes | set NodePool `limits.cpu: 2` in platform-config values and push | `kubectl describe nodepool` / Karpenter logs: limit exceeded |
| Argo app stuck OutOfSync | `kubectl -n shop edit cm shop-config` with selfHeal disabled in the UI | Diff view |
| No traces | scale `otel-collector` to 0 | app logs: OTLP export errors; empty Tempo |
| KEDA doesn't scale | remove the KEDA pod identity association | `kubectl -n keda logs deploy/keda-operator`: AccessDenied |
| Spot interruption | `aws ec2 send-spot-interruption` via AWS FIS on a Karpenter node | node cordoned and drained ahead of reclaim |

## ✅ Verify
```bash
make verify LEVEL=300
```

## Teardown
`make down` pauses Argo CD, deletes LBs, PVCs and NodePools, then destroys everything.

## Quiz
1. Why should Karpenter not run on nodes it provisions?
2. HPA and KEDA both create an HPA object. How do you avoid two controllers fighting over one Deployment?
3. What does `consolidationPolicy: WhenEmptyOrUnderutilized` do to a node running one small pod? How do PDBs interact with it?
4. Give the multi-window burn-rate rule for paging, and explain why there are two windows.
5. Logs in CloudWatch, metrics in Prometheus, traces in Tempo: how do you jump from a slow trace to the matching logs?
