# main.tf
resource "aws_iam_user" "certbot" {
  name = "${var.name_prefix}-certbot-route53"
  tags = var.tags
}

data "aws_iam_policy_document" "certbot_route53" {
  statement {
    sid    = "ListZonesAndGetChange"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:GetChange"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ChangeRecordsInHostedZone"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
  }
}

resource "aws_iam_policy" "certbot_route53" {
  name   = "${var.name_prefix}-certbot-route53"
  policy = data.aws_iam_policy_document.certbot_route53.json
}

resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.certbot.name
  policy_arn = aws_iam_policy.certbot_route53.arn
}

resource "aws_iam_access_key" "certbot" {
  user = aws_iam_user.certbot.name
}