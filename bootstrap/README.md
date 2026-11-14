# Bootstrap (run once)

Creates the long-lived pieces the daily lab depends on. Costs ≈ $1/month (more only if you
host a Route 53 zone: +$0.50/month).

| Resource | Why |
|---|---|
| S3 bucket `eks-lab-tfstate-<acct>-<region>` | Remote Terraform state, versioned, with S3-native locking (`use_lockfile`) — no DynamoDB table needed (Terraform ≥ 1.10) |
| AWS Budget `eks-lab-monthly` | Email at 50 / 80 / 100 % actual and 100 % forecast |
| Cost Anomaly monitor (optional) | Daily email for anomalies ≥ $5 |
| IAM role `eks-lab-admin` | The identity you use for all sessions (MFA required by default) |
| ECR repos `eks-lab/shop-*` | Sample app images; scan-on-push + lifecycle rules |
| ECR pull-through cache `ecr-public/` | Cache public images in your account (L200) |
| Route 53 zone (optional) | DNS + TLS labs in L200 |
| S3 bucket `eks-lab-velero-…` | Backups for L500 |
| GitHub OIDC role (optional) | Keyless CI in L300 |

## Steps

1. Use an **admin** identity for this step only (an admin IAM user or an IAM Identity
   Center admin session). A narrowly-scoped user that can't call EKS/IAM APIs will fail here.
2. Fill `lab.env` (at least `AWS_REGION`, `ALERT_EMAIL`; `DOMAIN` and `GITHUB_REPO` are optional).
3. From the repo root:
   ```bash
   make bootstrap
   ```
4. Confirm the **budget subscription email** AWS sends you.
5. Add a profile that assumes the lab role to `~/.aws/config`:
   ```ini
   [profile eks-lab]
   role_arn       = arn:aws:iam::<ACCOUNT_ID>:role/eks-lab-admin
   source_profile = default          # the profile holding your admin/user credentials
   mfa_serial     = arn:aws:iam::<ACCOUNT_ID>:mfa/<your-mfa-device>
   region         = ap-southeast-1
   duration_seconds = 43200
   ```
   Test it:
   ```bash
   AWS_PROFILE=eks-lab aws sts get-caller-identity
   ```
6. If you set `DOMAIN`, delegate it: create NS records for the domain at your registrar (or
   in the parent zone) pointing at `terraform -chdir=bootstrap output route53_name_servers`.

State for this folder is **local** (`bootstrap/terraform.tfstate`, gitignored). Back it up, or
migrate it into the bucket afterwards with a `backend "s3"` block + `terraform init -migrate-state`.

## Removing everything at the end of the course
```bash
make down                                   # if a cluster is up
env -u AWS_PROFILE terraform -chdir=bootstrap destroy
```
(The state bucket has `force_destroy = false`; empty it first in the console.)
