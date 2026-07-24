module "externalsecrets" {
  source = "./modules/external-secrets"
  count  = var.enable_external_secrets ? 1 : 0

  compartment_id = var.compartment_id
  cluster_id     = var.cluster_id
  cluster_name   = var.cluster_name
  create_vault   = var.create_external_secrets_vault
  vault_key_id   = var.vault_key_id
  principal_type = var.external_secrets_principal_type
  vault_id       = var.vault_id
  region         = var.region

  depends_on = [
    module.fluxcd
  ]
}

module "keycloak_admin" {
  source = "./modules/keycloak-admin"
  count  = var.enable_keycloak ? 1 : 0

  compartment_id = var.compartment_id
  vault_id       = module.externalsecrets[0].vault_id
  vault_key_id   = module.externalsecrets[0].key_id

  depends_on = [module.externalsecrets]
}

module "mariadb_credentials" {
  source = "./modules/mariadb-credentials"
  count  = var.enable_mariadb ? 1 : 0

  compartment_id = var.compartment_id
  vault_id       = module.externalsecrets[0].vault_id
  vault_key_id   = module.externalsecrets[0].key_id
  cluster_name   = var.cluster_name

  depends_on = [module.externalsecrets]
}

module "fluxcd" {
  source = "./modules/fluxcd"

  gh_token                   = var.gh_token
  compartment_id             = var.compartment_id
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_pem             = var.github_app_pem
  gitops_path                = var.gitops_path
  git_url                    = var.git_url
  gh_org                     = var.gh_org
  gh_repository              = var.gh_repository
  git_auth_enabled           = var.git_auth_enabled
  enable_github_webhook      = var.enable_github_webhook
}

module "ingress" {
  source = "./modules/ingress"
  count  = var.enable_ingress ? 1 : 0

  compartment_id = var.compartment_id
  vcn_name       = "${var.cluster_name}-vcn"
}

module "grafana" {
  source = "./modules/grafana"
  count  = var.enable_grafana_iam ? 1 : 0

  compartment_id = var.compartment_id
}

module "longhorn_backup" {
  source = "./modules/longhorn-backup"
  count  = var.enable_longhorn_backup ? 1 : 0

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_id
  region         = var.region
  vault_id       = module.externalsecrets[0].vault_id
  vault_key_id   = module.externalsecrets[0].key_id
  bucket_name    = var.longhorn_backup_bucket_name
  user_email     = var.longhorn_backup_user_email

  depends_on = [module.externalsecrets]
}

module "mimir_storage" {
  source = "./modules/mimir-storage"
  count  = var.enable_mimir_storage ? 1 : 0

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_id
  region         = var.region
  vault_id       = module.externalsecrets[0].vault_id
  vault_key_id   = module.externalsecrets[0].key_id
  bucket_name    = var.mimir_storage_bucket_name
  user_email     = var.mimir_storage_user_email

  depends_on = [module.externalsecrets]
}

resource "kubectl_manifest" "mimir_oci_config" {
  count = var.enable_mimir_storage ? 1 : 0

  yaml_body = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: observability-config
  namespace: flux-system
data:
  MIMIR_PRIVATE_SUBNET_ID: "${var.private_subnet_id}"
  MIMIR_PRIVATE_IP_ID: "${var.mimir_private_ip_id}"
  MIMIR_PRIVATE_IP_ADDRESS: "${var.mimir_private_ip_address}"
YAML
}
