output "amp_workspace_id" {
  value = aws_prometheus_workspace.this.id
}

output "amp_endpoint" {
  value = aws_prometheus_workspace.this.prometheus_endpoint
}

output "scraper_role_arn" {
  value = try(aws_prometheus_scraper.this[0].role_arn, "")
}
