# EKS Lab 2026 — L100 → L500

A hands-on path from your first EKS cluster to a production-grade, observable, hardened,
multi-region platform — built in **your own AWS account** with **Terraform**, and torn
down at the end of every session to keep the bill small.

| Level | Theme | Sessions | You will be able to… |
|---|---|---|---|
| [L100](levels/L100-foundations/README.md) | Foundations | 2 | explain EKS architecture, create a cluster (eksctl, then Terraform), deploy and expose an app |
| [L200](levels/L200-aws-integration/README.md) | Core AWS integration | 4 | design the VPC, tune the VPC CNI, use Pod Identity, ALB/NLB/Gateway API, TLS, DNS, EBS/EFS, ECR |
| [L300](levels/L300-production-ops/README.md) | Production operations | 6 | run Karpenter/HPA/KEDA, GitOps with Argo CD + Rollouts, CI with OIDC, full metrics/logs/traces + SLO alerts |
| [L400](levels/L400-security/README.md) | Security & hardening | 5 | lock down access, enforce policy (Kyverno/PSS), NetworkPolicies, signed images, GuardDuty, KMS, audit |
| [L500](levels/L500-expert/README.md) | Expert / architect | 6 | blue-green upgrades, cross-region DR with Velero, chaos with FIS, multi-cluster GitOps, mesh, FinOps, capstone |

Each level folder contains a `README.md` (the lab guide), a `lab.tfvars` (which Terraform
features that level turns on) and a `verify.sh` (automated checks that you finished it).

---

## How the repo is organised

```
bootstrap/            One-time, long-lived: TF state bucket, budget + anomaly alerts, ECR repos,
                      optional Route 53 zone, GitHub OIDC role, Velero bucket. (~$1/month)
terraform/modules/    vpc, eks, platform-iam (Pod Identity roles), karpenter, observability
terraform/envs/lab/   The cluster you create/destroy every session; features toggled per level
terraform/envs/dr/    Second-region cluster for L500 DR / blue-green
apps/shop/            Sample app: web → api → SQS → worker, OpenTelemetry + Prometheus metrics
k8s/                  Plain manifests + Helm values, grouped by level
gitops/               Argo CD app-of-apps (from L300)
scripts/              addons.sh, predestroy.sh, nuke-check.sh, helpers
levels/LXXX-*/        Lab guide, tfvars and verify.sh for each level
notebook/             Obsidian lab notebook: checklists, session logs, troubleshooting, cost log
```

**Design rule used throughout:** Terraform owns *AWS* resources (VPC, EKS, IAM, SQS, AMP…).
Things *inside* the cluster are installed by Helm (L200, via `scripts/addons.sh`) and later
by Argo CD (L300+). That's how most platform teams split it, and it avoids the
"Kubernetes provider in the same apply as the cluster" trap.

---

## Prerequisites

1. An AWS account where you can create IAM roles (an admin user/role for the one-time bootstrap).
2. Tools (you already have aws, terraform, kubectl, eksctl, helm, kubectx, docker):
   ```bash
   make tools
   ```
   installs `k9s stern argocd kubeconform infracost cosign hey kubent velero eks-node-viewer kubectl-argo-rollouts` with Homebrew. `tflint` is optional and no longer in Homebrew: `make tflint` installs it from its GitHub release (checksum-verified).
3. Copy the config file and edit it:
   ```bash
   cp lab.env.example lab.env
   ```

> ⚠️ Your current CLI identity may not have EKS permissions. Run the bootstrap once with an
> admin identity — it creates an `eks-lab-admin` role you then use for every session
> (`export AWS_PROFILE=eks-lab` — see [bootstrap/README.md](bootstrap/README.md)).

---

## The daily loop

```bash
make up LEVEL=200        # terraform apply + kubeconfig + in-cluster add-ons for that level (~15 min)
# ... follow levels/L200-aws-integration/README.md ...
make verify LEVEL=200    # automated checks
make down                # deletes LBs/PVCs/Karpenter nodes, terraform destroy, then nuke-check
```

`make down` is not optional. A forgotten cluster costs ~$5/day; a forgotten NAT gateway or
orphaned load balancer keeps billing after the cluster is gone — `scripts/nuke-check.sh`
looks for exactly those.

## Cost guardrails

| Item | Approx. cost (ap-southeast-1) | Mitigation |
|---|---|---|
| EKS control plane | $0.10/h | destroy daily |
| 2× Graviton Spot nodes (t4g/m7g large) | ~$0.05/h total | Spot + ARM |
| NAT gateway | $0.059/h + data | single NAT; VPC endpoints from L200 |
| ALB/NLB | ~$0.025/h each | `predestroy.sh` removes them |
| Bootstrap (S3, ECR, R53 zone) | ~$1/month | persistent on purpose |

Typical session: **$3–8**. The bootstrap creates an AWS Budget (default $50/month) with
email alerts at 50/80/100 % and a Cost Anomaly Detection monitor.

## Versions

All versions live in one place: [`terraform/envs/lab/versions.auto.tfvars`](terraform/envs/lab/versions.auto.tfvars)
and [`scripts/versions.env`](scripts/versions.env). The lab starts one Kubernetes minor
version behind latest on purpose — you upgrade it in L500.

Check what EKS currently supports:
```bash
aws eks describe-cluster-versions --query 'clusterVersions[].[clusterVersion,status]' --output table
```

## References
- EKS Best Practices Guide: https://docs.aws.amazon.com/eks/latest/best-practices/
- EKS User Guide: https://docs.aws.amazon.com/eks/latest/userguide/
- terraform-aws-modules/eks: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws
