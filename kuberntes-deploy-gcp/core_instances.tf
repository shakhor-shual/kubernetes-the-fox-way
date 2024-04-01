#--------------- VMs --------------------
resource "google_compute_address" "ip_address_bastion" {
  name   = "external-ip-k8s-bastion"
  region = var.region
}

resource "google_compute_instance" "bastion" {
  name                      = "bastion"
  hostname                  = "bastion.${local.domain}"
  description               = "Linux Server"
  machine_type              = local.nfs_server_gb != 0 ? var.powered_machine_type : var.machine_type
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
  machine_type              = local.control_plane_size == 1 ? var.powered_machine_type : var.machine_type
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
