data "oci_identity_availability_domains" "available" {
  compartment_id = var.compartment_id
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "gitlab" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.compartment_id
  display_name        = "gitlab"
  shape               = var.shape

  source_details {
    source_id               = data.oci_core_images.ubuntu.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  dynamic "shape_config" {
    for_each = can(regex("Flex$", var.shape)) ? [1] : []

    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_in_gbs
    }
  }

  create_vnic_details {
    assign_public_ip = true
    display_name     = "gitlab-vnic"
    subnet_id        = var.subnet_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/files/cloud-init.yaml", {
      external_url           = var.external_url
      gitlab_package_version = var.gitlab_package_version
    }))
  }

  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}

resource "oci_core_volume" "gitlab_data" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.compartment_id
  display_name        = "gitlab-data"
  size_in_gbs         = var.data_volume_size_in_gbs
  vpus_per_gb         = 10
}

resource "oci_core_volume_attachment" "gitlab_data" {
  attachment_type = "paravirtualized"
  device          = "/dev/oracleoci/oraclevdb"
  instance_id     = oci_core_instance.gitlab.id
  volume_id       = oci_core_volume.gitlab_data.id
}

data "oci_core_vnic_attachments" "gitlab" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.gitlab.id
}

data "oci_core_vnic" "gitlab" {
  vnic_id = data.oci_core_vnic_attachments.gitlab.vnic_attachments[0].vnic_id
}
