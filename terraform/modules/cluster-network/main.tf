terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.32.0"
    }
  }
}

locals {
  vcn_dns_label = substr("${replace(var.cluster_name, "-", "")}vcn", 0, 15)

  drg_route_rules = [
    for cidr in var.peer_vcn_cidrs : {
      destination       = cidr
      destination_type  = "CIDR_BLOCK"
      network_entity_id = "drg"
      description       = "Route ${var.cluster_name} traffic to the DRG"
    }
  ]
}

module "vcn" {
  source  = "oracle-terraform-modules/vcn/oci"
  version = "3.6.0"

  compartment_id = var.compartment_id
  region         = var.region
  vcn_name       = "${var.cluster_name}-vcn"
  vcn_dns_label  = local.vcn_dns_label
  vcn_cidrs      = [var.vcn_cidr]

  attached_drg_id              = var.drg_id
  internet_gateway_route_rules = local.drg_route_rules
  nat_gateway_route_rules      = local.drg_route_rules
  local_peering_gateways       = null
  create_internet_gateway      = true
  create_nat_gateway           = true
  create_service_gateway       = true
}

resource "oci_core_drg_attachment" "this" {
  drg_id       = var.drg_id
  vcn_id       = module.vcn.vcn_id
  display_name = "${var.cluster_name}-drg-attachment"

  drg_route_table_id = var.drg_route_table_id
}

resource "oci_core_private_ip" "mimir" {
  count = var.reserve_mimir_private_ip ? 1 : 0

  display_name = "${var.cluster_name}-mimir-private-ip"
  ip_address   = trimspace(var.mimir_private_ip_address) != "" ? var.mimir_private_ip_address : null
  lifetime     = "RESERVED"
  subnet_id    = oci_core_subnet.private.id
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  display_name   = "${var.cluster_name}-private-subnet-sl"

  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = var.peer_vcn_cidrs

    content {
      stateless   = false
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "all"
    }
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  display_name   = "${var.cluster_name}-public-subnet-sl"

  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = var.peer_vcn_cidrs

    content {
      stateless   = false
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      protocol    = "all"
    }
  }

  ingress_security_rules {
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_security_list" "nlb_private" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  display_name   = "${var.cluster_name}-nlb-private-subnet-sl"

  ingress_security_rules {
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"

    tcp_options {
      min = 30000
      max = 32767
    }
  }
}

resource "oci_core_subnet" "private" {
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id
  cidr_block     = var.private_subnet_cidr
  route_table_id = module.vcn.nat_route_id

  security_list_ids = [
    oci_core_security_list.private.id,
    oci_core_security_list.nlb_private.id,
  ]

  display_name               = "${var.cluster_name}-private-subnet"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = module.vcn.vcn_id
  cidr_block        = var.public_subnet_cidr
  route_table_id    = module.vcn.ig_route_id
  security_list_ids = [oci_core_security_list.public.id]

  display_name = "${var.cluster_name}-public-subnet"
}
