module "certbot_route53_iam" {
  source         = "../../../modules/certbot_route53_iam"
  name_prefix    = "brownrook"
  hosted_zone_id = var.hosted_zone_id

  tags = {
    Project = "brownrook-infra"
    Owner   = "brownrook"
    Purpose = "certbot-dns-01"
    Env     = "prod"
  }
}