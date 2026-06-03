###############################################################################
# bastion.tf - OCI Bastion (servicio gestionado) + subred dedicada
# Permite operar los API endpoints privados de OKE via sesiones port-forwarding.
# Se crea solo si var.create_bastion = true.
###############################################################################

resource "oci_core_route_table" "bastion" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-bastion"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.natgw.id
    description       = "Salida a internet via NAT (updates del plugin)"
  }
  route_rules {
    destination       = local.service_cidr
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
    description       = "Servicios OCI via Service Gateway"
  }
}

resource "oci_core_security_list" "bastion" {
  count          = var.create_bastion ? 1 : 0
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "seclist-bastion"
  freeform_tags  = var.freeform_tags

  egress_security_rules {
    protocol    = "all"
    destination = var.vcn_cidr
    description = "Bastion hacia recursos de la VCN"
  }
  egress_security_rules {
    protocol         = "6"
    destination      = local.service_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    description      = "Bastion hacia servicios OCI"
  }
}

resource "oci_core_subnet" "bastion" {
  count                      = var.create_bastion ? 1 : 0
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.bastion_subnet_cidr
  display_name               = "private_bastion"
  dns_label                  = "bastion"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.bastion[0].id
  security_list_ids          = [oci_core_security_list.bastion[0].id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  freeform_tags              = var.freeform_tags
}

resource "oci_bastion_bastion" "this" {
  count                        = var.create_bastion ? 1 : 0
  bastion_type                 = "STANDARD"
  compartment_id               = local.compartment_id
  target_subnet_id             = oci_core_subnet.bastion[0].id
  name                         = "okorum-bastion"
  client_cidr_block_allow_list = [var.bastion_client_cidr]
  freeform_tags                = var.freeform_tags
}
