variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
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
  description = "OCI Vault OIDC"
  type        = string
  default     = ""
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
