###############################################################################
# oke.tf - Clusteres OKE (Enhanced, Flannel, API privada) + node pools
###############################################################################

locals {
  # Compartment para listar ADs (debe ser conocido en tiempo de plan).
  # PRIORIDAD: compartment del usuario PRIMERO y tenancy de ULTIMO, porque en
  # tenancies con IAM restrictivo listar ADs contra la raiz devuelve null
  # (OCI filtra resultados sin error si no hay permiso a nivel tenancy).
  ad_compartment_id = var.compartment_ocid != "" ? var.compartment_ocid : (var.parent_compartment_ocid != "" ? var.parent_compartment_ocid : var.tenancy_ocid)
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.ad_compartment_id

  lifecycle {
    precondition {
      condition     = local.ad_compartment_id != ""
      error_message = "Para listar los Availability Domains proporciona tenancy_ocid, compartment_ocid o parent_compartment_ocid (al menos uno no vacio)."
    }
  }
}

data "oci_containerengine_cluster_option" "this" {
  cluster_option_id = "all"
}

data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = local.compartment_id
}

locals {
  k8s_versions = data.oci_containerengine_cluster_option.this.kubernetes_versions

  k8s_version = var.kubernetes_version != "" ? var.kubernetes_version : element(local.k8s_versions, length(local.k8s_versions) - 1)

  k8s_version_num = replace(local.k8s_version, "v", "")

  _matching_images = [
    for s in data.oci_containerengine_node_pool_option.this.sources : s.image_id
    if length(regexall("Oracle-Linux-8", s.source_name)) > 0
    && length(regexall("OKE-${local.k8s_version_num}", s.source_name)) > 0
    && length(regexall("aarch64|GPU", s.source_name)) == 0
  ]

  oke_image_id = var.node_image_id != "" ? var.node_image_id : (length(local._matching_images) > 0 ? local._matching_images[0] : "")

  # AD a usar, en orden de prioridad:
  # 1. var.availability_domains (lista, para tfvars/CLI)
  # 2. var.availability_domains_csv (string separado por coma, para el formulario RM)
  # 3. Deteccion automatica via data source (coalesce evita crash si llega null;
  #    la precondition del node pool valida y reporta el compartment usado).
  ad_names = length(var.availability_domains) > 0 ? var.availability_domains : (
    trimspace(var.availability_domains_csv) != "" ? [for s in split(",", var.availability_domains_csv) : trimspace(s)] :
    [for ad in coalesce(data.oci_identity_availability_domains.ads.availability_domains, []) : ad.name]
  )
}

resource "oci_containerengine_cluster" "this" {
  for_each = local.clusters

  compartment_id     = local.compartment_id
  name               = each.value.display_name
  vcn_id             = oci_core_vcn.this.id
  kubernetes_version = local.k8s_version
  type               = "ENHANCED_CLUSTER"
  freeform_tags      = var.freeform_tags

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  endpoint_config {
    subnet_id            = oci_core_subnet.api[each.key].id
    is_public_ip_enabled = false
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.lb[each.key].id]
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }
}

resource "oci_containerengine_node_pool" "this" {
  for_each = local.node_pools

  lifecycle {
    precondition {
      condition     = length(local.ad_names) > 0
      error_message = "No se pudieron listar los Availability Domains usando el compartment '${local.ad_compartment_id}'. Causas tipicas: permisos IAM insuficientes en ese compartment, o valor vacio. Solucion: usa el campo 'Availability Domains manuales' del formulario (oci iam availability-domain list), o verifica permisos."
    }
  }

  cluster_id         = oci_containerengine_cluster.this[each.value.cluster].id
  compartment_id     = local.compartment_id
  name               = "${each.value.cluster}-${each.value.pool_name}"
  kubernetes_version = local.k8s_version
  node_shape         = each.value.node_shape
  ssh_public_key     = var.node_ssh_public_key != "" ? var.node_ssh_public_key : null
  freeform_tags      = var.freeform_tags

  node_shape_config {
    ocpus         = each.value.node_ocpus
    memory_in_gbs = each.value.node_memory_gbs
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = local.oke_image_id
  }

  node_config_details {
    size = each.value.size

    dynamic "placement_configs" {
      for_each = local.ad_names
      content {
        availability_domain = placement_configs.value
        subnet_id           = oci_core_subnet.nodes[each.value.cluster].id
      }
    }
  }

  initial_node_labels {
    key   = "pool"
    value = each.value.pool_name
  }
}
