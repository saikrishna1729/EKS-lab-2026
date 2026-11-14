---
title: L500 Expert
tags: [eks, lab, L500, dr, chaos, finops]
level: 500
sessions: 6
status: not-started
verified:
---

# L500 Expert

← [[L400 Security]] · [[00 EKS Lab Home]] · full guide: [L500 README](../levels/L500-expert/README.md) · [capstone](../levels/L500-expert/capstone/README.md)

> [!abstract] Goal
> Change the platform safely, recover from losing a region, prove resilience with experiments, and know what everything costs.

Start every session with:
```bash
make up LEVEL=500
```

> [!warning] Two-cluster days
> `make dr-up` doubles the cost while it's up. Always finish with `make dr-down`.

## Session 1 — Upgrades
- [ ] Check upgrade readiness
  ```bash
  aws eks list-insights --cluster-name eks-lab
  kubent
  ```
- [ ] In place: bump `versions.auto.tfvars`, then `make plan` and `make up`
- [ ] Order observed: control plane → add-ons → core nodes → Karpenter drift
- [ ] Blue/green: a green cluster one minor version higher, then shift Route 53 weights
- [ ] ADR: which upgrade strategy for which kind of change

## Session 2 — Backup & DR
- [ ] The Velero backup location shows Available
- [ ] Back up `storage-lab` and `shop`, then create a 6-hourly schedule
- [ ] Bring up DR and restore there
  ```bash
  make dr-up
  ```
  Install Velero read-only against the same bucket, then restore.
- [ ] Data from the primary region is visible in the DR region
- [ ] Measured RTO `____` and RPO `____`
- [ ] Tear down DR
  ```bash
  make dr-down
  ```

## Session 3 — Chaos (AWS FIS)
Write the hypothesis **before** each run.

| Experiment | Hypothesis | Result | Alert fired? |
|---|---|---|---|
| pod-delete 50% | | | |
| Spot interruption | | | |
| AZ power loss | | | |
| CoreDNS to 0 | | | |

## Session 4 — Multi-cluster & tenancy
- [ ] Register the DR cluster with Argo CD using the same labels; the whole platform deploys there
- [ ] Onboard the `payments` team: namespace, quota, LimitRange, default-deny, scoped access entry, tainted NodePool. Do it all as a Kustomize component, through Git.

## Session 5 — Mesh
- [ ] Install Istio ambient
  ```bash
  levels/L500-expert/istio/install-ambient.sh
  ```
  Then label the `shop` namespace for ambient mode.
- [ ] Strict mTLS plus an identity-based AuthorizationPolicy
- [ ] The label-spoof probe from L400 is now **denied**
- [ ] ADR: no mesh vs Istio ambient vs VPC Lattice

## Session 6 — FinOps & performance
- [ ] OpenCost per namespace and team
- [ ] `make cost LEVEL=500` estimate for running 24×7: `$____/month`
- [ ] Rightsize from the VPA recommendations, then watch Karpenter consolidate
- [ ] Compare Spot prices: Graviton vs x86
- [ ] Big-cluster tuning: NodeLocal DNSCache, CoreDNS autoscaling, API Priority & Fairness

## Capstone
- [ ] Per-AZ NAT, two regions, one Argo CD
- [ ] CI → signed image → Git → canary, with no manual `kubectl apply`
- [ ] SLOs and real alerting
- [ ] 6-hourly backups and a tested restore into DR
- [ ] At least 5 ADRs in `levels/L500-expert/capstone/ADR-0*.md`
- [ ] `architecture.md`
- [ ] `gameday.md`
- [ ] `make verify LEVEL=500` all green

## Quiz
1. Why is a control-plane upgrade irreversible, and how does blue/green help?
   -
2. Why don't EBS snapshots alone give you cross-region DR?
   -
3. The AZ experiment caused a full outage although pods spread fine. Two likely causes?
   -
4. Istio ambient vs sidecars?
   -
5. Which three numbers would you show finance?
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
| | 6 | | | |
