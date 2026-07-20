variable "compartment_id" {
  description = "Compartment where the DRG is created"
  type        = string
}

variable "name" {
  description = "DRG display name"
  type        = string
  default     = "oke-drg"
}
