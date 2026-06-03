###############################################################################
# network.tf - VCN, gateways, subredes, route tables y security lists
# Patron por cluster: Flannel + API privada + workers privados + LB (Ejemplo 2)
###############################################################################

# Servicio "All <region> Services" para el Service Gateway
data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  service_cidr = data.oci_core_services.all_services.services[0].cidr_block
  service_id   = data.oci_core_services.all_services.services[0].id
}

# ----------------------------------------------------------------------------
# VCN + gateways compartidos
# ----------------------------------------------------------------------------
resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = var.vcn_name
  dns_label      = var.vcn_dns_label
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_nat_gateway" "natgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-natgw"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-sgw"
  services {
    service_id = local.service_id
  }
  freeform_tags = var.freeform_tags
}

# ----------------------------------------------------------------------------
# Route tables (una por subred, por cluster)
# ----------------------------------------------------------------------------

# Workers (privada): NAT + Service Gateway
resource "oci_core_route_table" "nodes" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-${each.key}-nodes"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.natgw.id
    description       = "Salida a internet via NAT"
  }
  route_rules {
    destination       = local.service_cidr
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
    description       = "Acceso a servicios OCI via Service Gateway"
  }
}

# API endpoint (privada): NAT + Service Gateway
resource "oci_core_route_table" "api" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-${each.key}-api"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.natgw.id
    description       = "Salida a internet via NAT"
  }
  route_rules {
    destination       = local.service_cidr
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
    description       = "Acceso a servicios OCI via Service Gateway"
  }
}

# Load balancers: si lb_public -> Internet Gateway; si privado -> Service Gateway
resource "oci_core_route_table" "lb" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "rt-${each.key}-lb"
  freeform_tags  = var.freeform_tags

  dynamic "route_rules" {
    for_each = each.value.lb_public ? [1] : []
    content {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.igw.id
      description       = "LB publico hacia internet"
    }
  }

  dynamic "route_rules" {
    for_each = each.value.lb_public ? [] : [1]
    content {
      destination       = local.service_cidr
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.sgw.id
      description       = "LB privado: solo servicios OCI"
    }
  }
}

# ----------------------------------------------------------------------------
# Security lists (Ejemplo 2 de la doc oficial), por cluster
# ----------------------------------------------------------------------------

# --- API endpoint ---
resource "oci_core_security_list" "api" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "seclist-${each.key}-api"
  freeform_tags  = var.freeform_tags

  ingress_security_rules {
    protocol    = "6"
    source      = each.value.nodes_cidr
    description = "Worker a API endpoint (6443)"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  ingress_security_rules {
    protocol    = "6"
    source      = each.value.nodes_cidr
    description = "Worker a control plane (12250)"
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  ingress_security_rules {
    protocol    = "1"
    source      = each.value.nodes_cidr
    description = "Path discovery"
    icmp_options {
      type = 3
      code = 4
    }
  }
  dynamic "ingress_security_rules" {
    for_each = var.create_bastion ? [1] : []
    content {
      protocol    = "6"
      source      = var.bastion_subnet_cidr
      description = "Bastion a API endpoint (6443)"
      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  egress_security_rules {
    protocol         = "6"
    destination      = local.service_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    description      = "Control plane a OKE/OCI"
  }
  egress_security_rules {
    protocol         = "1"
    destination      = local.service_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    description      = "Path discovery a servicios OCI"
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = each.value.nodes_cidr
    description = "Control plane a workers"
  }
  egress_security_rules {
    protocol    = "1"
    destination = each.value.nodes_cidr
    description = "Path discovery a workers"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

# --- Worker nodes ---
resource "oci_core_security_list" "nodes" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "seclist-${each.key}-nodes"
  freeform_tags  = var.freeform_tags

  ingress_security_rules {
    protocol    = "all"
    source      = each.value.nodes_cidr
    description = "Pod a pod entre nodos"
  }
  ingress_security_rules {
    protocol    = "6"
    source      = each.value.api_cidr
    description = "Control plane a workers"
  }
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    description = "Path discovery"
    icmp_options {
      type = 3
      code = 4
    }
  }
  ingress_security_rules {
    protocol    = "6"
    source      = each.value.lb_cidr
    description = "LB a NodePorts"
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  ingress_security_rules {
    protocol    = "6"
    source      = each.value.lb_cidr
    description = "LB a kube-proxy (health)"
    tcp_options {
      min = 10256
      max = 10256
    }
  }
  dynamic "ingress_security_rules" {
    for_each = var.create_bastion ? [1] : []
    content {
      protocol    = "6"
      source      = var.bastion_subnet_cidr
      description = "Bastion SSH a workers"
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = each.value.nodes_cidr
    description = "Pod a pod entre nodos"
  }
  egress_security_rules {
    protocol         = "6"
    destination      = local.service_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    description      = "Workers a OKE/OCI"
  }
  egress_security_rules {
    protocol    = "6"
    destination = each.value.api_cidr
    description = "Worker a API endpoint (6443)"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = each.value.api_cidr
    description = "Worker a control plane (12250)"
    tcp_options {
      min = 12250
      max = 12250
    }
  }
  egress_security_rules {
    protocol    = "1"
    destination = "0.0.0.0/0"
    description = "Path discovery"
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
    description = "Salida workers a internet via NAT"
  }
}

# --- Load balancers ---
resource "oci_core_security_list" "lb" {
  for_each       = local.clusters
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "seclist-${each.key}-lb"
  freeform_tags  = var.freeform_tags

  ingress_security_rules {
    protocol    = "6"
    source      = each.value.lb_ingress_cidr
    description = "HTTPS"
    tcp_options {
      min = 443
      max = 443
    }
  }
  ingress_security_rules {
    protocol    = "6"
    source      = each.value.lb_ingress_cidr
    description = "HTTP"
    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    protocol    = "6"
    destination = each.value.nodes_cidr
    description = "LB a NodePorts"
    tcp_options {
      min = 30000
      max = 32767
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = each.value.nodes_cidr
    description = "LB a kube-proxy (health)"
    tcp_options {
      min = 10256
      max = 10256
    }
  }
}

# ----------------------------------------------------------------------------
# Subredes (regionales)
# ----------------------------------------------------------------------------
resource "oci_core_subnet" "nodes" {
  for_each                   = local.clusters
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = each.value.nodes_cidr
  display_name               = "private_${each.key}_nodes"
  dns_label                  = "${each.key}nodes"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.nodes[each.key].id
  security_list_ids          = [oci_core_security_list.nodes[each.key].id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  freeform_tags              = var.freeform_tags
}

resource "oci_core_subnet" "api" {
  for_each                   = local.clusters
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = each.value.api_cidr
  display_name               = "private_${each.key}_api"
  dns_label                  = "${each.key}api"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.api[each.key].id
  security_list_ids          = [oci_core_security_list.api[each.key].id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  freeform_tags              = var.freeform_tags
}

resource "oci_core_subnet" "lb" {
  for_each                   = local.clusters
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = each.value.lb_cidr
  display_name               = each.value.lb_public ? "public_${each.key}_lb" : "private_${each.key}_lb"
  dns_label                  = "${each.key}lb"
  prohibit_public_ip_on_vnic = each.value.lb_public ? false : true
  route_table_id             = oci_core_route_table.lb[each.key].id
  security_list_ids          = [oci_core_security_list.lb[each.key].id]
  dhcp_options_id            = oci_core_vcn.this.default_dhcp_options_id
  freeform_tags              = var.freeform_tags
}
