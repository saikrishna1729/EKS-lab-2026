variable "cluster_name" {
  type = string
}

variable "route53_zone_arn" {
  type    = string
  default = ""
}

variable "velero_bucket" {
  type    = string
  default = ""
}

variable "sqs_queue_arns" {
  type    = list(string)
  default = []
}

variable "enable_lb_controller" {
  type    = bool
  default = false
}

variable "enable_external_dns" {
  type    = bool
  default = false
}

variable "enable_cert_manager" {
  type    = bool
  default = false
}

variable "enable_external_secrets" {
  type    = bool
  default = false
}

variable "enable_velero" {
  type    = bool
  default = false
}

variable "enable_keda" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_kyverno" {
  type    = bool
  default = false
}
