# Cluster access and application authentication

This repository uses Keycloak directly for OIDC. Dex and Teleport are not
required by the active profiles.

## Identity endpoint

```text
https://keycloak-inova.hackyard.dev/realms/platform
```

The Kubernetes OIDC client is `kubernetes`. Keycloak emits the
`preferred_username` and `groups` claims through the configured group-membership
protocol mapper. The same `groups` claim is used by OAuth2 Proxy for Longhorn.
OKE prefixes both Kubernetes values with `oidc:` before RBAC evaluates them.

## Kubernetes API access

Staging and production use native OKE OIDC. Install the
[`kubectl oidc-login`](https://github.com/int128/kubelogin) plugin and run:

```sh
kubectl oidc-login setup \
  --oidc-issuer-url=https://keycloak-inova.hackyard.dev/realms/platform \
  --oidc-client-id=kubernetes
```

The Terraform-generated kubeconfigs initially use OCI IAM. Configure their
current contexts to use the OIDC credential plugin:

```sh
source ~/.zshrc

export KUBECONFIG="$PWD/terraform/.kube.staging.config"
kubectl config set-credentials oidc-keycloak \
  --exec-api-version=client.authentication.k8s.io/v1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=https://keycloak-inova.hackyard.dev/realms/platform \
  --exec-arg=--oidc-client-id=kubernetes \
  --exec-interactive-mode=Never
kubectl config set-context "$(kubectl config current-context)" --user=oidc-keycloak
kubectl get nodes
kubectl get pods -A

export KUBECONFIG="$PWD/terraform/.kube.production.config"
kubectl config set-credentials oidc-keycloak \
  --exec-api-version=client.authentication.k8s.io/v1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=https://keycloak-inova.hackyard.dev/realms/platform \
  --exec-arg=--oidc-client-id=kubernetes \
  --exec-interactive-mode=Never
kubectl config set-context "$(kubectl config current-context)" --user=oidc-keycloak
kubectl get nodes
kubectl get pods -A
```

Terraform regenerates these files when the cluster is applied, so repeat the
credential and context commands after a kubeconfig refresh. Do not change the
tools kubeconfig; tools is still a Basic cluster and uses OCI IAM.

The current tools cluster is `BASIC_CLUSTER`, so native OIDC is not enabled
there. Use OCI IAM until tools is migrated or recreated as an Enhanced
VCN-native cluster:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl get nodes
```

OCI IAM remains the break-glass access method for every cluster.

## RBAC groups

| Keycloak group | Kubernetes scope |
|---|---|
| `platform-admins` | cluster administrator |
| `platform-viewers` | cluster-wide read-only |
| `staging-admins` | staging administrator |
| `production-admins` | production administrator |

Group membership is managed in the Keycloak `platform` realm.

Longhorn OAuth2 Proxy requires the Keycloak user email to be marked as
verified. New users must have a verified email before they can complete the
Longhorn login flow.

After changing group membership, clear the local OIDC token cache and log in
again so the new `groups` claim is issued:

```sh
kubectl oidc-login clean
kubectl get nodes
```

## Protected Longhorn UIs

Each Longhorn UI is behind a dedicated OAuth2 Proxy using Keycloak:

```text
https://storage-tools.hackyard.dev
https://storage-staging.hackyard.dev
https://storage-production.hackyard.dev
```

Allowed groups are environment-specific plus `platform-admins`:

```text
longhorn-tools-admins
longhorn-staging-admins
longhorn-production-admins
```

Verify the protected route with:

```sh
kubectl -n flux-system get kustomization longhorn-auth
kubectl -n longhorn get helmrelease,externalsecret,secret,pods,svc
curl -I https://storage-tools.hackyard.dev
```

Unauthenticated requests should redirect to Keycloak; users outside the
allowed groups should receive HTTP 403.

## Grafana

Tools Grafana uses the same Keycloak realm through its generic OAuth
integration. `platform-admins` receive the Grafana Administrator role; other
authenticated users receive Viewer access. Its Keycloak callback is
`https://grafana-inova.hackyard.dev/login/generic_oauth`.

## Secrets and troubleshooting

Keycloak client secrets and OAuth2 Proxy cookie secrets are stored in OCI Vault
and synchronized by External Secrets. Never commit them, kubeconfigs, or
generated credentials.

```sh
kubectl get clustersecretstore oracle-vault
kubectl get externalsecret -A
kubectl -n flux-system get kustomizations
kubectl -n longhorn logs deploy/longhorn-auth
curl -fsS https://keycloak-inova.hackyard.dev/realms/platform/.well-known/openid-configuration | jq .issuer
```
