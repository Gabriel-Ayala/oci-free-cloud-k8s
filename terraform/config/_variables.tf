variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "cluster_name" {
  description = "Name of the OKE cluster being configured"
  type        = string
  default     = "k8s-cluster"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig for this cluster"
  type        = string
  default     = "../.kube.config"
}

variable "region" {
  description = "OCI region"
  type        = string

  default = "eu-frankfurt-1"
}

variable "public_subnet_id" {
  type        = string
  description = "The public subnet's OCID"
  default     = ""
}

variable "node_pool_id" {
  description = "The OCID of the Node Pool where the compute instances reside"
  type        = string
  default     = ""
}

variable "vault_id" {
  description = "OCID of the OCI Vault used by External Secrets"
  type        = string
  default     = ""
}

variable "vault_key_id" {
  description = "OCID of the KMS key used by an existing OCI Vault"
  type        = string
  default     = ""
}

variable "create_external_secrets_vault" {
  description = "Create a software-protected OCI Vault when vault_id is empty"
  type        = bool
  default     = false
}

variable "cluster_id" {
  description = "OCID of the OKE cluster, used by the workload identity policy"
  type        = string
  default     = ""
}

variable "external_secrets_principal_type" {
  description = "OCI authentication principal used by External Secrets"
  type        = string
  default     = "Workload"

  validation {
    condition     = contains(["Workload", "InstancePrincipal"], var.external_secrets_principal_type)
    error_message = "external_secrets_principal_type must be Workload or InstancePrincipal."
  }
}

variable "tenancy_id" {
  description = "Tenancy OCID"
  type        = string
  default     = ""
}

variable "gh_token" {
  description = "Github PAT for FluxCD"
  type        = string
  default     = ""
}

variable "github_app_id" {
  description = "GitHub App ID"
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID"
  type        = string
  default     = ""
}

variable "github_app_pem" {
  description = "The contents of the GitHub App private key PEM file"
  sensitive   = true
  type        = string
  default     = ""
}

variable "git_url" {
  description = "Git repository Flux should synchronize"
  type        = string
  default     = "https://github.com/Gabriel-Ayala/oci-free-cloud-k8s.git"
}

variable "gitops_path" {
  description = "Repository path synchronized by Flux for this cluster"
  type        = string
  default     = "gitops/core"
}

variable "gh_org" {
  description = "GitHub organization or user"
  type        = string
  default     = "Gabriel-Ayala"
}

variable "gh_repository" {
  description = "GitHub repository name"
  type        = string
  default     = "oci-free-cloud-k8s"
}

variable "git_auth_enabled" {
  description = "Use GitHub App authentication for Flux"
  type        = bool
  default     = false
}

variable "enable_github_webhook" {
  description = "Create the GitHub webhook and Vault token"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Create the OCI Vault-backed External Secrets integration"
  type        = bool
  default     = false
}

variable "enable_keycloak" {
  description = "Generate and store the tools Keycloak bootstrap admin password in OCI Vault"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_keycloak || var.enable_external_secrets
    error_message = "enable_keycloak requires enable_external_secrets so the bootstrap password can be stored in OCI Vault."
  }
}

variable "enable_mariadb" {
  description = "Generate and store the MariaDB root password in OCI Vault"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_mariadb || var.enable_external_secrets
    error_message = "enable_mariadb requires enable_external_secrets so the root password can be stored in OCI Vault."
  }
}

variable "enable_ingress" {
  description = "Create OCI load-balancer integration resources"
  type        = bool
  default     = false
}

variable "enable_grafana_iam" {
  description = "Create Grafana OCI monitoring IAM resources"
  type        = bool
  default     = false
}

variable "enable_longhorn_backup" {
  description = "Create the OCI Object Storage backup target and Vault credentials for Longhorn"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_longhorn_backup || var.enable_external_secrets
    error_message = "enable_longhorn_backup requires enable_external_secrets so its credentials can be stored in OCI Vault."
  }
}

variable "enable_mimir_storage" {
  description = "Create the dedicated OCI Object Storage bucket and Vault credentials for Mimir"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_mimir_storage || var.enable_external_secrets
    error_message = "enable_mimir_storage requires enable_external_secrets so its credentials can be stored in OCI Vault."
  }
}

variable "mimir_storage_bucket_name" {
  description = "Private OCI Object Storage bucket used by Mimir"
  type        = string
  default     = "oke-mimir-metrics"
}

variable "mimir_storage_user_email" {
  description = "Primary email required for the dedicated OCI IAM user used by Mimir"
  type        = string
  default     = ""
}

variable "private_subnet_id" {
  description = "Private subnet OCID used by the internal Mimir load balancer"
  type        = string
  default     = ""
}

variable "mimir_private_ip_id" {
  description = "Reserved private IP OCID assigned to the internal Mimir load balancer"
  type        = string
  default     = ""
}

variable "mimir_private_ip_address" {
  description = "Reserved private IP address assigned to the internal Mimir load balancer"
  type        = string
  default     = ""
}

variable "longhorn_backup_bucket_name" {
  description = "Private OCI Object Storage bucket used by Longhorn backups"
  type        = string
  default     = "oke-longhorn-backups"
}

variable "longhorn_backup_user_email" {
  description = "Primary email required for the dedicated OCI IAM user used by Longhorn backups"
  type        = string
  default     = ""
}
