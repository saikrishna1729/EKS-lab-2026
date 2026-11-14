variable "cluster_name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  type = string
}

variable "enable_managed_scraper" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
