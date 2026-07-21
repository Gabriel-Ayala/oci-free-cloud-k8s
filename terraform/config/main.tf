module "externalsecrets" {
  source = "./modules/external-secrets"
  count  = var.enable_external_secrets ? 1 : 0

  compartment_id = var.compartment_id
  cluster_id     = var.cluster_id
  cluster_name   = var.cluster_name
  create_vault   = var.create_external_secrets_vault
  principal_type = var.external_secrets_principal_type
  vault_id       = var.vault_id
  region         = var.region

  depends_on = [
    module.fluxcd
  ]
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
