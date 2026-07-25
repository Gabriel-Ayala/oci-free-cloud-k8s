# ExternalDNS

ExternalDNS manages Cloudflare DNS records declared by Kubernetes resources in
the `tools`, `staging`, and `production` clusters. Each cluster runs its own
ExternalDNS deployment and uses a distinct TXT owner ID so that one cluster
does not adopt or delete another cluster's records.

## Cluster configuration

All three clusters use the shared resources at
`gitops/core/external-dns/resources/`. The cluster roots select the same
HelmRelease and substitute their owner IDs:

| Cluster | Flux Kustomization | TXT owner ID |
|---|---|---|
| tools | `gitops/tools/external-dns.yaml` | `tools` |
| staging | `gitops/staging/external-dns.yaml` | `staging` |
| production | `gitops/production/external-dns.yaml` | `production` |

ExternalDNS watches Services, Ingresses, `DNSEndpoint` resources, and Gateway
API `HTTPRoute` resources. It manages A records with the `sync` policy. The
configured domain filters are:

```text
amedsaude.com.br
amedpy.com
cms-sync.com.br
coomedms.com.br
drpap.com.br
drpap.uy
helppap.com
infectoassist.com.br
inovapap.com.br
monitoramentoemsaude.com.br
moveye.com.br
papeduca.com.br
papensino.com.br
papescala.com.br
papinfecto.com.br
pap-sync.com.br
perreabilita.com.br
qualiassist.com.br
```

The provider configuration is in
[`gitops/core/external-dns/resources/helm.yaml`](../gitops/core/external-dns/resources/helm.yaml).
The full shared profile has the equivalent configuration in
[`gitops/core/external-dns/helm.yaml`](../gitops/core/external-dns/helm.yaml).

## Credentials and security

ExternalDNS receives `CF_API_TOKEN` from the `external-dns-config` Secret. The
Secret is created by an ExternalSecret that reads the existing OCI Vault secret
named `cloudflare-api-token` through the `oracle-vault` ClusterSecretStore.
The token must have, for every managed zone:

- Zone read access;
- DNS record edit access.

The token is never stored in Git, Kubernetes manifests, or committed `.env`
files. Rotate it by updating the existing Vault secret; External Secrets
refreshes the Kubernetes Secret automatically.

## ExternalDNS and certificates

ExternalDNS creates DNS records; it does not issue TLS certificates. cert-manager
uses the same Cloudflare token for DNS01 validation through the `letsencrypt`
ClusterIssuer. A new hostname or zone therefore needs both:

1. A DNS-producing Kubernetes resource, such as an HTTPRoute or Service;
2. A cert-manager `Certificate` resource when the hostname is not covered by
   an existing certificate.

The current wildcard certificate `*.amedsaude.com.br` does not cover other
zones such as `amedpy.com` or `drpap.uy`. Use separate certificates per zone
or hostname, and include the apex name separately when it is required because
`*.example.com` does not cover `example.com`.

## Reconciliation and verification

Check the deployment and credentials in each cluster:

```sh
for cluster in tools staging production; do
  export KUBECONFIG="terraform/.kube.${cluster}.config"
  kubectl -n external-dns get deployment,pod,externalsecret,secret
  kubectl -n external-dns logs deploy/external-dns --since=10m
done
```

Force a Flux refresh after changing Git:

```sh
export KUBECONFIG=terraform/.kube.tools.config
flux reconcile source git flux-system --timeout=2m
flux reconcile kustomization flux-system --with-source --timeout=8m
flux reconcile kustomization external-dns --with-source --timeout=8m
```

Confirm the cluster-specific owner ID and reconciliation revision:

```sh
kubectl -n flux-system get kustomization external-dns -o yaml
kubectl -n external-dns get pod
```

For a route, verify the HTTPRoute and the resulting Cloudflare A record. A
new record can take time to appear in recursive DNS caches even after the
Cloudflare API and ExternalDNS report success.

## Current limitation

The configured domain filter includes `helppap.com`, but the current AMED
Cloudflare token does not see that zone. DNS records in that zone will not be
manageable until the zone exists in the token's Cloudflare account and the
token has Zone Read and DNS Edit permissions there.

