# Argo CD Microsoft Entra ID SSO

Argo CD uses direct OpenID Connect authentication against the Brown Rook
Microsoft Entra ID tenant. The public Argo CD hostname is the canonical SSO
entry point; the internal hostname remains available for recovery and local
operations.

## Identity objects

| Object | Identifier |
| --- | --- |
| Tenant | `8b07f4bd-41e4-4106-8d49-00c5d79d35a2` |
| App registration client ID | `c563315a-a8cb-4d80-85b8-e57bcb21b35a` |
| App registration object ID | `d192c96a-f699-4da4-b527-6b90bd063bae` |
| Enterprise application object ID | `ebf2dc40-d73d-46f7-8066-0961291e93eb` |
| `ArgoCD Admins` group object ID | `f4b2fcb6-b52d-4152-83f0-cd01243a1be5` |

The enterprise application requires assignment. Only the `ArgoCD Admins`
group is assigned, and Argo CD maps that group ID to its built-in admin role.

## Redirect URIs

- Web UI: `https://argocd.idc.brownrook.com/auth/callback`
- CLI: `http://localhost:8085/auth/callback`

## Secret handling

The client secret is stored only in the existing `argocd-secret` Kubernetes
Secret under the `oidc.azure.clientSecret` key. It is never committed to Git.
The current `argocd-sso-2026-09-15` credential expires on
**2027-09-15 at 16:37:32 UTC**. Rotate it before expiry by creating an appended
Entra app credential and patching that key without printing the new value.

After changing the secret, restart `argocd-server` and verify both browser and
CLI login before deleting the previous Entra credential.

## Validation and recovery

1. Open `https://argocd.idc.brownrook.com` and select **Log in via Microsoft
   Entra ID**.
2. Confirm the signed-in account can view and synchronize applications.
3. Run `argocd login argocd.idc.brownrook.com --sso` and confirm CLI access.
4. Keep the local `admin` account enabled until both checks pass.

If Entra authentication fails, use the internal hostname and local admin or
use Kubernetes access to correct `argocd-cm`, `argocd-rbac-cm`, or
`argocd-secret`.
