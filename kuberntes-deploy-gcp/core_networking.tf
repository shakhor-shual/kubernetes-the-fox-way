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
