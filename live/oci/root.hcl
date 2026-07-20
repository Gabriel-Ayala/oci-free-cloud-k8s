locals {
  compartment_id     = get_env("OCI_COMPARTMENT_ID", "")
  config_profile     = get_env("OCI_CONFIG_PROFILE", "DEFAULT")
  kubernetes_version = get_env("TF_VAR_kubernetes_version", "v1.33.1")
  region             = get_env("OCI_REGION", "eu-frankfurt-1")
  tenancy_id         = get_env("OCI_TENANCY_ID", "")
  ssh_public_key     = get_env("TF_VAR_ssh_public_key", "")
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"

  contents = <<EOF
provider "oci" {
  region              = "${local.region}"
  config_file_profile = "${local.config_profile}"
}
EOF
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"

  contents = <<EOF
terraform {
  backend "local" {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}
EOF
}

inputs = {
  compartment_id     = local.compartment_id
  region             = local.region
  tenancy_id         = local.tenancy_id
  ssh_public_key     = local.ssh_public_key
  kubernetes_version = local.kubernetes_version
}
