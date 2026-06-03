###############################################################################
# Okorum - OKE en OCI (sa-bogota-1)
# provider.tf
#
# Autenticacion:
#  - Resource Manager (one-click): la maneja automaticamente la sesion. No pide claves.
#  - CLI local: usa tu ~/.oci/config (perfil DEFAULT) o variables de entorno OCI_*.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.16" # fijada para evitar deriva de version entre corridas
    }
  }

  # -------------------------------------------------------------------------
  # (Opcional, recomendado para equipos) Estado remoto en OCI Object Storage.
  # -------------------------------------------------------------------------
  # backend "s3" {
  #   bucket                      = "okorum-tfstate"
  #   key                         = "okorum/poc/terraform.tfstate"
  #   region                      = "sa-bogota-1"
  #   endpoints                   = { s3 = "https://<NAMESPACE>.compat.objectstorage.sa-bogota-1.oraclecloud.com" }
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  # }
}

provider "oci" {
  region = var.region
}
