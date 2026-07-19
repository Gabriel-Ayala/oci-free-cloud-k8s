terraform {

  required_providers {

    oci = {
      source = "oracle/oci"
    }

    flux = {
      source = "fluxcd/flux"
    }

    helm = {
      source = "hashicorp/helm"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }

    random = {
      source = "hashicorp/random"
    }

    github = {
      source  = "integrations/github"
      version = ">= 5.18.0"
    }
  }
}
