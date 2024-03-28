/*
# !!! UNCOMMENT & SETUP this variable block for use Service Account key acces INSTEAD user account ADC
variable "credentials_file" {
  description = "path-to-my GCP credentials file"
  default     = "CHANGE-IT-TO-YOURS!"
}
*/

variable "project_id" {
  description = "project ID"
  default     = "CHANGE-IT-TO-YOURS!"
}

variable "region" {
  description = "Region for VPC and subnet"
  default     = "europe-central2"
}

variable "zone" {
  description = "Google Cloud Platform zone"
  default     = "europe-central2-c"
}

variable "vpc_name" {
  description = "VPC name"
  default     = "kube-vpc"
}

variable "subnet_list" {
  description = "Subnets list for claster"
  default     = ["10.230.0.0/24", "10.240.0.0/24", "10.250.0.0/24"]
}

variable "kube_kind" {
  description = "Kind of Kubernetes deployment, now possible are: k8raw, k8adm, k3s"
  default     = "k8raw"
}

variable "kubernetes_release" {
  description = "Kube release for k8raw deployment !!!IF EMPTY/WRONG -used last stable, IF major&minor -> used specefied OR minor-latest(for wrong/skipped minors)"
  default     = "1.29.1"
}

variable "ingress_host" {
  description = "Hostnames for ingress hosts"
  default     = "node-ingress"
}

variable "ssh_user" {
  description = "SSH user for all cluster VMs"
  default     = "ubuntu"
}

variable "custom_key_public" {
  description = "Path-to-my existing user-defined SSH public key (simplify external access to bastion) "
  default     = "CHANGE-IT-TO-YOURS!"
}

variable "auto_key_public" {
  description = "Path-to auto-generated SSH public key (shared for all claster VMs)"
  default     = "../.meta/public.key"
}

variable "auto_key_privare" {
  description = "Path-to auto-generated SSH private key (shared for all claster VMs)"
  default     = "../.meta/private.key"
}

variable "machine_type" {
  description = "Base(>=1 CPU)) VM type for cluster master/node"
  default     = "n1-standard-1"
}

variable "powered_machine_type" {
  description = "Powered(>=2 CPU) VM type !!!AUTOUSED  for k8adm(master-0) and/or local-NFS-server(bastion) configurations"
  default     = "n1-standard-2"
}

variable "os_image" {
  description = "OS image for cluster master/node !!!ONLY Ubuntu or Debian(possible?) with cloud-config support in GCP"
  default     = "ubuntu-os-cloud/ubuntu-2004-lts"
}

variable "os_disk_size" {
  description = "OS disk size for cluster masters/nodes in GB"
  default     = 25
}

variable "os_disk_type" {
  description = "OS disk type for cluster masters/nodes"
  default     = "pd-balanced"
}

variable "nfs_pv_size" {
  description = "Size of NFS PV-volumes storage: !!!ALL SIZEs >=1024 AUTO ALLOCATTED to GCP Filestore Service"
  default     = 25
}

#supported DDNS provider - Duck-DDNS
variable "ddns_domain_ingress" {
  description = "DUCK DDNS domain for ingress LB IP (nginx-based ingress) "
  default     = "my-ingress-lb-ddns-name"
}

variable "ddns_domain_bastion" {
  description = "DDNS domain (actually DDNS short-host-name) for bastion IP (traefik-based ingress)"
  default     = "my-bastion-ddns-name"
}

variable "ddns_access_token" {
  description = "Duck-DDNS access touken for domains refresh, take it from Duck-DNS provider"
  default     = ""
}

