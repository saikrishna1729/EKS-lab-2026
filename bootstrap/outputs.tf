output "backend_hcl" {
  description = "Partial S3 backend config used by terraform/envs/*"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.bucket}"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "lab_admin_role_arn" {
  value = aws_iam_role.lab_admin.arn
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "route53_name_servers" {
  description = "Delegate your domain to these name servers (at your registrar / parent zone)."
  value       = try(aws_route53_zone.lab[0].name_servers, [])
}

output "velero_bucket" {
  value = aws_s3_bucket.velero.bucket
}

output "github_ci_role_arn" {
  value = try(aws_iam_role.github_ci[0].arn, "")
}
