output "role_arns" {
  value = {
    aws_lb_controller = try(module.aws_lb_controller[0].iam_role_arn, null)
    external_dns      = try(module.external_dns[0].iam_role_arn, null)
    cert_manager      = try(module.cert_manager[0].iam_role_arn, null)
    external_secrets  = try(module.external_secrets[0].iam_role_arn, null)
    velero            = try(module.velero[0].iam_role_arn, null)
    keda              = try(module.keda[0].iam_role_arn, null)
    kyverno           = try(module.kyverno[0].iam_role_arn, null)
  }
}
