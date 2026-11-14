# AWS FIS experiments (L500 session 3)

FIS needs an IAM role it can assume. Create it once:
```bash
aws iam create-role --role-name eks-lab-fis --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"fis.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name eks-lab-fis --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access
aws iam attach-role-policy --role-name eks-lab-fis --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEKSAccess
aws iam attach-role-policy --role-name eks-lab-fis --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorNetworkAccess
```
Then, for each template:
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
sed "s/ACCOUNT_ID/$ACCOUNT/g; s/REGION/$AWS_REGION/g" fis/<template>.json > /tmp/fis.json
ID=$(aws fis create-experiment-template --cli-input-json file:///tmp/fis.json --query experimentTemplate.id --output text)
aws fis start-experiment --experiment-template-id $ID
```
Every template has a **stop condition** wired to nothing by default. Add a CloudWatch alarm (for example the ALB 5xx rate) so FIS aborts if your SLO breaks.
