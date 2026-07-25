variable "compartment_id" {
  type        = string
  description = "Compartment where GitLab resources are created"
}

variable "region" {
  type        = string
  description = "OCI region"
}

variable "subnet_id" {
  type        = string
  description = "Public subnet for the GitLab VM"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on the VM"
}

variable "hostname" {
  type        = string
  description = "GitLab VM hostname label"
  default     = "gitlab"
}

variable "external_url" {
  type        = string
  description = "Public GitLab URL"
  default     = "https://gitlab.amedsaude.com.br"
}

variable "shape" {
  type        = string
  description = "OCI compute shape"
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  type        = number
  description = "OCPUs for flexible shapes"
  default     = 4
}

variable "memory_in_gbs" {
  type        = number
  description = "Memory in GiB for flexible shapes"
  default     = 16
}

variable "boot_volume_size_in_gbs" {
  type        = number
  description = "Boot volume size"
  default     = 60
}

variable "data_volume_size_in_gbs" {
  type        = number
  description = "Persistent GitLab data volume size"
  default     = 200
}

variable "gitlab_package_version" {
  type        = string
  description = "Optional exact gitlab-ce package version"
  default     = ""
}
