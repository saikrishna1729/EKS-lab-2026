---
title: L200 AWS Integration
tags: [eks, lab, L200, networking, iam, storage]
level: 200
sessions: 4
status: not-started
verified:
---

# L200 AWS Integration

← [[L100 Foundations]] · [[00 EKS Lab Home]] · next → [[L300 Production Ops]] · full guide: [L200 README](../levels/L200-aws-integration/README.md)

> [!abstract] Goal
> A cluster wired into AWS networking, identity, load balancing, DNS, TLS and storage, with **no static credentials**.

Start every session with:
```bash
make up LEVEL=200
scripts/deploy-shop.sh l200
```

## Session 1 — VPC & VPC CNI
- [ ] Explain the subnet layout: /19 private, small public, intra
- [ ] Single NAT vs per-AZ NAT (cost vs resilience)
- [ ] VPC endpoints: S3 gateway (free) plus ECR/STS interface endpoints
- [ ] Max pods formula: `ENIs × (IPs per ENI − 1) + 2`. A t4g.large gives 35.
- [ ] Lab: disable prefix delegation, run the 120-pod `ipburn`, see Pending, re-enable, roll nodes, see 110
- [ ] Inspect node ENIs in EC2

> [!note] maxPods only changes on **new** nodes, because it's set when the kubelet bootstraps.

## Session 2 — Identity (Pod Identity vs IRSA)
- [ ] Fill in the table from memory:

| | Pod Identity | IRSA |
|---|---|---|
| Trust | | |
| Mapping | | |
| Multi-cluster reuse | | |

- [ ] Find the `AWS_CONTAINER_CREDENTIALS_FULL_URI` env var injected into shop-api
- [ ] `curl $ALB/api/s3check` returns an `assumed-role/eks-lab-shop-api` identity
- [ ] A debug pod in `default` **cannot** list S3 (no association)
- [ ] IMDS is blocked from pods (hop limit 1)

## Session 3 — Load balancing, Gateway API, DNS, TLS
- [ ] ALB Ingress with `target-type: ip` and `group.name`
- [ ] Look at the target groups in the console: type `ip`
- [ ] Gateway API
  ```bash
  kubectl apply -f levels/L200-aws-integration/gateway-api.yaml
  ```
  The Gateway gets its own ALB.
- [ ] NLB Service
  ```bash
  kubectl apply -f levels/L200-aws-integration/nlb-service.yaml
  ```
- [ ] *(DOMAIN)* `https://shop.<domain>` works, using the ACM cert plus the ExternalDNS record
- [ ] *(DOMAIN)* cert-manager DNS-01 certificate (`certificate.yaml`)

## Session 4 — Storage & ECR
- [ ] EBS StatefulSet: each volume is in the same AZ as its pod
- [ ] VolumeSnapshot, then restore it into a new PVC
- [ ] EFS: 3 pods on different nodes share one volume
- [ ] ECR: scan-on-push, lifecycle policy, multi-arch manifest, pull-through cache
- [ ] *(optional)* Bottlerocket node group vs AL2023

## 🔧 Break it
- [ ] Ingress never gets an address (LB controller scaled to 0)
- [ ] ALB 502/503 (bad health check path)
- [ ] Pod can't read S3 (association removed)
- [ ] PVC Pending (wrong StorageClass)
- [ ] Volume can't attach (AZ cordoned)

## Finish
- [ ] Run the checks
  ```bash
  make verify LEVEL=200
  ```
  Result: `__/__`
- [ ] Tear down
  ```bash
  make down
  ```

## Quiz
1. Pods out of IPs but the subnet has free space. Why? Two fixes?
   -
2. Why does `target-type: ip` matter for zero-downtime deploys?
   -
3. Pod Identity credential flow, step by step?
   -
4. Why spread a StatefulSet with EBS by zone? What breaks if a zone dies?
   -
5. What does the S3 gateway endpoint save, and why does ECR need it?
   -

## My notes
-

## Session log
| Date | Session | Duration | Cost | Notes |
|---|---|---|---|---|
| | 1 | | | |
| | 2 | | | |
| | 3 | | | |
| | 4 | | | |
