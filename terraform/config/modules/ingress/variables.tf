variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "vcn_name" {
  description = "VCN display name used by ingress resources"
  type        = string
  default     = "k8s-vcn"
}
