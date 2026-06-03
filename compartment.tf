###############################################################################
# compartment.tf - Crea el compartment (opcional) o usa uno existente.
# Toda la infra referencia local.compartment_id.
###############################################################################

resource "oci_identity_compartment" "this" {
  count = var.create_compartment ? 1 : 0

  # Padre: si no se indica, se crea en la raiz del tenancy.
  compartment_id = var.parent_compartment_ocid != "" ? var.parent_compartment_ocid : var.tenancy_ocid
  name           = var.compartment_name
  description    = "Okorum POC - creado por Terraform"
  enable_delete  = true
  freeform_tags  = var.freeform_tags
}

locals {
  compartment_id = var.create_compartment ? oci_identity_compartment.this[0].id : var.compartment_ocid
}
