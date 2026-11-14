# L500 — Expert: upgrades, DR, chaos, multi-cluster, mesh, FinOps

**Goal:** design and operate EKS at an architect level. That means changing the platform safely,
recovering from regional loss, proving resilience with experiments, and knowing what everything costs.
**Time:** 6 sessions + capstone · **Cost:** ≈ $6–10 per session; ≈ $12–18 on the two-cluster days

```bash
make up LEVEL=500      # adds Velero (Pod Identity, S3 from bootstrap), OpenCost, zonal shift
```

---

## Session 1 — Upgrades: in-place, then blue/green

**Concepts**
- Order: **control plane → managed add-ons → nodes**, one minor version at a time. Nodes can lag the control plane by up to 3 minors, but don't let them.
- Before you start: check for removed APIs (`kubent`, `pluto`, **EKS Upgrade Insights**), PDBs
  that block drains, add-on and chart compatibility, and Karpenter's supported Kubernetes range.
- In place is simple, but you can't roll the control plane back. **Blue/green clusters** cost
  double for a while, but give you instant rollback by moving DNS weights back.

**Lab A — in place**
```bash
aws eks list-insights --cluster-name eks-lab --filter kubernetesVersions=$(terraform -chdir=terraform/envs/lab output -raw cluster_version)
aws eks describe-insight --cluster-name eks-lab --id <id>      # deprecated API usage etc.
kubent                                                          # client-side check
# bump kubernetes_version in terraform/envs/lab/versions.auto.tfvars (e.g. 1.35 -> 1.36)
make plan LEVEL=500       # control plane + add-on versions (most_recent) + node group AMI
make up LEVEL=500         # ~10 min control plane, then add-ons, then the core node group rolls
kubectl get nodes -o wide # core nodes on the new version
# Karpenter nodes: they drift automatically (amiSelector alias @latest) and get replaced, honouring PDBs
kubectl get nodeclaims -o wide -w
```
**Lab B — blue/green** (two clusters ≈ 2× cost for the session):
```bash
make dr-up                # "green" cluster; set its kubernetes_version one minor higher in terraform/envs/dr/main.tf
# register green with Argo CD (same labels => all add-ons + shop deploy automatically)
argocd cluster add eks-lab-dr --name green --label enable_lb_controller=true --label enable_shop=true ...
# Route 53 weighted records: shop.$DOMAIN -> blue ALB (100) / green ALB (0), then 90/10, 50/50, 0/100
```
Write an ADR: which upgrade strategy for which kind of change (minor version, CNI swap, VPC redesign)?

## Session 2 — Backup & cross-region DR with Velero

**Concepts**
- Velero backs up API objects to S3, and volume data through CSI snapshots. With
  `snapshotMoveData`, the snapshot data is copied into S3 as well. That makes it restorable in
  **another region**, where plain EBS snapshots wouldn't be.
- GitOps already rebuilds *stateless* things. Backups exist for **state** (PVCs) and for whatever
  isn't in Git.
- RTO = how long until it works again. RPO = how much data you can lose. Measure both; don't guess.

**Lab**
```bash
kubectl -n velero get backupstoragelocation      # Available
kubectl apply -f levels/L200-aws-integration/storage.yaml   # stateful workload with data
velero backup create pre-dr --include-namespaces storage-lab,shop --wait
velero backup describe pre-dr --details
velero schedule create every-6h --schedule="0 */6 * * *" --ttl 72h0m0s
# DR region
make dr-up
kubectl config use-context eks-lab-dr
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero -n velero --create-namespace --version $(grep VELERO_CHART scripts/versions.env | cut -d= -f2 | cut -d' ' -f1) \
  -f k8s/platform/values/velero.yaml \
  --set "configuration.backupStorageLocation[0].name=default" --set "configuration.backupStorageLocation[0].provider=aws" \
  --set "configuration.backupStorageLocation[0].bucket=$(terraform -chdir=terraform/envs/lab output -raw velero_bucket)" \
  --set "configuration.backupStorageLocation[0].prefix=eks-lab" \
  --set "configuration.backupStorageLocation[0].config.region=$AWS_REGION" \
  --set "configuration.backupStorageLocation[0].accessMode=ReadOnly" --wait
velero backup get                      # the primary's backups are visible from the DR cluster
velero restore create --from-backup pre-dr --wait
kubectl -n storage-lab exec ebs-writer-0 -- tail -3 /data/log     # data from the primary region
make dr-down
```
Record: backup duration, restore duration, the age of the newest data restored (that's your RPO).

## Session 3 — Chaos engineering with AWS FIS
Set up the role and RBAC in [fis/README.md](fis/README.md) and [fis/fis-rbac.yaml](fis/fis-rbac.yaml). Run them in this order, with Grafana and the SLO alerts open:

| Experiment | Hypothesis to write *before* running |
|---|---|
| [pod-delete.json](fis/pod-delete.json) | 50 % of api pods die → no 5xx thanks to readiness + PDB + preStop |
| [spot-interruption.json](fis/spot-interruption.json) | Karpenter cordons and drains within 2 min and replaces capacity, so no user impact |
| [az-power-loss.json](fis/az-power-loss.json) | one AZ is gone for 10 min → ? (with a single NAT, egress may die: find out) |
| CoreDNS loss: `kubectl -n kube-system scale deploy coredns --replicas=0` for 2 min | cached connections survive, new lookups fail → which alerts fire? |

After each one: was the hypothesis right? Which alert fired, and how quickly? What will you change?

## Session 4 — Multi-cluster & multi-tenancy
- **One Argo CD, many clusters**: every ApplicationSet uses the `clusters` generator, so registering
  the DR cluster with labels deploys the whole platform to it. Try it with `make dr-up` and `argocd cluster add`.
- Per-environment differences go in the cluster-secret annotations (GitOps bridge), not in forked YAML.
- **Tenancy models**:

| Model | Isolation | Cost | When |
|---|---|---|---|
| Namespace per team (+ quotas, NetworkPolicy, Kyverno, RBAC) | soft | low | trusted internal teams |
| Node pools per tenant (Karpenter NodePool + taints) | medium | medium | noisy neighbours, compliance |
| Cluster per tenant / environment | hard | high | untrusted tenants, blast radius |

Lab: onboard a second team `payments` by creating a namespace, ResourceQuota, LimitRange,
default-deny policy, a dev access entry scoped to `payments`, and a dedicated tainted NodePool.
Do all of it through Git as a reusable Kustomize component.

## Session 5 — Service mesh: Istio ambient vs Amazon VPC Lattice
```bash
levels/L500-expert/istio/install-ambient.sh
kubectl label ns shop istio.io/dataplane-mode=ambient
kubectl apply -f levels/L500-expert/istio/shop-mesh.yaml
kubectl -n shop run probe --rm -it --labels=app.kubernetes.io/name=shop-web --image=public.ecr.aws/docker/library/busybox:1.37 -- wget -qO- -T3 http://shop-api:8080/api/whoami
# ✘ denied now: the label trick from L400 no longer works, because identity = ServiceAccount (SPIFFE), not labels
```
- Ambient puts **ztunnel** on each node for L4 mTLS, plus optional **waypoints** for L7. There are
  no sidecars, so there's nothing to restart for upgrades.
- **VPC Lattice** (AWS Gateway API controller, `LATTICE_CONTROLLER_CHART` in `scripts/versions.env`)
  is AWS-managed service-to-service networking across VPCs, accounts and compute types, using
  IAM auth policies. There's nothing in the data path to run.

Write an ADR comparing *no mesh + NetworkPolicy*, *Istio ambient* and *VPC Lattice* for: mTLS,
L7 authz, cross-cluster, ops burden, cost and observability.

## Session 6 — FinOps & performance
```bash
kubectl -n opencost port-forward svc/opencost 9090:9090 &   # UI: cost by namespace / controller / label (team=…)
make cost LEVEL=500                                          # infracost: what this would cost 24×7
```
- Rightsizing: compare VPA recommendations with the current requests. Lower `shop-*` requests via Git and watch Karpenter consolidate.
- Spot + Graviton: compare prices with `aws ec2 describe-spot-price-history --instance-types m7g.large m7i.large`. What's in your NodePool and why?
- Big-cluster tuning: NodeLocal DNSCache, CoreDNS autoscaling (`coredns` add-on `autoScaling` config),
  API Priority & Fairness (`kubectl get flowschemas`), and `WARM_IP_TARGET` vs prefix delegation.
- Optional: a GPU NodePool (`g6` instances, the NVIDIA device plugin, taints). Watch the cost: on-demand GPUs cost dollars per hour.

## Capstone
See [capstone/README.md](capstone/README.md). Build it from an empty account, write the ADRs, and run the game day.

## ✅ Verify
```bash
make verify LEVEL=500
```

## Quiz
1. Why is a control-plane upgrade irreversible, and how does blue/green work around that?
2. Why do EBS snapshots alone not give you cross-region DR, and what does `snapshotMoveData` change?
3. Your AZ-failure experiment caused a full outage although pods spread fine. Name two likely causes.
4. Istio ambient vs sidecars: what changes for upgrades, resource cost and L7 features?
5. Which three numbers would you show a finance partner to justify the platform's monthly cost?
