output "access_key_id" {
  value = module.certbot_route53_iam.access_key_id
}

output "secret_access_key" {
  value     = module.certbot_route53_iam.secret_access_key
  sensitive = true
}

output "iam_user_name" {
  value = module.certbot_route53_iam.iam_user_name
}