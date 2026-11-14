---
title: Troubleshooting
tags: [eks, lab, runbook, troubleshooting]
---

# 90 Troubleshooting

[[00 EKS Lab Home]] · [[02 Daily Loop]]

> [!tip] First three commands, always
> ```bash
> kubectl get events -A --sort-by=.lastTimestamp | tail -20
> kubectl describe <kind> <name> -n <ns>      # read the Events section
> kubectl logs <pod> -n <ns> --previous        # logs from the crashed container
> ```

## Pods
| Symptom | Likely cause | Fix / where to look |
|---|---|---|
| `Pending` – Insufficient cpu/memory | requests too big, or no capacity | lower the requests; L300+: Karpenter logs, NodePool `limits` |
| `Pending` – Too many pods | ENI/IP limit | prefix delegation (L200), new nodes |
| `ImagePullBackOff` | wrong tag, ECR auth, or no NAT/endpoint | `describe pod`; check `.lab/image-tag`; VPC endpoints |
| `CrashLoopBackOff` | the app exits | `logs --previous` |
| `OOMKilled` | memory limit too low | raise the limit; check VPA |
| Pod admission denied | Kyverno / PSS (L400) | the error message names the policy; `kubectl get policyreport -n <ns>` |
| `failed calling webhook` | a webhook (Kyverno, LBC, cert-manager) is down | check that controller's pods |

## AWS integration
| Symptom | Likely cause | Fix |
|---|---|---|
| Ingress has no ADDRESS | LB controller down, or bad subnet tags | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| ALB 502/503 | targets unhealthy | target group health in the console; health check path |
| `NoCredentialProviders` / AccessDenied in a pod | missing Pod Identity association, or wrong SA name | `aws eks list-pod-identity-associations --cluster-name eks-lab` |
| PVC Pending | wrong StorageClass, or EBS CSI missing | `describe pvc`; the `aws-ebs-csi-driver` add-on |
| `FailedAttachVolume` | volume and pod in different AZs | topology spread; delete the pod so it lands in the right AZ |
| DNS record not created | ExternalDNS filter or IAM | `kubectl -n external-dns logs deploy/external-dns` |

## GitOps (L300+)
| Symptom | Likely cause | Fix |
|---|---|---|
| App `Unknown` / `ComparisonError` | CRD not installed yet | wait for the retry; check the add-on providing the CRD |
| App OutOfSync forever | a field is mutated at runtime | `ignoreDifferences` |
| ApplicationSet creates nothing | cluster secret label missing | `kubectl -n argocd get secret in-cluster -o yaml` |
| Repo not accessible | private repo with no token | make it public, or export `GITOPS_TOKEN` |

## Terraform / teardown
| Symptom | Likely cause | Fix |
|---|---|---|
| `DependencyViolation` deleting the VPC/subnet | orphaned LB or ENI | `make nuke-check`, then delete what it lists; re-run `make down` |
| State lock error | an interrupted apply | wait, or `terraform -chdir=terraform/envs/lab force-unlock <id>` |
| `Unauthorized` from kubectl | expired credentials or wrong profile | `export AWS_PROFILE=eks-lab`, then `make kubeconfig` |
| Add-on `DEGRADED` | conflicting config | `aws eks describe-addon --cluster-name eks-lab --addon-name <x>` |

## My own incidents
| Date | Symptom | Root cause | Fix | Lesson |
|---|---|---|---|---|
| | | | | |
