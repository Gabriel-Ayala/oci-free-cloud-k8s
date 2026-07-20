resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "helm_release" "external_secrets" {
  depends_on = [kubernetes_namespace_v1.external_secrets]

  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "1.3.2"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    serviceAccount = {
      create = true
      name   = "external-secrets"
    }
  })]
}

resource "kubectl_manifest" "external_secrets_cluster_store" {
  depends_on = [helm_release.external_secrets]

  yaml_body = <<YAML
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: oracle-vault
spec:
  provider:
    oracle:
      vault: ${local.vault_id}
      region: ${var.region}
      principalType: ${var.principal_type}
      ${var.principal_type == "Workload" ? "serviceAccountRef:\n        name: external-secrets\n        namespace: external-secrets" : ""}
YAML
}
