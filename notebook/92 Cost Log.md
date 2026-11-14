---
title: Cost Log
tags: [eks, lab, cost]
budget_usd: 50
---

# 92 Cost Log

[[00 EKS Lab Home]] · Budget: **$50/month** (alerts at 50 / 80 / 100 %)

> [!tip] Where to find the numbers
> Billing → Cost Explorer → filter **Tag: Project = eks-lab**, grouped by **Service**, daily.
> (First activate `Project` as a cost allocation tag: Billing → Cost allocation tags.)

| Date | Level | Session | Hours up | Cost ($) | Biggest line item | nuke-check clean? |
|---|---|---|---|---|---|---|
| | | | | | | ⬜ |

## Expected per hour (ap-southeast-1, approx.)
| Item | $/h |
|---|---|
| EKS control plane | 0.10 |
| NAT gateway (single) | 0.059 + data |
| 2× Graviton Spot nodes | ~0.05 |
| ALB | ~0.025 + LCU |
| Interface endpoints (3 × 3 AZ) | ~0.11 |
| AMP managed scraper (optional) | ~0.04 + samples |

## Monthly running total
- Month: ______  Total: $______
