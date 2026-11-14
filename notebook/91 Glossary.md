---
title: Glossary
tags: [eks, lab, reference]
---

# 91 Glossary

[[00 EKS Lab Home]]

| Term | Meaning | Level |
|---|---|---|
| **Access entry** | Maps an IAM principal to Kubernetes access (replaces `aws-auth`) | [[L100 Foundations]] |
| **Access policy** | EKS-managed permission set (Admin/Edit/View) scoped to the cluster or to namespaces | [[L400 Security]] |
| **Auto Mode** | EKS runs the nodes, Karpenter and the core add-ons for you | [[L100 Foundations]] |
| **VPC CNI** | Gives pods real VPC IPs via node ENIs | [[L200 AWS Integration]] |
| **Prefix delegation** | Assign /28 prefixes per ENI slot, so ~110 pods per node | [[L200 AWS Integration]] |
| **Pod Identity** | IAM role per (cluster, namespace, ServiceAccount) via an agent; no OIDC trust policy | [[L200 AWS Integration]] |
| **IRSA** | The older OIDC-based way to give a ServiceAccount an IAM role | [[L200 AWS Integration]] |
| **AWS LB Controller** | Ingress/Service/Gateway → ALB/NLB | [[L200 AWS Integration]] |
| **Gateway API** | Successor to Ingress: GatewayClass / Gateway / HTTPRoute | [[L200 AWS Integration]] |
| **Karpenter** | Provisions right-sized EC2 for pending pods, and consolidates | [[L300 Production Ops]] |
| **NodePool / EC2NodeClass** | Karpenter's what-to-launch and how-to-launch objects | [[L300 Production Ops]] |
| **KEDA** | Event-driven autoscaling (e.g. SQS depth) | [[L300 Production Ops]] |
| **GitOps bridge** | Terraform facts → Argo CD cluster secret → ApplicationSets | [[L300 Production Ops]] |
| **Argo Rollouts** | Canary/blue-green with metric analysis | [[L300 Production Ops]] |
| **SLI / SLO / error budget** | What you measure / the target / allowed failure (1 − SLO) | [[L300 Production Ops]] |
| **Burn rate** | Error ratio ÷ error budget. 14.4× over 1h means page someone. | [[L300 Production Ops]] |
| **AMP** | Amazon Managed Service for Prometheus | [[L300 Production Ops]] |
| **PSS / PSA** | Pod Security Standards and the built-in admission that enforces them | [[L400 Security]] |
| **Kyverno** | Policy engine: validate, mutate, generate, verifyImages | [[L400 Security]] |
| **cosign** | Signs and verifies container images | [[L400 Security]] |
| **GuardDuty Runtime Monitoring** | Threat detection agent on the nodes | [[L400 Security]] |
| **Upgrade Insights** | EKS checks for deprecated APIs before an upgrade | [[L500 Expert]] |
| **Velero** | Kubernetes backup/restore (objects + volume data) | [[L500 Expert]] |
| **RTO / RPO** | Time to recover / data you can lose | [[L500 Expert]] |
| **AWS FIS** | Fault Injection Service (chaos experiments) | [[L500 Expert]] |
| **ARC zonal shift** | Move traffic away from an impaired AZ | [[L500 Expert]] |
| **Istio ambient** | Sidecar-less mesh: ztunnel (L4) + waypoint (L7) | [[L500 Expert]] |
| **VPC Lattice** | AWS-managed service-to-service networking | [[L500 Expert]] |
| **ADR** | Architecture Decision Record | [[L500 Expert]] |
