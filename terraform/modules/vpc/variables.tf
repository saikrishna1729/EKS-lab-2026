variable "name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "enable_vpc_endpoints" {
  type    = bool
  default = false
}

variable "interface_endpoints" {
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts"]
  description = "Interface endpoints to create when enable_vpc_endpoints = true."
}

variable "tags" {
  type    = map(string)
  default = {}
}
