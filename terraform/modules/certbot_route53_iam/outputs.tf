# outputs.tf
output "access_key_id" {
  value = aws_iam_access_key.certbot.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.certbot.secret
  sensitive = true
}

output "iam_user_name" {
  value = aws_iam_user.certbot.name
}

output "policy_arn" {
  value = aws_iam_policy.certbot_route53.arn
}