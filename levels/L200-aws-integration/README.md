# L200 — Core AWS integration

**Goal:** a cluster that is properly wired into AWS networking, identity, load balancing, DNS,
TLS and storage, with no static credentials anywhere.
**Time:** 4 sessions · **Cost:** ≈ $4–7 per session (ALB + interface endpoints add ~$0.06/h)

```
make up LEVEL=200     # Terraform + Helm: LB Controller, ExternalDNS, cert-manager, platform-config
make images           # if you changed the app
scripts/deploy-shop.sh l200
```

## Objectives
- Design an EKS VPC: subnet sizing, NAT choices, VPC endpoints, and LB discovery tags
- Explain VPC CNI IP management; fix IP exhaustion with prefix delegation
- Give pods AWS permissions with **EKS Pod Identity** (and know how IRSA differs)
- Expose apps with ALB Ingress, NLB, and **Gateway API**, with automatic DNS and TLS
- Use EBS (RWO, AZ-bound) and EFS (RWX) correctly, including snapshots
- Run a sane ECR setup: scanning, lifecycle, pull-through cache, multi-arch images

---

## Session 1 — Networking & the VPC CNI

**Concepts**
- Subnets: private `/19`s (8k IPs each) for nodes and pods, small public subnets for LBs/NAT,
  and *intra* subnets (no internet) for the control-plane ENIs. Read [modules/vpc/main.tf](../../terraform/modules/vpc/main.tf).
- One NAT gateway is cheap but a single point of failure across AZs. Production uses one per AZ (`single_nat_gateway = false`).
- **VPC endpoints**: the S3 gateway endpoint is free, and ECR stores layers in S3. Interface
  endpoints for `ecr.api`, `ecr.dkr` and `sts` keep image pulls and Pod Identity off the NAT.
- VPC CNI: each node has ENIs, each ENI has N secondary IPs. **Max pods** = ENIs × (IPs per ENI − 1) + 2.
  A t4g.large has 3 ENIs × 12 IPs → 35 pods. **Prefix delegation** assigns /28 prefixes instead → 110 pods.

**Lab**
```bash
# Without prefix delegation (temporarily):
kubectl -n kube-system set env ds/aws-node ENABLE_PREFIX_DELEGATION=false
kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"  maxPods="}{.status.allocatable.pods}{"\n"}{end}'
kubectl create deploy ipburn --image=public.ecr.aws/docker/library/busybox:1.37 --replicas=120 -- sleep infinity
kubectl get pods -l app=ipburn | grep -c Pending        # some can't schedule: "Too many pods"
kubectl -n kube-system logs ds/aws-node -c aws-node --tail=20 | grep -i ip
# Fix: the Terraform-managed add-on config re-enables prefix delegation. Re-apply it:
make up LEVEL=200
# NOTE: maxPods only changes for NEW nodes (it's set at kubelet bootstrap). Roll the node group:
aws eks update-nodegroup-version --cluster-name eks-lab --nodegroup-name $(aws eks list-nodegroups --cluster-name eks-lab --query 'nodegroups[0]' --output text) --force
kubectl delete deploy ipburn
```
Also inspect: `aws ec2 describe-network-interfaces --filters Name=tag:cluster.k8s.amazonaws.com/name,Values=eks-lab`

## Session 2 — Identity: Pod Identity vs IRSA

**Concepts**
| | EKS Pod Identity (used here) | IRSA |
|---|---|---|
| Trust | `pods.eks.amazonaws.com` service principal, the same for every cluster | Per-cluster OIDC provider in the role trust policy |
| Mapping | `aws_eks_pod_identity_association` (cluster, namespace, SA) | annotation on the ServiceAccount |
| Reuse role across clusters | Yes, with no trust policy edits | One trust condition per cluster |
| Session tags | Cluster/namespace/SA tags, usable for ABAC | No |
| Needs | the `eks-pod-identity-agent` add-on | nothing on nodes |

**Lab**
```bash
scripts/deploy-shop.sh l200
kubectl -n shop exec deploy/shop-api -- env | grep AWS_     # AWS_CONTAINER_CREDENTIALS_FULL_URI injected by the webhook
curl -s http://<ALB>/api/s3check | jq                       # identity = assumed-role/eks-lab-shop-api…
aws eks list-pod-identity-associations --cluster-name eks-lab --output table
```
Least privilege exercise: try `aws s3 ls` from a debug pod in the `default` namespace. It fails
because that ServiceAccount has no association. Then read [terraform/envs/lab/app.tf](../../terraform/envs/lab/app.tf)
and explain exactly which actions shop-api can and cannot perform.

> Why the hop limit matters: with `http_put_response_hop_limit = 1`, a pod **cannot** read the
> node's instance-role credentials from IMDS. Check it: `kubectl -n shop exec deploy/shop-api -- python -c "import urllib.request as u; u.urlopen(u.Request('http://169.254.169.254/latest/api/token', method='PUT', headers={'X-aws-ec2-metadata-token-ttl-seconds':'60'}), timeout=2)"` → timeout.

## Session 3 — Load balancing, Gateway API, DNS, TLS

**Concepts**
- The **AWS Load Balancer Controller** reconciles `Ingress` → ALB, `Service type=LoadBalancer` (with `loadBalancerClass: service.k8s.aws/nlb`) → NLB, and Gateway API `Gateway`/`HTTPRoute` → ALB or NLB.
- `target-type: ip` sends traffic straight to pod IPs, skipping kube-proxy and NodePorts. That needs the VPC CNI.
- `group.name` shares one ALB across many Ingresses (cost!).
- TLS: the ALB uses **ACM**. Terraform issues `*.DOMAIN` with DNS validation, and the controller
  discovers it from the Ingress host. **ExternalDNS** writes the Route 53 record.
  **cert-manager** is for certificates *inside* the cluster (mTLS, webhooks, NLB passthrough).

**Lab**
```bash
kubectl -n shop get ingress shop          # ADDRESS = ALB DNS name
aws elbv2 describe-target-groups --query 'TargetGroups[].{n:TargetGroupName,t:TargetType}' --output table
# With DOMAIN set: https://shop.$DOMAIN (watch ExternalDNS create it: kubectl -n external-dns logs deploy/external-dns)
```
Gateway API (the successor to Ingress):
```bash
kubectl apply -f levels/L200-aws-integration/gateway-api.yaml
kubectl -n shop get gateway,httproute
curl -s http://$(kubectl -n shop get gateway shop-gw -o jsonpath='{.status.addresses[0].value}')/api/whoami
```
NLB for TCP:
```bash
kubectl -n shop apply -f levels/L200-aws-integration/nlb-service.yaml
```
cert-manager (requires DOMAIN): `kubectl apply -f levels/L200-aws-integration/certificate.yaml`, then
`kubectl -n shop describe certificate shop-internal` and follow the DNS-01 challenge.

## Session 4 — Storage & ECR

**Concepts**
- EBS = one AZ, ReadWriteOnce. `WaitForFirstConsumer` makes the volume follow the pod's AZ.
  A pod rescheduled into another AZ **cannot** attach it, which is why StatefulSets spread replicas per AZ.
- EFS = multi-AZ, ReadWriteMany, more expensive per GB, higher latency.
- Snapshots: `VolumeSnapshot` → EBS snapshot. That's how backups (L500 Velero) work.

**Lab**
```bash
kubectl apply -f levels/L200-aws-integration/storage.yaml
kubectl -n storage-lab get pvc,pod -o wide        # note the AZ of the EBS volume and the pod
kubectl -n storage-lab exec ebs-writer-0 -- sh -c 'echo hello > /data/f && cat /data/f'
kubectl -n storage-lab apply -f levels/L200-aws-integration/snapshot.yaml
kubectl -n storage-lab get volumesnapshot -w      # READYTOUSE=true
kubectl -n storage-lab logs deploy/efs-readers --prefix | head   # 3 pods on different nodes share one EFS
kubectl delete ns storage-lab                     # reclaimPolicy Delete => volumes removed
```
ECR:
```bash
aws ecr describe-repositories --query 'repositories[].{n:repositoryName,scan:imageScanningConfiguration.scanOnPush,tags:imageTagMutability}' --output table
aws ecr get-lifecycle-policy --repository-name eks-lab/shop-api | jq -r .lifecyclePolicyText | jq
docker buildx imagetools inspect $(terraform -chdir=terraform/envs/lab output -raw ecr_registry)/eks-lab/shop-api:$(cat .lab/image-tag)  # arm64 + amd64
# Pull-through cache: pull a public image through YOUR registry
kubectl run ptc --image=$(terraform -chdir=terraform/envs/lab output -raw ecr_registry)/ecr-public/docker/library/busybox:1.37 -- sleep 60
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName,`ecr-public`)].repositoryName'
```
Bottlerocket vs AL2023: change `core_ami_type = "BOTTLEROCKET_ARM_64"` in the tfvars, run `make up LEVEL=200`,
and compare `kubectl get nodes -o wide` (OS image, kernel) and the attack surface (no shell, no package manager).

## 🔧 Break it
| Scenario | Cause | Clue |
|---|---|---|
| Ingress never gets an address | `kubectl -n kube-system scale deploy aws-load-balancer-controller --replicas=0` | `kubectl describe ingress` → no events |
| ALB created but 502/503 | patch the ingress `healthcheck-path: /nope` | Target group targets "unhealthy" |
| Pod can't read S3 | delete the pod identity association for shop-api, then restart the pod | `/api/s3check` → AccessDenied / NoCredentials |
| PVC Pending forever | create a PVC with `storageClassName: gp2-typo` | `kubectl describe pvc` |
| Volume can't attach | cordon all nodes in the volume's AZ and delete the pod | `FailedAttachVolume` / volume node affinity conflict |

## ✅ Verify
```bash
make verify LEVEL=200
```

## Teardown
```bash
make down
```

## Quiz
1. Your pods run out of IPs but the subnet has plenty of free addresses. What's going on, and what are two fixes?
2. Why does `target-type: ip` matter for zero-downtime deploys? (Hint: deregistration delay and `preStop`.)
3. Pod Identity: where does the SDK actually get credentials from, step by step?
4. Why must a StatefulSet with EBS volumes be spread by zone, and what breaks if a zone fails?
5. What does the S3 *gateway* endpoint save you, and why doesn't ECR work fully without it?
