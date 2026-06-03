###############################################################################
# locals.tf - Construye el mapa de clusteres a partir de variables planas.
###############################################################################

locals {
  cluster_defaults = {
    presnet = {
      display_name    = "cluster-presnet"
      nodes_cidr      = "10.0.10.0/24"
      api_cidr        = "10.0.11.0/24"
      lb_cidr         = "10.0.12.0/24"
      lb_public       = true
      lb_ingress_cidr = "0.0.0.0/0"
      pool1_name      = "front"
      pool2_name      = "back-apis"
    }
    termed = {
      display_name    = "cluster-termed"
      nodes_cidr      = "10.0.20.0/24"
      api_cidr        = "10.0.21.0/24"
      lb_cidr         = "10.0.22.0/24"
      lb_public       = true
      lb_ingress_cidr = "0.0.0.0/0"
      pool1_name      = "front"
      pool2_name      = "back-apis"
    }
    mongodb = {
      display_name    = "cluster-mongodb"
      nodes_cidr      = "10.0.30.0/24"
      api_cidr        = "10.0.31.0/24"
      lb_cidr         = "10.0.32.0/24"
      lb_public       = false
      lb_ingress_cidr = "10.0.0.0/16"
      pool1_name      = "db"
      pool2_name      = "db-io"
    }
  }

  cluster_inputs = {
    presnet = {
      enabled    = var.presnet_enabled
      ocpus      = var.presnet_node_ocpus
      memory     = var.presnet_node_memory_gbs
      pool1_size = var.presnet_pool1_size
      pool2_size = var.presnet_pool2_size
    }
    termed = {
      enabled    = var.termed_enabled
      ocpus      = var.termed_node_ocpus
      memory     = var.termed_node_memory_gbs
      pool1_size = var.termed_pool1_size
      pool2_size = var.termed_pool2_size
    }
    mongodb = {
      enabled    = var.mongodb_enabled
      ocpus      = var.mongodb_node_ocpus
      memory     = var.mongodb_node_memory_gbs
      pool1_size = var.mongodb_pool1_size
      pool2_size = var.mongodb_pool2_size
    }
  }

  clusters = {
    for k, d in local.cluster_defaults : k => {
      display_name    = d.display_name
      nodes_cidr      = d.nodes_cidr
      api_cidr        = d.api_cidr
      lb_cidr         = d.lb_cidr
      lb_public       = d.lb_public
      lb_ingress_cidr = d.lb_ingress_cidr
      node_shape      = var.node_shape
      node_ocpus      = local.cluster_inputs[k].ocpus
      node_memory_gbs = local.cluster_inputs[k].memory
      node_pools = {
        (d.pool1_name) = { size = local.cluster_inputs[k].pool1_size }
        (d.pool2_name) = { size = local.cluster_inputs[k].pool2_size }
      }
    } if local.cluster_inputs[k].enabled
  }

  node_pools = merge([
    for ck, cv in local.clusters : {
      for pk, pv in cv.node_pools :
      "${ck}-${pk}" => {
        cluster         = ck
        pool_name       = pk
        size            = pv.size
        node_shape      = cv.node_shape
        node_ocpus      = cv.node_ocpus
        node_memory_gbs = cv.node_memory_gbs
      }
    }
  ]...)
}
