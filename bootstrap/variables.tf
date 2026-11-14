variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "alert_email" {
  type        = string
  description = "Email that receives budget and anomaly alerts."
}

variable "monthly_budget_usd" {
  type    = number
  default = 50
}

variable "create_anomaly_monitor" {
  type        = bool
  default     = false
  description = "Create a SERVICE anomaly monitor. Most accounts already have AWS's default one (only one is allowed)."
}

variable "require_mfa" {
  type        = bool
  default     = true
  description = "Require MFA to assume eks-lab-admin. Strongly recommended."
}

variable "trusted_sso_permission_sets" {
  type        = list(string)
  default     = []
  description = "IAM Identity Center permission set names allowed to assume eks-lab-admin (e.g. [\"AdministratorAccess\"]). When set, replaces the MFA condition."
}

variable "domain" {
  type        = string
  default     = ""
  description = "Optional domain/subdomain to host in Route 53 for L200 TLS/DNS labs."
}

variable "github_repo" {
  type        = string
  default     = ""
  description = "owner/name of your GitHub repo for L300 CI (empty = skip)."
}

variable "create_github_oidc_provider" {
  type        = bool
  default     = true
  description = "Set false if token.actions.githubusercontent.com already exists in the account."
}
