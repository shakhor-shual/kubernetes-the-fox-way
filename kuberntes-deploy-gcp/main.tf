provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project_id
  region      = var.region
}

provider "google-beta" {
  credentials = file(var.credentials_file)
  project     = var.project_id
  region      = var.region
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
  machine_type_auto  = local.control_plane_size == 1 ? var.shift_machine_type : var.machine_type
  custom_key_public  = fileexists(var.custom_key_public) ? file(var.custom_key_public) : local_file.public_key.content

  domain = "example.com"
  #- export DuckDNS_DOMAIN_BASTION=shuala-bastion &&  export DuckDNS_DOMAIN_INGRESS=shuala-ingress && export DuckDNS_ACCESS_TOKEN=71138021-1493-4e65-9d1f-b99d704eb7a7 && $DuckDNS_IP_INGRESS=
  ddns_domain_ingress = "shuala-bastion"
  ddns_domain_bastion = "shuala-ingress"
  ddns_access_token   = "71138021-1493-4e65-9d1f-b99d704eb7a7"

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

resource "google_compute_network" "kube_vpc" {
  name                    = var.vpc_name
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = false
}

resource "google_compute_router" "router" {
  name    = "master-router"
  region  = var.region
  network = google_compute_network.kube_vpc.id
}

resource "google_compute_router_nat" "nat_router" {
  name                   = "master-router-nat"
  router                 = google_compute_router.router.name
  region                 = google_compute_router.router.region
  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.master_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_subnetwork" "master_subnet" {
  name          = "control-plane-subnet"
  ip_cidr_range = local.subnet_cidr
  network       = google_compute_network.kube_vpc.self_link
  region        = var.region
}

# create firewall rules for project
resource "google_compute_firewall" "rules-external" {
  name        = "firewall-ext"
  project     = var.project_id # Replace this with your project ID in quotes
  network     = google_compute_network.kube_vpc.self_link
  description = "Creates  external firewall rules"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080"]
  }
  source_ranges = ["0.0.0.0/0"]
  //target_tags = ["opened-ports"]
}

resource "google_compute_firewall" "rules-internal" {
  name        = "firewall-int"
  project     = var.project_id
  network     = google_compute_network.kube_vpc.self_link
  description = "Creates firewall rule targeting tagged instances"

  dynamic "allow" {
    for_each = ["tcp", "udp", "icmp", "ipip"]
    content {
      protocol = allow.value
    }
  }
  source_ranges = ["10.230.0.0/24", "10.240.0.0/24", "10.250.0.0/24", "10.200.0.0/16"]
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
    ddns_domain_ingress  = local.ddns_domain_ingress
    ddns_domain_bastion  = local.ddns_domain_bastion
    ddns_access_token    = local.ddns_access_token
    bastion_network_ip   = local.bastion_network_ip,
    cloudnfs_network_ip  = local.filestore_network_ip,
    control_plane_lb_ip  = local.kube_load_balancing.ip_address,
    subnets_list         = join(",", var.subnet_list),
    kubernetes           = local.kubernetes,
    extra_sans           = local.extra_sans,
    ingress_nodes_prefix = var.ingress_host
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

#--------------- VMs --------------------
resource "google_compute_address" "ip_address_bastion" {
  name   = "external-ip-k8s-bastion"
  region = var.region
}

resource "google_compute_instance" "bastion" {
  name                      = "bastion"
  hostname                  = "bastion.${local.domain}"
  description               = "Linux Server"
  machine_type              = local.machine_type_auto
  zone                      = var.zone
  allow_stopping_for_update = true
  deletion_protection       = false

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    provisioning_model  = "STANDARD"
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.os_image
      type  = var.os_disk_type
      size  = var.os_disk_size + local.nfs_server_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.master_subnet.self_link
    network_ip = local.bastion_network_ip
    access_config {
      network_tier = "PREMIUM"
      nat_ip       = google_compute_address.ip_address_bastion.address
    }
  }

  #tags = [master-group, node, bastion]

  metadata = {
    user-data              = "${data.cloudinit_config.cloud_conf.rendered}"
    ssh-keys               = "${var.ssh_user}:${local_file.public_key.content}"
    block-project-ssh-keys = true
  }
}

resource "google_compute_instance" "master" {
  count                     = local.control_plane_size
  name                      = "master-${count.index}"
  hostname                  = "master-${count.index}.${local.domain}"
  description               = "Linux Server"
  machine_type              = local.machine_type_auto
  zone                      = var.zone
  allow_stopping_for_update = true
  deletion_protection       = false

  scheduling {
    provisioning_model  = "STANDARD"
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.os_image
      type  = var.os_disk_type
      size  = var.os_disk_size
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.master_subnet.self_link
    network_ip = cidrhost(local.subnet_cidr, count.index + 10)
  }

  #tags = [master-group, master, control-plane]

  metadata = {
    user-data              = "${data.cloudinit_config.cloud_conf.rendered}"
    ssh-keys               = "${var.ssh_user}:${local_file.public_key.content}"
    block-project-ssh-keys = true
  }
}

resource "google_compute_instance" "node_ingress" {
  count                     = 2
  name                      = "node-ingress-${count.index}"
  hostname                  = "node-ingress-${count.index}.${local.domain}"
  description               = "Linux Server"
  machine_type              = var.machine_type
  zone                      = var.zone
  allow_stopping_for_update = true
  deletion_protection       = false

  scheduling {
    provisioning_model  = "STANDARD"
    on_host_maintenance = "TERMINATE"
    automatic_restart   = true
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.os_image
      type  = var.os_disk_type
      size  = var.os_disk_size
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.master_subnet.self_link
    network_ip = cidrhost(local.subnet_cidr, count.index + 21)
  }

  #tags = [master-group, master, control-plane]

  metadata = {
    user-data              = "${data.cloudinit_config.cloud_conf.rendered}"
    ssh-keys               = "${var.ssh_user}:${local_file.public_key.content}"
    block-project-ssh-keys = true
  }
}

resource "google_filestore_instance" "kube_pv_storage" {
  count    = local.file_store_count
  name     = "pv-store-${count.index}"
  location = var.zone
  tier     = "BASIC_HDD"

  file_shares {
    capacity_gb = local.file_store_gb
    name        = "pv_storage"

    nfs_export_options {
      ip_ranges   = var.subnet_list
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }
  networks {
    network           = google_compute_network.kube_vpc.name
    modes             = ["MODE_IPV4"]
    connect_mode      = "DIRECT_PEERING"
    reserved_ip_range = local.filestore_cidr
  }
}

output "filestore_ip" {
  value = local.file_store_count == 0 ? "0.0.0.0" : google_filestore_instance.kube_pv_storage[0].networks[0].ip_addresses[0]
}

#-------------------- Load Balancing Settings ----------------
resource "google_compute_firewall" "rules-hc" {
  name          = "kube-api-lb-fw-allow-helz"
  direction     = "INGRESS"
  network       = google_compute_network.kube_vpc.self_link
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "35.235.240.0/20"]
  allow {
    protocol = "tcp"
  }
  source_tags = ["allow-health-check"]
}

#-- Internal LB for CONTROL PLANE --------------------
resource "google_compute_instance_group" "control_plane_lb_backend_uig" {
  count       = local.deploy_on_demand
  name        = "kube-api-uig-${count.index}"
  zone        = var.zone
  description = "Terraform kube-api instance group"

  instances = google_compute_instance.master[*].id
}

resource "google_compute_region_health_check" "control_plane_lb_health" {
  count              = local.deploy_on_demand
  name               = "kube-api-lb-hc-${count.index}"
  region             = var.region
  timeout_sec        = local.kube_load_balancing.health_timeout
  check_interval_sec = local.kube_load_balancing.health_check

  dynamic "https_health_check" {
    for_each = local.kube_https_hc
    content {
      port         = local.kube_load_balancing.health_port
      host         = local.kube_load_balancing.health_host
      request_path = local.kube_load_balancing.health_path
    }
  }

  dynamic "http_health_check" {
    for_each = local.kube_http_hc
    content {
      port         = local.kube_load_balancing.health_port
      host         = local.kube_load_balancing.health_host
      request_path = local.kube_load_balancing.health_path
    }
  }

  log_config { enable = local.kube_load_balancing.log_config }
}

resource "google_compute_region_backend_service" "control_plane_lb_backend" {
  count                 = local.deploy_on_demand
  name                  = "kube-api-lb-backend-${count.index}"
  region                = var.region
  protocol              = local.kube_load_balancing.ip_protocol
  load_balancing_scheme = local.kube_load_balancing.balancing_scheme
  health_checks         = [google_compute_region_health_check.control_plane_lb_health[count.index].id]
  backend {
    group          = google_compute_instance_group.control_plane_lb_backend_uig[count.index].id
    balancing_mode = local.kube_load_balancing.balancing_mode
  }
}

resource "google_compute_forwarding_rule" "control_plane_lb_forwarding" {
  count                 = local.deploy_on_demand
  name                  = "kube-api-lb-forwarding-${count.index}"
  backend_service       = google_compute_region_backend_service.control_plane_lb_backend[count.index].id
  region                = var.region
  ip_protocol           = local.kube_load_balancing.ip_protocol
  load_balancing_scheme = local.kube_load_balancing.balancing_scheme
  all_ports             = local.kube_load_balancing.all_ports
  allow_global_access   = local.kube_load_balancing.allow_global_access
  network               = google_compute_network.kube_vpc.self_link
  subnetwork            = google_compute_subnetwork.master_subnet.self_link
  ip_address            = local.kube_load_balancing.ip_address
}

#--- External LB for INGRESS --------------------
resource "google_compute_address" "ingress_ip_address" {
  name   = "external-ip-k8s-ingress"
  region = var.region
}

resource "google_compute_instance_group" "ingress_lb_backend_uig" {
  name        = "k8s-ingress-uig"
  zone        = var.zone
  description = "Terraform k8s-INGRESS instance group"
  instances   = google_compute_instance.node_ingress[*].id
}

resource "google_compute_region_health_check" "ingress_lb_health" {
  name               = "k8s-ingress-lb-hc"
  region             = var.region
  timeout_sec        = local.ingress_load_balancing.health_timeout
  check_interval_sec = local.ingress_load_balancing.health_check

  dynamic "https_health_check" {
    for_each = local.ingress_https_hc
    content {
      port         = local.ingress_load_balancing.health_port
      host         = local.ingress_load_balancing.health_host
      request_path = local.ingress_load_balancing.health_path
    }
  }

  dynamic "http_health_check" {
    for_each = local.ingress_http_hc
    content {
      port         = local.ingress_load_balancing.health_port
      host         = local.ingress_load_balancing.health_host
      request_path = local.ingress_load_balancing.health_path
    }
  }

  dynamic "tcp_health_check" {
    for_each = local.ingress_tcp_hc
    content {
      port = local.ingress_load_balancing.health_port
    }
  }

  log_config { enable = local.ingress_load_balancing.log_config }
}

resource "google_compute_region_backend_service" "ingress_lb_backend" {
  name                  = "k8s-ingress-lb-backend-service"
  region                = var.region
  protocol              = local.ingress_load_balancing.ip_protocol
  load_balancing_scheme = local.ingress_load_balancing.balancing_scheme
  health_checks         = [google_compute_region_health_check.ingress_lb_health.id]
  backend {
    group          = google_compute_instance_group.ingress_lb_backend_uig.id
    balancing_mode = local.ingress_load_balancing.balancing_mode
  }
}

resource "google_compute_forwarding_rule" "ingress_lb_forwarding_http" {
  name                  = "k8s-ingress-lb-forwarding-http"
  backend_service       = google_compute_region_backend_service.ingress_lb_backend.id
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = 80
  load_balancing_scheme = local.ingress_load_balancing.balancing_scheme
  ip_address            = google_compute_address.ingress_ip_address.id
  network_tier          = google_compute_address.ingress_ip_address.network_tier
}

resource "google_compute_forwarding_rule" "ingress_lb_forwarding_https" {
  name                  = "k8s-ingress-lb-forwarding-https"
  backend_service       = google_compute_region_backend_service.ingress_lb_backend.id
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = 443
  load_balancing_scheme = local.ingress_load_balancing.balancing_scheme
  ip_address            = google_compute_address.ingress_ip_address.id
  network_tier          = google_compute_address.ingress_ip_address.network_tier
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
