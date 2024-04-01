
####################################################################################
# This file is part of the CW4D tookit. It deploys Kubernetes cluster-ready 
# infrastructure on GCP & bootstraps a self-managed Kubernetes cluster on top of it.
# Copyright (C) Vadym Yanik 2024
#
# CW4D is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3  of the License, or (at your option) any
# later version
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; # without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License  along
# with this program; If not, see <http://www.gnu.org/licenses/>.
###################################################################################

provider "google" {
  # !!!UNCOMMENT next line for use Service Account key access INSTEAD user-account ADC
  #  credentials = file(var.credentials_file)
  project = var.project_id
  region  = var.region
}

locals {
  supported_deployments = ["k3s", "k8adm", "k8raw"]
  kubernetes            = contains(local.supported_deployments, var.kube_kind) ? var.kube_kind : "k8adm"

  ssh_tunnel = {
    gateway = "bastion.gcp" //  fake-FQDN for bastion host (autorefreshed in "hosts"-file for Linux & Windows-WSL )
    target  = "master-0"    // default vpc-network-internal hostname for SSH-tunnel endpoint (targeted to one of control plane nodes) 
  }

  nfs_server_gb      = var.nfs_pv_size < 1024 ? var.nfs_pv_size < 100 ? 100 : var.nfs_pv_size : 0
  file_store_gb      = var.nfs_pv_size >= 1024 ? var.nfs_pv_size : 1024
  file_store_count   = var.nfs_pv_size < 1024 ? 0 : 1
  control_plane_size = local.kubernetes == "k8adm" ? 1 : 3
  deploy_on_demand   = local.control_plane_size == 1 ? 0 : 1
  machine_type_auto  = local.control_plane_size == 1 ? var.powered_machine_type : var.machine_type

  custom_key_public = fileexists(var.custom_key_public) ? file(var.custom_key_public) : local_file.public_key.content

  domain = "example.local"
  kube_kinds = {
    k3s   = { health_path = "/ping", health_port = "6443", config_path = "/etc/rancher/k3s/k3s.yaml" }
    k8adm = { health_path = "/healthz", health_port = "6443", config_path = "/root/.kube/config" }
    k8raw = { health_path = "/healthz", health_port = "6443", config_path = "/root/.kube/config" }
  }

  bastion_network_ip   = cidrhost(local.subnet_cidr, 20)
  filestore_cidr       = "10.200.0.200/29"
  filestore_network_ip = local.file_store_count == 0 ? "0.0.0.0" : google_filestore_instance.kube_pv_storage[0].networks[0].ip_addresses[0]
  extra_sans           = local.ssh_tunnel.gateway
  subnet_cidr          = var.subnet_list[0]


  kube_load_balancing = {
    ip_address          = cidrhost(local.subnet_cidr, 222)
    ip_protocol         = "TCP"
    balancing_scheme    = "INTERNAL"
    balancing_mode      = "CONNECTION"
    health_type         = "https"
    health_port         = local.kube_kinds[local.kubernetes].health_port
    health_path         = local.kube_kinds[local.kubernetes].health_path
    log_config          = true
    health_host         = ""
    health_timeout      = 2
    health_check        = 2
    log_config          = true
    all_ports           = true
    allow_global_access = true
  }
  kube_https_hc = local.kube_load_balancing.health_type == "https" ? ["yes"] : []
  kube_http_hc  = local.kube_load_balancing.health_type == "http" ? ["yes"] : []

  ingress_load_balancing = {
    balancing_scheme = "EXTERNAL"
    balancing_mode   = "CONNECTION"
    health_type      = "tcp"
    health_port      = "80"
    ip_protocol      = "TCP"
    health_path      = "/"
    health_host      = ""
    health_timeout   = 2
    health_check     = 2
    log_config       = true
    network_tier     = "STANDARD"
  }
  ingress_https_hc = local.ingress_load_balancing.health_type == "https" ? ["yes"] : []
  ingress_http_hc  = local.ingress_load_balancing.health_type == "http" ? ["yes"] : []
  ingress_tcp_hc   = local.ingress_load_balancing.health_type == "tcp" ? ["yes"] : []
}

data "archive_file" "manifests" {
  type        = "zip"
  source_dir  = ".meta/manifests"
  output_path = ".meta/manifests.zip"
}

data "archive_file" "scripts" {
  type        = "zip"
  source_dir  = ".meta/scripts"
  output_path = ".meta/scripts.zip"
}
#--------------- Metadata --------------------
data "template_file" "cloud_conf" {
  template = file(".meta/cloud-init/apt-k8s-config.tftpl")
  vars = {
    user                 = var.ssh_user
    private_key          = base64gzip(local_sensitive_file.private_key.content),
    public_key_internal  = local_file.public_key.content,
    public_key_custom    = local.custom_key_public,
    all-manifests        = base64gzip(filebase64(data.archive_file.manifests.output_path)),
    all-scripts          = base64gzip(filebase64(data.archive_file.scripts.output_path)),
    front_ip_bastion     = google_compute_address.ip_address_bastion.address,
    front_ip_ingress     = google_compute_address.ingress_ip_address.address,
    ddns_domain_ingress  = var.ddns_domain_ingress
    ddns_domain_bastion  = var.ddns_domain_bastion
    ddns_access_token    = var.ddns_access_token
    bastion_network_ip   = local.bastion_network_ip,
    cloudnfs_network_ip  = local.filestore_network_ip,
    control_plane_lb_ip  = local.kube_load_balancing.ip_address,
    subnets_list         = join(",", var.subnet_list),
    kubernetes           = local.kubernetes,
    extra_sans           = local.extra_sans,
    ingress_nodes_prefix = var.ingress_host
    kubernetes_release   = var.kubernetes_release
  }
  depends_on = [local_file.public_key, local_sensitive_file.private_key]
}

data "cloudinit_config" "cloud_conf" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content      = data.template_file.cloud_conf.rendered
    filename     = "cloud-config.yml"
  }
}

#---------------Keys --------------------
resource "tls_private_key" "my_vm_access" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "public_key" {
  filename        = var.auto_key_public
  content         = trimspace(tls_private_key.my_vm_access.public_key_openssh)
  file_permission = "0400"
}

resource "local_sensitive_file" "private_key" {
  filename = var.auto_key_privare
  # IMPORTANT: Newline is required at end of open SSH private key file
  content         = tls_private_key.my_vm_access.private_key_openssh
  file_permission = "0400"
}


//============================================== LOCAL PROVISIONERS =======================================
resource "null_resource" "boot_finalize" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    working_dir = ".meta"
    command     = "./init_remote_access.sh ${local.ssh_tunnel.gateway} && ./init_remote_access.sh  ${google_compute_address.ip_address_bastion.address} ${local.ssh_tunnel.gateway} ${var.ssh_user}"
  }
  depends_on = [google_compute_router_nat.nat_router, google_compute_instance.bastion, google_compute_forwarding_rule.ingress_lb_forwarding_https]
}
