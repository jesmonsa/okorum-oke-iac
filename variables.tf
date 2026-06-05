###############################################################################
# variables.tf - Variables planas (las consume el formulario schema.yaml)
###############################################################################

# --- Provider -----------------------------------------------------------------
# tenancy_ocid y region: en Resource Manager se autocompletan; en CLI local
# se toman de tfvars o de tu ~/.oci/config.
variable "tenancy_ocid" {
  description = "OCID del tenancy. En Resource Manager se autocompleta; en CLI ponlo en tfvars."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region OCI de despliegue."
  type        = string
  default     = "sa-bogota-1"
}

variable "compartment_ocid" {
  description = "OCID del compartment destino (si create_compartment = false). Vacio si se crea uno nuevo."
  type        = string
  default     = ""
}

# --- Compartment (crear o usar existente) -------------------------------------
variable "create_compartment" {
  description = "Si true, Terraform crea el compartment; si false, usa compartment_ocid existente."
  type        = bool
  default     = false
}

variable "compartment_name" {
  description = "Nombre del compartment a crear (solo si create_compartment = true)."
  type        = string
  default     = "okorum-poc"
}

variable "parent_compartment_ocid" {
  description = "OCID del compartment padre donde crear el nuevo (vacio = raiz del tenancy)."
  type        = string
  default     = ""
}

# --- VCN ----------------------------------------------------------------------
variable "vcn_name" {
  description = "Nombre de la VCN."
  type        = string
  default     = "okorum-prod-vcn"
}

variable "vcn_cidr" {
  description = "CIDR de la VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  description = "DNS label de la VCN."
  type        = string
  default     = "okorumvcn"
}

# --- Compute / Kubernetes (globales) ------------------------------------------
variable "node_shape" {
  description = "Shape de los worker nodes (Flex)."
  type        = string
  default     = "VM.Standard.E6.Flex"
}

variable "kubernetes_version" {
  description = "Version de Kubernetes (vacio = ultima soportada)."
  type        = string
  default     = ""
}

variable "node_image_id" {
  description = "OCID de imagen de worker (vacio = se selecciona OL8 acorde a la version)."
  type        = string
  default     = ""
}

variable "node_ssh_public_key" {
  description = "Llave publica SSH para los nodos (opcional)."
  type        = string
  default     = ""
}

variable "availability_domains" {
  description = "Lista de nombres de AD a usar para los nodos (vacio = todos los AD de la region)."
  type        = list(string)
  default     = []
}

variable "availability_domains_csv" {
  description = "ADs separados por coma (alternativa manual para el formulario de Resource Manager). Ej: 'Pgjw:US-ASHBURN-AD-1,Pgjw:US-ASHBURN-AD-2'. Vacio = deteccion automatica."
  type        = string
  default     = ""
}

# --- Bastion (acceso al API endpoint privado) ---------------------------------
variable "create_bastion" {
  description = "Crear OCI Bastion para operar los endpoints privados con kubectl."
  type        = bool
  default     = true
}

variable "bastion_subnet_cidr" {
  description = "CIDR de la subred privada del Bastion."
  type        = string
  default     = "10.0.99.0/24"
}

variable "bastion_client_cidr" {
  description = "CIDR autorizado para iniciar sesiones de Bastion (idealmente tu IP/VPN, no 0.0.0.0/0)."
  type        = string
  default     = "0.0.0.0/0"
}

# --- Etiquetas ----------------------------------------------------------------
variable "freeform_tags" {
  description = "Freeform tags para todos los recursos."
  type        = map(string)
  default = {
    project = "okorum"
    env     = "poc"
  }
}

# --- Cluster PresNet ----------------------------------------------------------
variable "presnet_enabled" {
  type    = bool
  default = true
}
variable "presnet_node_ocpus" {
  type    = number
  default = 1
}
variable "presnet_node_memory_gbs" {
  type    = number
  default = 8
}
variable "presnet_pool1_size" {
  description = "Nodos del pool front."
  type        = number
  default     = 2
}
variable "presnet_pool2_size" {
  description = "Nodos del pool back-apis."
  type        = number
  default     = 2
}

# --- Cluster TerMed -----------------------------------------------------------
variable "termed_enabled" {
  type    = bool
  default = true
}
variable "termed_node_ocpus" {
  type    = number
  default = 1
}
variable "termed_node_memory_gbs" {
  type    = number
  default = 8
}
variable "termed_pool1_size" {
  description = "Nodos del pool front."
  type        = number
  default     = 2
}
variable "termed_pool2_size" {
  description = "Nodos del pool back-apis."
  type        = number
  default     = 2
}

# --- Cluster MongoDB ----------------------------------------------------------
variable "mongodb_enabled" {
  type    = bool
  default = true
}
variable "mongodb_node_ocpus" {
  type    = number
  default = 2
}
variable "mongodb_node_memory_gbs" {
  description = "RAM por nodo de BD. 16 GB por recomendacion oficial de MongoDB (sesion 05-jun-2026)."
  type        = number
  default     = 16
}
variable "mongodb_pool1_size" {
  description = "Nodos del pool db."
  type        = number
  default     = 2
}
variable "mongodb_pool2_size" {
  description = "Nodos del pool db-io."
  type        = number
  default     = 2
}
