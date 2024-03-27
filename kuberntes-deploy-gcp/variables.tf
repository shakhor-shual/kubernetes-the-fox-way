variable "credentials_file" {
  description = "GCP credentials file name"
  default     = "gcp.json"
}

variable "project_id" {
  description = "project ID"
  default     = "some-roject"
}

variable "region" {
  description = "Region for VPC and subnet"
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud Platform zone"
  default     = "us-central1-c"
}

variable "vpc_name" {
  description = "VPC name"
  default     = "some-vpc"
}

variable "subnet_list" {
  description = "Hostnames for ingress hosts"
  default     = ["10.230.0.0/24", "10.240.0.0/24", "10.250.0.0/24"]
}

variable "kube_kind" {
  description = "Kind of Kubernetes deployment, now possible are: k8raw, k8adm, k3s"
  default     = "k8adm"
}

variable "ingress_host" {
  description = "Hostnames for ingress hosts"
  default     = "node_ingress"
}

variable "ssh_user" {
  description = "SSH user"
  default     = "shual"
}

variable "custom_key_public" {
  description = "Path-to existing user-defined SSH public key (simplify external access to bastion) "
  default     = "~/.ssh/id_rsa_pub.pem"
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
  description = "Base VM type for cluster master/node"
  default     = "n1-standard-1"
}

variable "shift_machine_type" {
  description = "Powered  VM type for cluster master/node"
  default     = "n1-standard-2"
}

variable "os_image" {
  description = "OS image for cluster master/node !!!ONLY Ubuntu or Debian with cloud-config support in GCP"
  default     = "ubuntu-os-cloud/ubuntu-2004-lts"
}

variable "os_disk_size" {
  description = "OS disk size for cluster master/node in GB"
  default     = 25
}

variable "os_disk_type" {
  description = "OS disk type for cluster master/node"
  default     = "pd-balanced"
}

variable "nfs_pv_size" {
  description = "Size of NFS PV-volumes storage: !!!SIZE >=1024 AUTO ALLOCATTED to GCP Filestore Service"
  default     = 25
}
