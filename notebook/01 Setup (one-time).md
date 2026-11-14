---
title: Setup (one-time)
tags: [eks, lab, setup]
status: not-started
---

# 01 Setup (one-time)

Back to [[00 EKS Lab Home]]

## 1. Tools
- [ ] Install the extra CLIs
  ```bash
  make tools
  ```
- [ ] Check the versions
  ```bash
  aws --version; terraform version; kubectl version --client; helm version --short
  ```

## 2. Config
- [x] Create `lab.env`
  ```bash
  cp lab.env.example lab.env
  ```
- [x] Set `AWS_REGION`, `ALERT_EMAIL`, and `GITHUB_REPO=saikrishna1729/EKS-lab-2026`
- [ ] *(optional)* Set `DOMAIN`, a domain or subdomain you control, for the HTTPS/DNS labs

## 3. Bootstrap (admin identity, once)
> [!important]
> Run this as an **admin** identity. A limited CLI user can't create EKS or IAM resources.

- [ ] Run the bootstrap
  ```bash
  make bootstrap
  ```
- [ ] Confirm the AWS Budgets subscription email
- [x] Create the `EKSLabOperator` permission set in Identity Center (inline policy: only `sts:AssumeRole` on `eks-lab-admin`) and assign it in the lab account
- [x] Add the `eks-lab-operator` and `eks-lab` profiles to `~/.aws/config` (templates in `bootstrap/README.md`)
- [x] Test it
  ```bash
  aws sso login --profile eks-lab-operator
  AWS_PROFILE=eks-lab aws sts get-caller-identity   # -> assumed-role/eks-lab-admin/eks-lab
  ```

> [!note] Identity chain
> `eks-lab-operator` (SSO, can only assume the role) → **`eks-lab-admin`** (Terraform + cluster-admin).
> Always run `make up` as `eks-lab`, so the role is the cluster creator and keeps cluster-admin.
> `EKSLab-Admin` (AdministratorAccess) is break-glass only: it runs `make bootstrap` and can fix the trust policy.
- [ ] *(if DOMAIN)* Delegate NS records to the name servers printed by
  ```bash
  terraform -chdir=bootstrap output route53_name_servers
  ```

## 4. Images
- [ ] Build and push the sample app images (multi-arch)
  ```bash
  make images
  ```
- [ ] Note the tag here: `____________` (also saved in `.lab/image-tag`)

## 5. Sanity check
- [ ] Run the static checks
  ```bash
  make lint
  ```
- [ ] Check which Kubernetes versions EKS offers in your region
  ```bash
  aws eks describe-cluster-versions --query 'clusterVersions[].[clusterVersion,status]' --output table
  ```
  The lab is pinned to 1.35 in `terraform/envs/lab/versions.auto.tfvars`. Adjust it if needed.

## My notes
-
