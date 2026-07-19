terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }

    kubectl = {
      source = "gavinbunney/kubectl"
    }

    tls = {
      source = "hashicorp/tls"
    }
  }
}
