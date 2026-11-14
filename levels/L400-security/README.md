# L400 — Security & hardening

**Goal:** a cluster that would pass a security review, covering identity, admission policy,
network, supply chain, runtime detection, encryption and audit.
**Time:** 5 sessions · **Cost:** ≈ $6–10 per session (GuardDuty has a 30-day free trial; KMS key $1/month, prorated)

```bash
make up LEVEL=400     # adds: NetworkPolicy enforcement, KMS secrets encryption, personas, Kyverno, security baseline
```
The `security-baseline` Argo CD app syncs [k8s/L400](../../k8s/L400) (policies, NetworkPolicies, RBAC).

Use the EKS Best Practices **Security** guide as your checklist: https://docs.aws.amazon.com/eks/latest/best-practices/security.html

---

## Session 1 — Cluster access & least privilege

**Concepts**
- Authentication goes IAM principal → **access entry**. Authorization is either an **EKS access
  policy** (scoped to the cluster or to namespaces) or **Kubernetes RBAC groups** (`kubernetes_groups`). We use both.
- The API endpoint has three settings: public, public+private (the lab default, optionally limited
  by CIDR), or private only. With private only you reach it through a VPN, Direct Connect, a bastion, or SSM port-forwarding.
- `enable_cluster_creator_admin_permissions` is convenient, but in production **break-glass
  admin** should be a separate, audited role.

**Lab**
```bash
# Restrict the public endpoint to your IP
echo "endpoint_public_access_cidrs = [\"$(curl -s https://checkip.amazonaws.com)/32\"]" >> levels/L400-security/lab.tfvars
make up LEVEL=400

aws eks list-access-entries --cluster-name eks-lab
aws eks list-associated-access-policies --cluster-name eks-lab --principal-arn $(terraform -chdir=terraform/envs/lab output -json persona_role_arns | jq -r .dev)

# Become the dev persona
DEV=$(terraform -chdir=terraform/envs/lab output -json persona_role_arns | jq -r .dev)
aws eks update-kubeconfig --name eks-lab --alias eks-lab-dev --role-arn $DEV
kubectl --context eks-lab-dev -n shop get pods          # ✔ allowed
kubectl --context eks-lab-dev -n shop delete pod -l app.kubernetes.io/name=shop-web   # ✔ allowed (edit)
kubectl --context eks-lab-dev -n kube-system get pods   # ✘ forbidden
kubectl --context eks-lab-dev auth can-i --list -n shop

# Viewer persona: mapped to group lab-viewers -> ClusterRole view (k8s/L400/rbac/viewer.yaml)
VIEW=$(terraform -chdir=terraform/envs/lab output -json persona_role_arns | jq -r .viewer)
aws eks update-kubeconfig --name eks-lab --alias eks-lab-viewer --role-arn $VIEW
kubectl --context eks-lab-viewer get pods -A            # ✔
kubectl --context eks-lab-viewer -n shop get secrets    # ✘ view excludes secrets — why does that matter?
kubectl config use-context eks-lab
```
Exercise (private endpoint): run `aws eks update-cluster-config --name eks-lab --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true`.
Your laptop loses access. Get it back with an SSM session to a Karpenter node
(`aws ssm start-session --target <instance-id>`; the node role has `AmazonSSMManagedInstanceCore`).
Revert afterwards with `make up LEVEL=400`.

## Session 2 — Admission control: Pod Security Standards + Kyverno

**Concepts**
- **Pod Security Admission** is built in, with three levels (privileged, baseline, restricted)
  set per namespace by label. It's a coarse floor.
- **Kyverno** adds custom validation (registries, tags, resources), mutation, generation and
  image verification. Roll it out in `Audit` first, read the PolicyReports, then switch to `Enforce`.

**Lab**
```bash
kubectl get clusterpolicy
kubectl get policyreport -A                       # audit results across the cluster
kubectl -n shop run bad --image=nginx:latest       # ✘ blocked: latest tag + not from ECR + no limits
kubectl run bad --image=nginx:latest -n default    # ✔ allowed but reported (Audit outside shop)
kubectl -n shop get pod -l app.kubernetes.io/name=shop-web -o jsonpath='{.items[0].metadata.labels.team}'   # mutated label
```
Raise the shop namespace to PSS **restricted** through Git: edit `k8s/apps/shop/base/shop.yaml`
(`enforce: restricted`), then push. Does the shop still run? (It should: non-root, seccomp,
dropped capabilities and a read-only root filesystem were built in from L100.) Try the same on
`monitoring` and explain what breaks (node-exporter needs host access).

## Session 3 — Network security

**Concepts**
- With `enable_network_policy = true`, the VPC CNI enforces standard Kubernetes NetworkPolicies
  using eBPF. No Calico is needed.
- The pattern is default-deny per namespace, then explicit allows. Remember DNS, the
  Pod Identity agent (169.254.170.23), and monitoring.
- **Security groups for pods** (`ENABLE_POD_ENI`) give a pod its own ENI and SG, for example to
  allow only the shop-api pods into an RDS security group.

**Lab**
```bash
kubectl -n shop get networkpolicy
curl -s http://$ALB/ | grep -c err                  # still works (ALB -> web -> api allowed)
kubectl -n default run probe --rm -it --image=public.ecr.aws/docker/library/busybox:1.37 -- wget -qO- -T 3 http://shop-api.shop:8080/api/whoami   # ✘ times out
kubectl -n shop run probe --rm -it --labels=app.kubernetes.io/name=shop-web --image=public.ecr.aws/docker/library/busybox:1.37 -- wget -qO- -T 3 http://shop-api:8080/api/whoami  # ✔ (pretending to be web)
```
Exercise: the last command shows that labels are identity in NetworkPolicy. Which L400 control
stops an attacker from simply setting that label? (Hint: RBAC on pod create plus Kyverno.)
Then remove `aws-api-egress` and watch `/api/s3check` fail. Now you have proof of egress control.

## Session 4 — Supply chain: scanning, signing, admission verification

```bash
cosign generate-key-pair                           # cosign.key (gitignored) + cosign.pub
REG=$(terraform -chdir=terraform/envs/lab output -raw ecr_registry); TAG=$(cat .lab/image-tag)
aws ecr get-login-password | cosign login --username AWS --password-stdin $REG
for s in web api worker; do cosign sign --yes --key cosign.key $REG/eks-lab/shop-$s:$TAG; done
cosign verify --key cosign.pub $REG/eks-lab/shop-api:$TAG | jq '.[0].critical'
```
1. Paste `cosign.pub` into [k8s/L400/policies/verify-images.yaml](../../k8s/L400/policies/verify-images.yaml) and set `validationFailureAction: Enforce`. Push.
2. Restart the shop deployments. Pods now run by **digest** (`mutateDigest`).
3. Push an *unsigned* image (`IMAGE_TAG=unsigned make images`) and point the Rollout at it → admission **denied**.
4. Uncomment the cosign step in `.github/workflows/shop.yaml` so CI signs everything it builds.
5. ECR: switch the repos to `IMMUTABLE` tags in `bootstrap/main.tf` and turn on **enhanced scanning** (Amazon Inspector) for continuous CVE monitoring:
   `aws ecr put-registry-scanning-configuration --scan-type ENHANCED --rules '[{"scanFrequency":"CONTINUOUS_SCAN","repositoryFilters":[{"filter":"eks-lab/*","filterType":"WILDCARD"}]}]'`
   (Inspector charges per image scanned; switch back to BASIC after the lab.)

## Session 5 — Runtime detection, encryption, audit

**GuardDuty.** If the region has no detector, set `enable_guardduty = true`. Otherwise enable
*EKS Protection* and *Runtime Monitoring* (automated agent) in the console.
```bash
aws eks describe-addon --cluster-name eks-lab --addon-name aws-guardduty-agent --query addon.status
kubectl apply -f k8s/tools/attack-sim.yaml
kubectl -n attack-sim exec -it suspicious -- sh -c 'apk add --no-cache curl nmap >/dev/null; nmap -sn 10.0.0.0/28; cat /etc/shadow; curl -s -m2 http://169.254.169.254/latest/meta-data/ || true'
# 5-15 min later:
aws guardduty list-findings --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --finding-criteria '{"Criterion":{"resource.eksClusterDetails.name":{"Eq":["eks-lab"]}}}'
kubectl delete ns attack-sim
```
Optional comparison: install Falco (`falcosecurity/falco`) and trigger the same actions. Where do its alerts go, and who would read them?

**Encryption.**
```bash
aws eks describe-cluster --name eks-lab --query cluster.encryptionConfig     # your KMS key, resources=[secrets]
aws kms describe-key --key-id $(terraform -chdir=terraform/envs/lab output -raw kms_key_arn) --query KeyMetadata.KeyManager
```
EBS volumes (gp3 class), EFS and SQS are encrypted too. Check each one in the console.

**Audit and CIS.**
```bash
kubectl apply -f k8s/tools/kube-bench.yaml && kubectl wait --for=condition=complete job/kube-bench --timeout=120s && kubectl logs job/kube-bench | tail -30
```
Logs Insights on `/aws/eks/eks-lab/cluster`: who used `exec` in the last hour?
```
fields @timestamp, user.username, objectRef.namespace, objectRef.name
| filter objectRef.subresource = "exec" | sort @timestamp desc
```

## 🔧 Break it
| Scenario | Cause | Clue |
|---|---|---|
| Whole cluster can't create pods | Kyverno webhook down with `failurePolicy: Fail` (scale kyverno to 0) | Events: `failed calling webhook` — why we exclude kube-system/argocd |
| DNS fails in shop | delete `allow-dns` NetworkPolicy | `getaddrinfo` errors, `/api/s3check` fails |
| Dev locked out | remove the dev access entry | `You must be logged in to the server (Unauthorized)` |
| Signed image rejected after re-tag | re-push a different image to an existing tag | signature/digest mismatch → `IMMUTABLE` tags prevent this |

## ✅ Verify
```bash
make verify LEVEL=400
```

## Quiz
1. Access policy vs RBAC group: when would you use each?
2. Why must a default-deny NetworkPolicy namespace explicitly allow 169.254.170.23?
3. What's the difference between scanning an image and verifying its signature? Which one stops a compromised CI?
4. What does a customer-managed KMS key for Secrets give you over the AWS-owned default key?
5. Kyverno with `failurePolicy: Fail` vs `Ignore`: trade-offs?
