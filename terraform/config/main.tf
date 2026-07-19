module "externalsecrets" {
  source = "./modules/external-secrets"
  count  = var.enable_external_secrets ? 1 : 0

  compartment_id = var.compartment_id
  tenancy_id     = var.tenancy_id
  vault_id       = var.vault_id

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
}

module "grafana" {
  source = "./modules/grafana"
  count  = var.enable_grafana_iam ? 1 : 0

  compartment_id = var.compartment_id
}
