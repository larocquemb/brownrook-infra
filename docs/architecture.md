# BrownRook IDC – Architecture (Phase 1)

## Overview

BrownRook Identity & Control Plane (IDC) is an identity-aware API gateway that validates external OIDC tokens before granting access to internal services.

Phase 1 establishes a minimal, production-ready identity boundary.

---

## Logical Architecture

Client  
↓ (HTTPS + Bearer JWT)  
Reverse Proxy (nginx)  
↓ (HTTP internal)  
IDC API (FastAPI + JWT validation)  
↓  
Future internal services  

Trust decisions occur **only inside IDC**.

---

## Physical Deployment (Proxmox)

CT200 – Reverse Proxy  
- nginx
- TLS termination
- Let’s Encrypt wildcard certificate
- Forwards to IDC on port 8080

CT201 – IDC API  
- FastAPI service
- systemd-managed
- Validates OIDC tokens
- Not directly exposed to internet

---

## DNS

Public:
- idc.brownrook.com → reverse proxy

Internal:
- idc1.brownrook.net → CT201
- proxy.brownrook.net → CT200

---

## Ports

| Component | Port | Exposure |
|-----------|------|----------|
| nginx     | 443  | Public   |
| IDC       | 8080 | Internal |

---

## Certificate Management

- Wildcard certificate: *.idc.brownrook.com
- Issued via Let's Encrypt
- DNS-01 challenge using Route53 IAM automation
- Certbot handles renewal

---

## Service Management

Systemd unit:

    /etc/systemd/system/brownrook-idc.service

Environment configuration:

    /opt/brownrook-idc/app/.env

Start / Restart:

    systemctl restart brownrook-idc
    journalctl -u brownrook-idc -f

---

## Health Check

Public health endpoint:

    GET /health

Used for:
- Reverse proxy verification
- Operational monitoring