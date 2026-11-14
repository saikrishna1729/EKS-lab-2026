---
title: Daily Loop
tags: [eks, lab, runbook]
---

# 02 Daily Loop

Back to [[00 EKS Lab Home]]

> [!tip] Copy this checklist into the session log at the bottom of the level note you're working on.

## Start (≈ 15–20 min)
- [ ] Sign in (operator SSO) and start with fresh credentials
  ```bash
  aws sso login --profile eks-lab-operator
  export AWS_PROFILE=eks-lab
  aws sts get-caller-identity
  ```
- [ ] Check there are no leftovers from last time
  ```bash
  make nuke-check
  ```
- [ ] Bring the cluster up
  ```bash
  make up LEVEL=___
  ```
- [ ] Check the nodes
  ```bash
  kubectl get nodes -L topology.kubernetes.io/zone
  ```
- [ ] **L100–L200 only:** deploy the shop by hand
  ```bash
  scripts/deploy-shop.sh l100   # or l200
  ```
- [ ] **L300+ only:** wait for Argo CD
  ```bash
  kubectl -n argocd get applications   # all Synced/Healthy
  ```
- [ ] Get the ALB address
  ```bash
  export ALB=$(kubectl -n shop get ingress shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  ```

## During
- Work through the session in the level note. Write findings under **My notes**.
- Useful terminals to keep open:
  - `k9s`
  - `stern -n shop shop-`
  - `kubectl get events -A -w`

## Stop (≈ 10 min)
- [ ] Check progress
  ```bash
  make verify LEVEL=___
  ```
- [ ] Tear everything down
  ```bash
  make down
  ```
- [ ] Confirm `nuke-check` printed **✔ nothing billable left behind**
- [ ] Write the session's cost in [[92 Cost Log]] (Billing console, next day)

> [!danger] If `make down` fails halfway
> 1. Re-run `make down`. It's idempotent.
> 2. If the VPC won't delete, an orphaned load balancer or network interface is blocking it. `make nuke-check` prints the delete commands.
> 3. Check the EC2 console for leftover load balancers, available volumes, and NAT gateways.

## Handy port-forwards
| What | Command | Login |
|---|---|---|
| Argo CD | `kubectl -n argocd port-forward svc/argocd-server 8080:80` | admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| Grafana | `kubectl -n monitoring port-forward svc/kps-grafana 3000:80` | admin / eks-lab-admin |
| Prometheus | `kubectl -n monitoring port-forward svc/kps-prometheus 9090` | – |
| Alertmanager | `kubectl -n monitoring port-forward svc/kps-alertmanager 9093` | – |
| OpenCost (L500) | `kubectl -n opencost port-forward svc/opencost 9090:9090` | – |
