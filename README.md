# BrownRook Infrastructure (IaC)

Infrastructure-as-Code for BrownRook services.

This repository contains Terraform configuration and AWS integration
used to provision and manage:

- Route53 DNS
- IAM roles and policies
- Certbot DNS-01 automation
- Environment scaffolding (dev / prod)
- Future infrastructure components

---

## Repository Structure

aws/              → AWS-specific configuration (IAM, certbot, Route53)
terraform/        → Terraform modules and environments
scripts/          → Helper scripts for provisioning
docs/             → Architecture and operational documentation

---

## Design Principles

- Infrastructure is declarative
- No secrets committed to Git
- Terraform state is never stored in the repository
- Environments are isolated (dev / prod)
- Changes are version-controlled and auditable

---

## Security

The following are intentionally excluded via .gitignore:

- .terraform/
- *.tfstate
- terraform.tfvars
- .env
- *.pem / *.key
- AWS credentials

Secrets must be stored securely outside this repository.

---

## Terraform Usage

Initialize:

    terraform init

Validate:

    terraform validate

Plan:

    terraform plan

Apply:

    terraform apply

---

## Next Steps

- Configure remote backend (S3 + DynamoDB locking)
- Add CI validation workflow
- Separate dev/prod environments
- Implement least-privilege IAM policies

---

## Status

This repository supports:

✔ Route53 IAM automation for DNS-01  
✔ Certbot integration  
✔ Structured Terraform module layout  

