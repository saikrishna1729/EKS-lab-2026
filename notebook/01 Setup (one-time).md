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
- [ ] Add the `eks-lab` profile to `~/.aws/config` (template in `bootstrap/README.md`)
- [ ] Test it
  ```bash
  AWS_PROFILE=eks-lab aws sts get-caller-identity
  ```
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
