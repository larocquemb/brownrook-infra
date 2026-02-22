# BrownRook IDC – Identity Trust Model (Phase 1)

## Trust Philosophy

IDC enforces identity-based trust.

A request is accepted if and only if:

    ValidSignature
    ∧ IssuerMatch
    ∧ AudienceMatch
    ∧ NotExpired
    ∧ ScopeSatisfied

Formally:

Allow ⇔
(sig_valid)
∧ (iss = expected_issuer)
∧ (aud = expected_audience)
∧ (exp > now)
∧ (scp ⊇ required_scope)

---

## Trust Anchors

Trusted Identity Provider:
- Microsoft Entra ID

Trusted Tenant ID:
- 8b07f4bd-41e4-4106-8d49-00c5d79d35a2

Trusted JWKS Endpoint:
- https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys

Only keys published by this JWKS endpoint are accepted.

---

## Authorization Model

Scope required:

    access_as_user

If scope is missing → request rejected.

---

## Failure Handling Contract

Token validation errors:
→ HTTP 401 Unauthorized

JWKS fetch / network errors:
→ HTTP 503 Service Unavailable

Unexpected auth failures:
→ HTTP 401

This ensures predictable security boundaries.

---

## Explicit Non-Trust

The system does NOT trust:

- Tokens from other tenants
- Tokens with invalid audience
- Expired tokens
- Tokens missing required scope
- Self-signed tokens
- Tokens signed by unknown keys

---

## Zero-Trust Principles Applied

- No implicit network trust
- Identity validated on every request
- Signature verified per request
- TLS enforced at boundary
- No session-based bypass

IDC is a resource server only.
It does not issue tokens.
It validates them.

---

## Phase 2 (Not Included)

- mTLS between services
- Private CA integration
- Automated internal certificate rotation
- Multi-tenant support
- Fine-grained RBAC