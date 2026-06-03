###############################################################################
# outputs.tf
###############################################################################

output "vcn_id" {
  description = "OCID de la VCN."
  value       = oci_core_vcn.this.id
}

output "kubernetes_version" {
  description = "Version de Kubernetes usada."
  value       = local.k8s_version
}

output "node_image_id" {
  description = "Imagen seleccionada para los worker nodes."
  value       = local.oke_image_id
}

output "clusters" {
  description = "OCID de cada cluster OKE creado."
  value       = { for k, c in oci_containerengine_cluster.this : k => c.id }
}

output "node_pools" {
  description = "OCID de cada node pool creado."
  value       = { for k, np in oci_containerengine_node_pool.this : k => np.id }
}

output "bastion_id" {
  description = "OCID del OCI Bastion (si se creó)."
  value       = var.create_bastion ? oci_bastion_bastion.this[0].id : null
}

output "subnets" {
  description = "OCID de las subredes por cluster."
  value = {
    for k in keys(local.clusters) : k => {
      nodes = oci_core_subnet.nodes[k].id
      api   = oci_core_subnet.api[k].id
      lb    = oci_core_subnet.lb[k].id
    }
  }
}
