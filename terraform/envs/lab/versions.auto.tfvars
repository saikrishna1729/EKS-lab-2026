# Single place for the Kubernetes version. The lab deliberately starts one minor behind
# the newest EKS version so you can practise an upgrade in L500.
# Check what's available:  aws eks describe-cluster-versions --query 'clusterVersions[].[clusterVersion,status]' --output table
kubernetes_version = "1.35"
