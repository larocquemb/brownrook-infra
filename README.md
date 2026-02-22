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

<<<<<<< HEAD
---

# Phase 1 Scope

## Included

- Minimal IDC API service
- JWT validation middleware
- Public `/health` endpoint
- Secured `/secure` endpoint
- Reverse proxy front-end (nginx)
- Structured architecture and security documentation

## Excluded (Phase 2)

- mTLS between services
- Private CA integration
- Automated certificate rotation
- Multi-tenant identity
- Fine-grained RBAC
=======
## Identity Trust Model

IDC acts as a resource server and enforces token-based trust.

A request is accepted if and only if:

ValidSignature ∧
IssuerMatch ∧
AudienceMatch ∧
NotExpired ∧
ScopeSatisfied

Trust Anchor:
- Microsoft Entra ID Tenant (tid: 8b07f4bd-41e4-4106-8d49-00c5d79d35a2)

The system does not trust:
- Tokens from other tenants
- Tokens signed by unknown keys
- Tokens missing required scope
- Expired tokens
- Tokens with incorrect audience

---

# Phase 1 Scope

## Included

- Minimal IDC API service
- JWT validation middleware
- Public `/health` endpoint
- Secured `/secure` endpoint
- Reverse proxy front-end (nginx)
- Structured architecture and security documentation

## Excluded (Phase 2)

- mTLS between services
- Private CA integration
- Automated certificate rotation
- Multi-tenant identity
- Fine-grained RBAC