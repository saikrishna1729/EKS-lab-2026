---
title: L400 Security
tags: [eks, lab, L400, security]
level: 400
sessions: 5
status: not-started
verified:
---

# L400 Security

← [[L300 Production Ops]] · [[00 EKS Lab Home]] · next → [[L500 Expert]] · full guide: [L400 README](../levels/L400-security/README.md)

> [!abstract] Goal
> A cluster that would pass a security review, covering identity, admission, network, supply chain, runtime, encryption and audit.

Start every session with:
```bash
make up LEVEL=400
```
The `security-baseline` Argo app syncs `k8s/L400/`.

Checklist source: [EKS Best Practices — Security](https://docs.aws.amazon.com/eks/latest/best-practices/security.html)

## Session 1 — Access
- [ ] Restrict the public endpoint to my IP: add `endpoint_public_access_cidrs` to `lab.tfvars`
- [ ] **dev** persona: edit rights in `shop`, forbidden in `kube-system`
- [ ] **viewer** persona: can list pods, can't read secrets
- [ ] Exercise: private endpoint only, regain access via SSM, then revert

## Session 2 — Admission
- [ ] `kubectl get clusterpolicy` and the policy reports
- [ ] `nginx:latest` in shop is blocked; in default it's only reported
- [ ] Mutation: the `team=shop` label is added
- [ ] Shop namespace raised to PSS `restricted` via Git. Does the shop still run?

## Session 3 — Network
- [ ] Default-deny plus allows (DNS, ALB, web→api, AWS APIs, monitoring)
- [ ] A probe from `default` → shop-api is blocked
- [ ] The label-spoof probe *succeeds*. Why, and what stops it?
- [ ] Remove the egress allow and watch `/api/s3check` fail

## Session 4 — Supply chain
- [ ] Generate a key pair with `cosign generate-key-pair`, then sign all 3 images
- [ ] Paste the public key into the verify policy, set it to Enforce, and push
- [ ] Pods now run by digest
- [ ] An unsigned image is denied
- [ ] Turn on cosign signing in CI
- [ ] ECR: immutable tags and enhanced (Inspector) scanning, then switch scanning back after the lab

## Session 5 — Runtime, encryption, audit
- [ ] GuardDuty EKS Protection and Runtime Monitoring on
- [ ] Run the attack sim, then look for the findings 5–15 min later
- [ ] Secrets encrypted with my KMS key (`describe-cluster`)
- [ ] kube-bench CIS results
- [ ] Logs Insights: who used `exec`?

## 🔧 Break it
- [ ] Kyverno webhook down blocks pod creation
- [ ] DNS policy removed
- [ ] Dev access entry removed
- [ ] Re-tagged image fails signature verification

## Finish
- [ ] Run the checks
  ```bash
  make verify LEVEL=400
  ```
  Result: `__/__`
- [ ] Tear down
  ```bash
  make down
  ```

## Quiz
1. Access policy vs RBAC group: when would you use each?
   -
2. Why allow 169.254.170.23 in a default-deny namespace?
   -
3. Scanning vs signature verification: which one stops a compromised CI?
   -
4. Customer-managed KMS vs the AWS-owned default key?
   -
5. Kyverno `failurePolicy: Fail` vs `Ignore`?
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
| | 5 | | | |
