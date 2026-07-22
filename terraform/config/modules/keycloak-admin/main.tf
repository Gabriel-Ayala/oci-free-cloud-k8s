resource "random_password" "admin" {
  length           = 32
  special          = true
  override_special = "!#$%&()*+,-.:;<=>?@[]^_{|}~"
}

resource "oci_vault_secret" "admin_password" {
  compartment_id = var.compartment_id
  key_id         = var.vault_key_id
  secret_name    = "keycloak-tools-admin-password"
  vault_id       = var.vault_id

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.admin.result)
  }
}
