variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "region" {
  description = "OCI region"
  type        = string

  default = "eu-frankfurt-1"
}

variable "ssh_public_key" {
  description = "SSH Public Key used to access all instances"
  type        = string

  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBPjsPbPbEsCywcFfS24iBUV1ISMM+5Yk0eqWuaNSP8YqjgPkJU5K62Pm8tRYUpfoP2mkF5zdT3Zj+6kMtqxkACcvQDui71PzIVQx57AE4wcvsEYXqLYNpvHl/YEdf7fCNvsXounnJjYSHbjRPjTcq+34CgedCVFL5MYXpdRmc5Kl1Do8JscYm5AzVOhfRJJ0Fiqd4bkRMpJN5zYZ+NYw/cnSKFckSTsG4pSbcSCoR1wPNRU6rEPXSQa2hFZPpYORuxKcwua/bb3aRzyU1fT7xdjzkDs++0rQJQ461kvBjsYgD5Zuwgl3MkzouVx2p5ic1dU34kQTrWpH3z5diRut7 ull@rsa"
}

variable "kubernetes_version" {
  # https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutk8sversions.htm
  description = "Version of Kubernetes"
  type        = string

  default = "v1.33.1"
}

variable "kubernetes_worker_nodes" {
  description = "Worker node count"
  type        = number

  default = 2
}

variable "worker_ocpus" {
  description = "OCPUs per worker node"
  type        = number
  default     = 1
}

variable "worker_memory_in_gbs" {
  description = "Memory per worker node in GiB"
  type        = number
  default     = 6
}

variable "worker_shape" {
  description = "OCI compute shape for worker nodes"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "worker_image_pattern" {
  description = "Regular-expression fragment used to select the worker image"
  type        = string
  default     = "aarch"
}
