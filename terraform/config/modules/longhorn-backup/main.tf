data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "this" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Enabled"
}

resource "oci_identity_user" "this" {
  compartment_id = var.tenancy_id
  name           = var.user_name
  description    = "Dedicated user for Longhorn backups in OCI Object Storage"
  email          = var.user_email
}

resource "oci_identity_customer_secret_key" "this" {
  display_name = "longhorn-object-storage"
  user_id      = oci_identity_user.this.id
}

resource "oci_identity_policy" "this" {
  compartment_id = var.compartment_id
  name           = "LonghornObjectStorageBackups"
  description    = "Allow the Longhorn backup user to manage objects in its bucket"

  statements = [
    "Allow any-user to manage objects in tenancy where all {request.principal.type = 'user', request.principal.id = '${oci_identity_user.this.id}', target.bucket.name = '${var.bucket_name}'}",
  ]
}

resource "oci_vault_secret" "access_key" {
  compartment_id = var.compartment_id
  key_id         = var.vault_key_id
  secret_name    = "longhorn-backup-access-key"
  vault_id       = var.vault_id

  secret_content {
    content_type = "BASE64"
    content      = base64encode(oci_identity_customer_secret_key.this.id)
  }
}

resource "oci_vault_secret" "secret_key" {
  compartment_id = var.compartment_id
  key_id         = var.vault_key_id
  secret_name    = "longhorn-backup-secret-key"
  vault_id       = var.vault_id

  secret_content {
    content_type = "BASE64"
    content      = base64encode(oci_identity_customer_secret_key.this.key)
  }
}

resource "oci_vault_secret" "endpoint" {
  compartment_id = var.compartment_id
  key_id         = var.vault_key_id
  secret_name    = "longhorn-backup-endpoint"
  vault_id       = var.vault_id

  secret_content {
    content_type = "BASE64"
    content      = base64encode("https://${data.oci_objectstorage_namespace.this.namespace}.compat.objectstorage.${var.region}.oci.customer-oci.com")
  }
}
