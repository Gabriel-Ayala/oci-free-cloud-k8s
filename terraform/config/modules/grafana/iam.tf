# https://github.com/oracle/oci-grafana-metrics/blob/master/docs/kubernetes.md

resource "oci_identity_dynamic_group" "grafana_instances" {
  #Required
  compartment_id = var.compartment_id
  description    = "Grafana Monitoring"
  name           = "Grafana-tools"

  # all instances
  matching_rule = "All {instance.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "grafana" {
  #Required
  compartment_id = var.compartment_id
  description    = "allow metrics"
  name           = "Monitoring-tools"
  statements = [
    "Allow dynamic-group Grafana-tools to read metrics in tenancy",
    "Allow dynamic-group Grafana-tools to read compartments in tenancy"
  ]
}
