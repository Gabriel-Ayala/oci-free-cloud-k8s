variable "compartment_id" {
  type        = string
  description = "Compartment where the cluster is created"
}

variable "cluster_name" {
  type        = string
  description = "Unique OKE cluster name"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_type" {
  type        = string
  description = "OKE cluster type"
  default     = "BASIC_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "cluster_type must be BASIC_CLUSTER or ENHANCED_CLUSTER."
  }
}

variable "region" {
  type        = string
  description = "OCI region"
}

variable "vcn_id" {
  type        = string
  description = "Cluster VCN OCID"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet OCID for the API endpoint and load balancers"
}

variable "private_subnet_id" {
  type        = string
  description = "Private subnet OCID for worker nodes"
}

variable "pods_cidr" {
  type        = string
  description = "Unique Kubernetes pod CIDR"
}

variable "services_cidr" {
  type        = string
  description = "Unique Kubernetes service CIDR"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path where kubeconfig is written"
}

variable "worker_availability_domains" {
  type        = list(string)
  description = "Availability domains for worker placement; empty selects all"
  default     = []
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "v1.33.1"
}

variable "kubernetes_worker_nodes" {
  type        = number
  description = "Worker node count"
  default     = 2
}

variable "worker_ocpus" {
  type        = number
  description = "OCPUs per worker node"
  default     = 1
}

variable "worker_memory_in_gbs" {
  type        = number
  description = "Memory per worker node in GiB"
  default     = 6
}

variable "worker_shape" {
  type        = string
  description = "OCI compute shape for worker nodes"
  default     = "VM.Standard.A1.Flex"
}

variable "worker_image_pattern" {
  type        = string
  description = "Regular expression fragment used to select the worker image"
  default     = "aarch"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key used for worker nodes"
}
