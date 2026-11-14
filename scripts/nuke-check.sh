#!/usr/bin/env bash
# After `make down`: list billable resources the lab may have left behind.
# Read-only — it prints delete commands, it never deletes anything itself.
source "$(dirname "$0")/lib.sh"
R="$AWS_REGION"; C="$CLUSTER_NAME"; found=0

hit() { echo "  ${c_bad}●${c_off} $1"; [[ -n "${2:-}" ]] && echo "      ${c_dim}$2${c_off}"; found=1; }
echo "Leftover check in $R for cluster '$C'"

aws eks describe-cluster --region "$R" --name "$C" >/dev/null 2>&1 &&
  hit "EKS cluster $C still exists (\$0.10/h)" "make down"

for arn in $(aws elbv2 describe-load-balancers --region "$R" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
  tags=$(aws elbv2 describe-tags --region "$R" --resource-arns "$arn" --query 'TagDescriptions[0].Tags' --output json)
  if jq -e --arg c "$C" 'map(select((.Key=="elbv2.k8s.aws/cluster" and .Value==$c) or .Key==("kubernetes.io/cluster/"+$c))) | length>0' <<<"$tags" >/dev/null; then
    hit "Load balancer $arn" "aws elbv2 delete-load-balancer --region $R --load-balancer-arn $arn"
  fi
done

for lb in $(aws elb describe-load-balancers --region "$R" --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text 2>/dev/null); do
  if aws elb describe-tags --region "$R" --load-balancer-names "$lb" --output json |
     jq -e --arg c "$C" '.TagDescriptions[0].Tags | map(select(.Key==("kubernetes.io/cluster/"+$c))) | length>0' >/dev/null; then
    hit "Classic load balancer $lb (from L100 Service type LoadBalancer)" "aws elb delete-load-balancer --region $R --load-balancer-name $lb"
  fi
done

aws ec2 describe-volumes --region "$R" --filters Name=status,Values=available \
  --query "Volumes[?Tags[?Key=='kubernetes.io/cluster/$C' || Key=='KubernetesCluster' && Value=='$C' || Key=='ebs.csi.aws.com/cluster' || Key=='Project' && Value=='eks-lab']].VolumeId" \
  --output text | tr '\t' '\n' | grep . | while read -r v; do hit "Unattached EBS volume $v" "aws ec2 delete-volume --region $R --volume-id $v"; done

aws ec2 describe-instances --region "$R" \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped "Name=tag:karpenter.sh/discovery,Values=$C" \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | grep . |
  while read -r i; do hit "Karpenter instance $i" "aws ec2 terminate-instances --region $R --instance-ids $i"; done

aws ec2 describe-instances --region "$R" \
  --filters Name=instance-state-name,Values=pending,running "Name=tag:eks:cluster-name,Values=$C" \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | grep . |
  while read -r i; do hit "Node instance $i still running" "(make down should remove it)"; done

aws ec2 describe-nat-gateways --region "$R" --filter Name=state,Values=available,pending Name=tag:Project,Values=eks-lab \
  --query 'NatGateways[].NatGatewayId' --output text | tr '\t' '\n' | grep . |
  while read -r n; do hit "NAT gateway $n (\$0.059/h)" "aws ec2 delete-nat-gateway --region $R --nat-gateway-id $n"; done

aws ec2 describe-addresses --region "$R" --query 'Addresses[?AssociationId==null].AllocationId' --output text | tr '\t' '\n' | grep . |
  while read -r a; do hit "Unassociated Elastic IP $a (\$0.005/h)" "aws ec2 release-address --region $R --allocation-id $a"; done

aws ec2 describe-vpcs --region "$R" --filters Name=tag:Project,Values=eks-lab --query 'Vpcs[].VpcId' --output text | tr '\t' '\n' | grep . |
  while read -r v; do hit "VPC $v still exists (usually blocked by an orphaned ENI/LB)" "aws ec2 describe-network-interfaces --region $R --filters Name=vpc-id,Values=$v"; done

aws ec2 describe-vpc-endpoints --region "$R" --filters Name=tag:Project,Values=eks-lab --query 'VpcEndpoints[].VpcEndpointId' --output text | tr '\t' '\n' | grep . |
  while read -r e; do hit "VPC endpoint $e" "aws ec2 delete-vpc-endpoints --region $R --vpc-endpoint-ids $e"; done

aws prometheusservice list-scrapers --region "$R" --query "scrapers[?alias=='$C-scraper'].scraperId" --output text 2>/dev/null | tr '\t' '\n' | grep . |
  while read -r s; do hit "AMP scraper $s" "aws amp delete-scraper --region $R --scraper-id $s"; done

if [[ $found -eq 0 ]]; then echo "  ${c_ok}✔ nothing billable left behind${c_off} (bootstrap resources are kept on purpose)"; fi
