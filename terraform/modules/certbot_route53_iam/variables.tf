# variables.tf
variable "name_prefix" {
  description = "Prefix for IAM resources (e.g., brownrook)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 Hosted Zone ID for the zone that contains the record (e.g., Z123...)"
  type        = string
}

variable "tags" {
  description = "Optional tags"
  type        = map(string)
  default     = {}
}