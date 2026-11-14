# You sign in with IAM Identity Center. Only the EKSLabOperator permission set (whose sole
# permission is sts:AssumeRole on eks-lab-admin) may assume the lab role.
# Leave empty ([]) to use the IAM-user + MFA trust instead.
trusted_sso_permission_sets = ["EKSLabOperator"]
