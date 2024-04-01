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
