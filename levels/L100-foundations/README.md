# L100 — Foundations

**Goal:** understand what EKS actually is, create a cluster two ways, and run and expose a real
app on it.
**Time:** 2 sessions · **Cost:** ≈ $3–5 per session

## Objectives
By the end of this level you can:
- explain which parts AWS runs and which you run, and pick between managed node groups, Fargate and EKS Auto Mode
- create a cluster with eksctl and with Terraform, and say why teams prefer Terraform
- authenticate with `aws eks update-kubeconfig` and explain **access entries**
- deploy, scale, expose, debug and roll back a three-tier app

---

## Concepts (read before session 1)

```
                     ┌──────────── AWS-managed account ────────────┐
                     │  EKS control plane (HA across 3 AZs)         │
  kubectl ──HTTPS──► │  kube-apiserver · etcd · scheduler · ctrl-mgr│
                     └───────────────┬──────────────────────────────┘
                                     │ cross-account ENIs in YOUR subnets
   ┌──────────────────────── your VPC ┴──────────────────────────────┐
   │  private subnets (3 AZs)                                         │
   │   ┌─ node ──────────┐ ┌─ node ──────────┐   pods get VPC IPs     │
   │   │ kubelet, vpc-cni│ │ kubelet, vpc-cni│   (VPC CNI)            │
   │   │ kube-proxy, pods│ │ kube-proxy, pods│                        │
   │   └─────────────────┘ └─────────────────┘                        │
   │  public subnets: NAT gateway, load balancers                     │
   └──────────────────────────────────────────────────────────────────┘
```

| Concept | What to know |
|---|---|
| **Control plane** | AWS runs, scales and patches it: $0.10/h per cluster. You can't SSH to it or scrape etcd/scheduler metrics. |
| **Data plane options** | **Managed node groups** (EC2 in an ASG, AWS handles AMI and draining) · **Karpenter** (L300) · **Fargate** (one micro-VM per pod; no DaemonSets) · **EKS Auto Mode** (AWS also runs Karpenter, the core add-ons and node OS patching for you). |
| **VPC CNI** | Every pod gets a real VPC IP. That makes the network fast and simple, but it uses up subnet IPs (more in L200). |
| **Managed add-ons** | vpc-cni, CoreDNS, kube-proxy, and the Pod Identity agent are versioned and upgraded through the EKS API. |
| **Authentication** | IAM identity → **access entry** → Kubernetes permissions (access policies or RBAC groups). The old `aws-auth` ConfigMap is deprecated. |
| **Versions** | About 14 months of standard support, then extended support (+$0.50/h). The lab sets `upgrade_policy = STANDARD`. |

Reading: [EKS Best Practices — Cluster Upgrades & Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/), [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)

## Prerequisites
- `make bootstrap` done ([bootstrap/README.md](../../bootstrap/README.md)) and `AWS_PROFILE=eks-lab` works
- `make tools` done
- Images pushed: `make images` (do this once now; ~5 min)

---

## Session 1 — the eksctl way (≈ 60 min)

1. Create a throwaway cluster:
   ```bash
   eksctl create cluster -f levels/L100-foundations/eksctl-cluster.yaml
   ```
   While it builds (about 15 minutes), open **CloudFormation** in the console. eksctl is a
   CloudFormation generator: look at the two stacks (cluster, nodegroup) and what they contain.
2. Explore:
   ```bash
   kubectl get nodes -o wide            # private IPs, Spot instances, Graviton (arm64)
   kubectl get pods -A                  # what runs in an "empty" cluster?
   kubectl get ds -n kube-system        # aws-node (VPC CNI), kube-proxy, pod identity agent
   aws eks list-access-entries --cluster-name eks-lab-first
   aws eks describe-cluster --name eks-lab-first --query 'cluster.{v:version,ep:endpoint,auth:accessConfig}'
   k9s                                  # press : then type pods, deploy, svc, events
   ```
3. Who am I to Kubernetes?
   ```bash
   kubectl auth whoami
   kubectl auth can-i '*' '*' --all-namespaces
   ```
   You're cluster-admin because eksctl created an access entry for the identity that made the
   cluster. Find it with `aws eks list-associated-access-policies`.
4. *(Optional, ~15 min, ≈ $0.50)* **EKS Auto Mode** comparison:
   ```bash
   eksctl create cluster --name eks-lab-auto --region $AWS_REGION --enable-auto-mode
   kubectl --context <auto-ctx> get nodes     # none! Nodes appear only when pods need them
   kubectl --context <auto-ctx> create deploy nginx --image=public.ecr.aws/nginx/nginx:1.27 --replicas=3
   kubectl --context <auto-ctx> get nodes -w  # AWS-managed Karpenter launches a node
   eksctl delete cluster --name eks-lab-auto --region $AWS_REGION
   ```
   Write down three things that you *don't* control in Auto Mode. They'll matter in L300 and L400.
5. Tear down:
   ```bash
   eksctl delete cluster -f levels/L100-foundations/eksctl-cluster.yaml --disable-nodegroup-eviction
   ```

## Session 2 — the Terraform way + your first app (≈ 90 min)

1. Read the code before you apply it: [terraform/envs/lab/main.tf](../../terraform/envs/lab/main.tf) →
   [modules/vpc](../../terraform/modules/vpc/main.tf) → [modules/eks](../../terraform/modules/eks/main.tf).
   Questions to answer:
   - Why does the VPC have *three* kinds of subnets (public, private, intra)?
   - What do the `kubernetes.io/role/elb` tags do?
   - What does `http_put_response_hop_limit = 1` stop pods from doing?
2. Plan and apply:
   ```bash
   make plan LEVEL=100      # read the plan: ~60 resources
   make up LEVEL=100        # ~15 min
   kubectl get nodes -L node-role,topology.kubernetes.io/zone,karpenter.sh/capacity-type,eks.amazonaws.com/capacityType
   ```
3. Deploy the shop:
   ```bash
   scripts/deploy-shop.sh l100
   kubectl -n shop get all
   kubectl -n shop get svc shop-web -w     # wait for EXTERNAL-IP (a Classic LB), ~2 min
   open "http://$(kubectl -n shop get svc shop-web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
   ```
   Refresh the page a few times and watch the web and api pod names change.
4. Core Kubernetes workflow drills:
   ```bash
   kubectl -n shop scale deploy shop-web --replicas=4
   kubectl -n shop set env deploy/shop-api APP_VERSION=v2     # triggers a rolling update
   kubectl -n shop rollout status deploy/shop-api
   kubectl -n shop rollout history deploy/shop-api
   kubectl -n shop rollout undo deploy/shop-api
   kubectl -n shop logs -l app.kubernetes.io/name=shop-api --tail=20   # or: stern -n shop shop-
   kubectl -n shop exec deploy/shop-api -- python -c "import urllib.request;print(urllib.request.urlopen('http://shop-web/').status)"
   kubectl -n shop debug -it deploy/shop-api --image=public.ecr.aws/docker/library/busybox:1.37 --target=api -- sh
   kubectl get events -n shop --sort-by=.lastTimestamp | tail
   ```
5. Readiness vs liveness:
   ```bash
   POD=$(kubectl -n shop get pod -l app.kubernetes.io/name=shop-api -o name | head -1)
   kubectl -n shop exec $POD -- python -c "import urllib.request as u;u.urlopen(u.Request('http://localhost:8080/admin/readiness/off',method='POST'))"
   kubectl -n shop get endpointslices -l kubernetes.io/service-name=shop-api -o yaml | grep -A2 conditions
   ```
   The pod is still running, but it's no longer an endpoint. Turn readiness back `on`.

## 🔧 Break it (troubleshooting)
| Scenario | How to cause it | What to find |
|---|---|---|
| ImagePullBackOff | `kubectl -n shop set image deploy/shop-web web=nope:1` | `kubectl describe pod` → Events |
| Pending pod | `kubectl -n shop set resources deploy/shop-api -c api --requests=cpu=8` | `FailedScheduling: Insufficient cpu` |
| OOMKilled | `kubectl -n shop set resources deploy/shop-web -c web --limits=memory=20Mi` | `kubectl get pod` → `OOMKilled`, restart count |
| CrashLoopBackOff | `kubectl -n shop patch deploy shop-api --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["python","-c","import sys; print(\"boom\"); sys.exit(1)"]}]'` | `kubectl logs --previous`, back-off timing |
| Web shows an API error | `kubectl -n shop scale deploy shop-api --replicas=0` | red error banner on the page; Service has no endpoints |

Fix each one with `kubectl rollout undo`.

## ✅ Verify
```bash
make verify LEVEL=100
```

## Teardown
```bash
make down      # deletes the LB Service first, then terraform destroy, then nuke-check
```

## Quiz
1. Which components can you **not** see as pods in `kube-system`, and why?
2. A pod has IP 10.0.37.12. Where does that address come from, and what limits how many pods fit on a node?
3. What's the difference between an access *entry* and an access *policy*?
4. Name one reason to choose managed node groups over Auto Mode, and one reason to choose the reverse.
5. A readiness probe fails. Does the container restart? What happens to traffic?
