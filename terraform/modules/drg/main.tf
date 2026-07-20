terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.32.0"
    }
  }
}

resource "oci_core_drg" "this" {
  compartment_id = var.compartment_id
  display_name   = var.name
}
