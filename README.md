# Okorum — OKE en OCI (Terraform + Resource Manager)

Despliegue de una **VCN** y **3 clusteres OKE Enhanced** (PresNet, TerMed, MongoDB) en `sa-bogota-1`, con patrón de red **Flannel CNI + API endpoint privado + worker nodes privados + Load Balancer** (Ejemplo 2 de la documentación oficial de OKE).

Todo está parametrizado: shape, OCPUs, RAM, número de nodos, compartment, CIDRs y versión de Kubernetes se eligen por variables — desde un **formulario one-click** (Resource Manager) o desde `terraform.tfvars` (CLI).

---

## Opción 1 — One-click deploy (Resource Manager)

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/jesmonsa/okorum-oke-iac/archive/refs/heads/main.zip)

1. Haz clic en el botón. OCI abre Resource Manager con el formulario de `schema.yaml`: seleccionas **compartment**, **shape**, **OCPUs**, **RAM**, número de nodos, Bastion y qué clústeres desplegar.
2. Revisa el **Plan** y ejecuta **Apply**.

Alternativa sin botón: Consola OCI → **Developer Services → Resource Manager → Stacks → Create Stack → Source: Source Code Control** → conectas este repo de GitHub.

---

## Opción 2 — CLI local

```bash
# 1. Autentícate (usa ~/.oci/config perfil DEFAULT, o variables OCI_*)
# 2. Prepara variables
cp terraform.tfvars.example terraform.tfvars
#    edita terraform.tfvars con tu compartment_ocid, tenancy_ocid, etc.

terraform init
terraform plan
terraform apply
```

Acceso al clúster (API privada): el stack ya crea un **OCI Bastion** (`create_bastion = true`). Para operar `kubectl`:

```bash
# 1. Genera el kubeconfig
oci ce cluster create-kubeconfig --cluster-id <OCID_CLUSTER> \
  --file $HOME/.kube/config --region sa-bogota-1 --token-version 2.0.0

# 2. Crea una sesión de port-forwarding del Bastion al API endpoint privado (puerto 6443)
oci bastion session create-port-forwarding \
  --bastion-id <BASTION_OCID> \
  --target-private-ip <IP_PRIVADA_API_ENDPOINT> \
  --target-port 6443 \
  --session-ttl 10800 \
  --key-file ~/.ssh/id_rsa.pub

# 3. Abre el túnel SSH que entrega el comando anterior y luego:
kubectl get nodes
```

Alternativa: **OCI Cloud Shell** con acceso privado (private endpoint) sin necesidad de túnel.

---

## Estructura

| Archivo | Contenido |
|---------|-----------|
| `provider.tf` | Provider OCI + backend remoto opcional (Object Storage) |
| `variables.tf` | Variables planas (las consume el formulario) |
| `locals.tf` | Construye el mapa de clústeres desde las variables planas |
| `network.tf` | VCN, IGW/NAT/Service GW, subredes, route tables, security lists (Ejemplo 2) |
| `bastion.tf` | OCI Bastion + subred dedicada (acceso a los API endpoints privados) |
| `oke.tf` | Clústeres OKE (Enhanced, Flannel, API privada) + node pools |
| `outputs.tf` | OCIDs de VCN, clústeres, node pools y subredes |
| `schema.yaml` | Formulario one-click de Resource Manager |
| `terraform.tfvars.example` | Plantilla de variables para CLI |
| `manifests/mongodb-oke.yaml` | Workload de MongoDB (se aplica con kubectl tras crear el clúster) |
| `.github/workflows/terraform.yml` | CI: `fmt` + `validate` en cada push/PR |

---

## Parámetros principales (formulario / tfvars)

| Parámetro | Default | Notas |
|-----------|---------|-------|
| `compartment_ocid` | — | Compartment destino (debe existir) |
| `region` | `sa-bogota-1` | Región |
| `node_shape` | `VM.Standard.E6.Flex` | E6/E5/E4/A1 Flex |
| `kubernetes_version` | última soportada | Vacío = la más nueva de OKE |
| `<cluster>_enabled` | `true` | Desplegar o no cada clúster |
| `<cluster>_node_ocpus` | 1 (Mongo 2) | OCPUs por nodo |
| `<cluster>_node_memory_gbs` | 8 | RAM por nodo |
| `<cluster>_pool1_size` / `pool2_size` | 2 / 2 | Nodos por pool |

Topología fija (CIDRs, nombres, LB público/privado) en `locals.tf` → `cluster_defaults`.

---

## Topología desplegada

| Clúster | Nodes | API | LB | Pools | OCPU total |
|---------|-------|-----|----|----|----|
| PresNet | `10.0.10.0/24` | `10.0.11.0/24` | `10.0.12.0/24` (público) | front(2)+back-apis(2) | 4 |
| TerMed  | `10.0.20.0/24` | `10.0.21.0/24` | `10.0.22.0/24` (público) | front(2)+back-apis(2) | 4 |
| MongoDB | `10.0.30.0/24` | `10.0.31.0/24` | `10.0.32.0/24` (privado) | db(2)+db-io(2) | 8 |

---

## Antes de ejecutar — checklist

1. **Service limit de E6.** Se necesitan **16 OCPUs** `VM.Standard.E6.Flex` en `sa-bogota-1`. Verifica/solicita el aumento antes de ejecutar.
2. **Compartment.** Debe existir; el código no lo crea.
3. **Versión de K8s.** Si dejas `kubernetes_version=""` toma la última; revisa el output `node_image_id`. Si queda vacío, pasa `node_image_id` manualmente.
4. **MongoDB sobre OKE (definitivo).** La BD corre como workload en `cluster-mongodb`. Este Terraform crea la infraestructura (red + OKE + LB privado); el motor MongoDB se aplica con `manifests/mongodb-oke.yaml` (StatefulSet ReplicaSet de 3 miembros + Block Volume CSI `oci-bv` + Service LoadBalancer interno + CronJob de backup) desde Bastion/Cloud Shell tras crear el clúster:

```bash
kubectl apply -f manifests/mongodb-oke.yaml
```
