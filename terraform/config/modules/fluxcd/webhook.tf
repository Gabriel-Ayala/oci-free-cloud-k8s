data "github_repository" "oci" {
  count     = var.enable_github_webhook ? 1 : 0
  full_name = "${var.gh_org}/${var.gh_repository}"
}

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

data "oci_kms_vaults" "existing_vault" {
  count          = var.enable_github_webhook ? 1 : 0
  compartment_id = var.compartment_id
}

data "oci_kms_keys" "existing_key" {
  count               = var.enable_github_webhook ? 1 : 0
  compartment_id      = var.compartment_id
  management_endpoint = data.oci_kms_vaults.existing_vault[0].vaults[0].management_endpoint
}

resource "oci_vault_secret" "test_secret" {
  count = var.enable_github_webhook ? 1 : 0
  #Required
  compartment_id = var.compartment_id
  key_id         = data.oci_kms_keys.existing_key[0].keys[0].id
  secret_name    = "github-flux-webhook-token"
  vault_id       = data.oci_kms_vaults.existing_vault[0].vaults[0].id

  secret_content {
    name         = "token"
    content_type = "BASE64"
    content      = base64encode(random_password.webhook_secret.result)
  }
}

resource "github_repository_webhook" "flux_webhook" {
  count      = var.enable_github_webhook ? 1 : 0
  repository = data.github_repository.oci[0].name

  configuration {
    url          = "https://flux-webhook.hackyard.dev/hook/${sha256(format("%s%s%s", random_password.webhook_secret.result, "github-receiver", "flux-system"))}"
    content_type = "json"
    secret       = random_password.webhook_secret.result
    insecure_ssl = false
  }

  events = ["push"]
}
