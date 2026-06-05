# Okorum — OKE en OCI (Terraform + Resource Manager)

Despliegue de una **VCN** y **3 clusteres OKE Enhanced** (PresNet, TerMed, MongoDB) en OCI — **POC Okorum: región `sa-bogota-1` (Colombia)** —, con patrón de red **Flannel CNI + API endpoint privado + worker nodes privados + Load Balancer** (Ejemplo 2 de la documentación oficial de OKE).

Todo está parametrizado: región, compartment (crear o existente), shape, OCPUs, RAM, número de nodos, CIDRs y versión de Kubernetes — desde un **formulario one-click** (Resource Manager) o desde `terraform.tfvars` (CLI).

---

## Opción 1 — One-click deploy (Resource Manager)

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/jesmonsa/okorum-oke-iac/archive/refs/heads/main.zip)

1. **Sitúate en la región Colombia Central (Bogotá)** en la consola (esquina superior derecha) y haz clic en el botón. OCI abre Resource Manager con el formulario de `schema.yaml`: región (preseleccionada `sa-bogota-1`), compartment (crear o existente), shape, OCPUs, RAM, número de nodos, Bastion y qué clústeres desplegar.
2. Revisa el **Plan** y ejecuta **Apply**.

Alternativa sin botón: Consola OCI → **Developer Services → Resource Manager → Stacks → Create Stack → Source: Source Code Control** → conectas este repo.

---

## Opción 2 — CLI local

```bash
cp terraform.tfvars.example terraform.tfvars
#    edita terraform.tfvars (region, compartment, etc.)

terraform init
terraform plan
terraform apply
```

Autenticación local: usa tu `~/.oci/config` (perfil DEFAULT) o variables `OCI_*`.

Acceso al clúster (API privada): el stack crea un **OCI Bastion** (`create_bastion = true`). Para `kubectl`:

```bash
oci ce cluster create-kubeconfig --cluster-id <OCID_CLUSTER> \
  --file $HOME/.kube/config --region sa-bogota-1 --token-version 2.0.0

oci bastion session create-port-forwarding \
  --bastion-id <BASTION_OCID> --target-private-ip <IP_PRIVADA_API> \
  --target-port 6443 --session-ttl 10800 --key-file ~/.ssh/id_rsa.pub

kubectl get nodes
```

Alternativa: **OCI Cloud Shell** con acceso privado, sin túnel.

---

## Estructura

| Archivo | Contenido |
|---------|-----------|
| `provider.tf` | Provider OCI (version fijada ~> 8.16) + backend remoto opcional |
| `compartment.tf` | Crea el compartment (opcional) o usa uno existente |
| `variables.tf` | Variables planas (las consume el formulario) |
| `locals.tf` | Construye el mapa de clústeres desde las variables planas |
| `network.tf` | VCN, IGW/NAT/Service GW, subredes, route tables, security lists (Ejemplo 2) |
| `bastion.tf` | OCI Bastion + subred dedicada (acceso a los API endpoints privados) |
| `oke.tf` | Clústeres OKE (Enhanced, Flannel, API privada) + node pools |
| `outputs.tf` | OCIDs de VCN, clústeres, node pools y subredes |
| `schema.yaml` | Formulario one-click de Resource Manager |
| `terraform.tfvars.example` | Plantilla de variables para CLI |
| `manifests/mongodb-oke.yaml` | Workload de MongoDB para validar la plataforma (kubectl) |
| `.github/workflows/terraform.yml` | CI: `fmt` + `validate` en cada push/PR |

---

## Parámetros principales (formulario / tfvars)

| Parámetro | Default | Notas |
|-----------|---------|-------|
| `region` | `sa-bogota-1` | **POC Okorum: Colombia (Bogotá)**. Debe coincidir con la región de la consola |
| `create_compartment` | `false` | `true` = Terraform crea el compartment |
| `compartment_name` | `okorum-poc` | Nombre del compartment si se crea |
| `parent_compartment_ocid` | "" | Padre del compartment (seleccionarlo siempre al crear) |
| `compartment_ocid` | "" | Compartment existente (si `create_compartment=false`) |
| `availability_domains_csv` | "" | ADs separados por coma (Bogotá: `xxxx:SA-BOGOTA-1-AD-1`) |
| `node_shape` | `VM.Standard.E6.Flex` | E6/E5/E4/A1 Flex |
| `kubernetes_version` | última soportada | Vacío = la más nueva de OKE |
| `<cluster>_enabled` | `true` | Desplegar o no cada clúster |
| `<cluster>_node_ocpus` | 1 (Mongo 2) | OCPUs por nodo |
| `<cluster>_node_memory_gbs` | 8 (Mongo **16**) | RAM por nodo — 16 GB en BD por recomendación oficial de MongoDB |
| `<cluster>_pool1_size` / `pool2_size` | 2 / 2 | Nodos por pool |

Topología fija (CIDRs, nombres, LB público/privado) en `locals.tf` → `cluster_defaults`.

---

## Topología desplegada

| Clúster | Nodes | API | LB | Pools | OCPU total |
|---------|-------|-----|----|----|----|
| PresNet | `10.0.10.0/24` | `10.0.11.0/24` | `10.0.12.0/24` (público) | front(2)+back-apis(2) | 4 |
| TerMed  | `10.0.20.0/24` | `10.0.21.0/24` | `10.0.22.0/24` (público) | front(2)+back-apis(2) | 4 |
| MongoDB | `10.0.30.0/24` | `10.0.31.0/24` | `10.0.32.0/24` (privado) | db(2)+db-io(2) · **16 GB RAM/nodo** | 8 |

---

## Prerrequisitos del fabricante MongoDB (sesión 05-jun-2026)

El despliegue productivo del motor lo realiza el equipo de **MongoDB (Enterprise Advanced v8.2 + Ops Manager)**. Para su engagement, esta plataforma debe entregar — y este stack ya lo cubre o lo deja preparado:

| Prerrequisito de MongoDB | Cómo lo cubre este stack |
|--------------------------|--------------------------|
| Entorno K8s correctamente configurado | 3 clústeres OKE Enhanced con red del Ejemplo 2, API privada y última versión de Kubernetes ✅ |
| Clases de volumen de alto desempeño | StorageClass `oci-bv-retain` con `vpusPerGB: 20` (Higher Performance) y 500 GB por réplica ✅ |
| **16 GB de RAM** en los nodos de BD | Default `mongodb_node_memory_gbs = 16` (recomendación oficial; los agentes de Ops Manager consumen 3-5 GB) ✅ |
| Certificados TLS x509 para firmar cada nodo | Definir con el cliente: emisión vía cert-manager en el clúster o CA corporativa. Coordinar las llaves TLS por dominio |
| Políticas de respaldo, autenticación y logging documentadas | Responsabilidad del cliente antes del engagement; el CronJob de backup del manifiesto sirve como base |

---

## Antes de ejecutar — checklist

1. **Service limit de E6.** Se necesitan **16 OCPUs** `VM.Standard.E6.Flex` en `sa-bogota-1`. Verifica/solicita el aumento antes de ejecutar (fue un bloqueador en pruebas tempranas del proyecto).
2. **Compartment.** Puedes crearlo (`create_compartment = true`) o usar uno existente (`compartment_ocid`). Crear compartment requiere permiso *manage compartments* en el padre/tenancy. Nota: al hacer `destroy`, OCI tarda en eliminar el compartment (queda en estado "deleting").
3. **Región y AD.** La POC de Okorum se despliega en **`sa-bogota-1` (Colombia)**, que tiene **1 Availability Domain** (`xxxx:SA-BOGOTA-1-AD-1`): los 12 nodos quedan en ese AD distribuidos automáticamente entre *fault domains*. El código sigue siendo multi-región para otros ambientes (`availability_domains_csv` para fijar ADs manualmente).
4. **Versión de K8s.** Si dejas `kubernetes_version=""` toma la última; revisa el output `node_image_id`. Si queda vacío, pasa `node_image_id` manualmente.
5. **MongoDB sobre OKE.** La BD corre como workload en `cluster-mongodb`. Este Terraform crea la infraestructura; para validar la plataforma se aplica `manifests/mongodb-oke.yaml` (StatefulSet ReplicaSet de 3 miembros + Block Volume CSI de alto desempeño + LB interno + backup) desde Bastion/Cloud Shell:

```bash
kubectl apply -f manifests/mongodb-oke.yaml
```
