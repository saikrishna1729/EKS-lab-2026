# Capstone: a production-like platform from an empty account

Rebuild **everything** from scratch, using your own notes. Copy only from your own repo.

## Requirements
1. Two regions: primary (lab) and DR (`make dr-up`), both GitOps-managed by **one** Argo CD (add the DR cluster as a second cluster secret with the same labels).
2. Multi-AZ everywhere: **per-AZ NAT** (`single_nat_gateway = false`), PDBs, topology spread, Karpenter across 3 AZs.
3. The shop deploys only through CI → signed image → Git tag bump → Argo CD → canary. No manual `kubectl apply`.
4. SLO: 99.5 % availability and p99 < 300 ms for `/api/*`, with burn-rate alerts delivered to a real channel.
5. Backups every 6 h with Velero, plus a **tested** restore into the DR region. Write down your RTO and RPO.
6. Security: private or IP-restricted endpoint, no wildcard admin, Kyverno enforcing in app namespaces, default-deny NetworkPolicies, GuardDuty on, KMS for secrets.
7. Cost: an OpenCost report per namespace, and a monthly estimate (`make cost`) for running it 24×7.

## Deliverables (commit them in `levels/L500-expert/capstone/`)
- `architecture.md`: a diagram plus a component list (use the archify skill, draw.io, or ASCII).
- At least 5 ADRs from `ADR-template.md`. Suggested topics: Karpenter vs managed node groups only ·
  Pod Identity vs IRSA · ALB Ingress vs Gateway API · Prometheus in-cluster vs AMP · Istio ambient vs VPC Lattice vs no mesh.
- `gameday.md`: the run sheet and results of an AZ failure plus a bad deploy, run together.
- `make verify LEVEL=500` all green.

## Game day script (90 min)
1. Baseline: `hey -z 30m -q 20 https://shop.$DOMAIN/api/items` from your laptop, with Grafana open.
2. T+5: push a release with `ERROR_RATE: "0.15"`. Expect: the canary aborts automatically.
3. T+15: start `fis/az-power-loss.json`. Expect: pods reschedule into the other AZs, ALB health checks drain the dead AZ, and the SLO dashboard shows a short dip.
   (With a **single** NAT in the failed AZ, *all* egress dies. That is your evidence for the per-AZ NAT ADR.)
4. T+30: shift traffic away from the impaired AZ with **ARC zonal shift** (`aws arc-zonal-shift start-zonal-shift --resource-identifier <cluster-arn> --away-from <az-id> --expires-in 1h --comment gameday`).
5. T+45: declare the region lost. Restore the latest Velero backup into the DR cluster and flip Route 53 weights.
6. Write `gameday.md`: timeline, what alerted, what didn't, actions.
