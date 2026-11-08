data "cloudflare_ip_ranges" "cloudflare" {}

resource "google_compute_global_address" "api" {
  depends_on = [google_project_service.required]

  name         = "${var.service_name}-api-lb-ip"
  description  = "Global external IPv4 address for ${var.api_hostname}."
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_region_network_endpoint_group" "api" {
  depends_on = [google_project_service.required]

  name                  = "${var.service_name}-neg"
  description           = "Serverless NEG for ${google_cloud_run_v2_service.api.name}."
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_security_policy" "api" {
  depends_on = [google_project_service.required]

  name        = "${var.service_name}-cloudflare-only"
  description = "Allow only Cloudflare proxy IP ranges to reach ${var.api_hostname}."
  type        = "CLOUD_ARMOR"

  dynamic "rule" {
    for_each = { for index, cidrs in local.cloudflare_cidr_chunks : index => cidrs }

    content {
      action      = "allow"
      priority    = 1000 + tonumber(rule.key)
      description = "Allow Cloudflare proxy IP ranges chunk ${tonumber(rule.key) + 1}."

      match {
        versioned_expr = "SRC_IPS_V1"

        config {
          src_ip_ranges = rule.value
        }
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 2147483647
    description = "Deny all non-Cloudflare traffic."

    match {
      versioned_expr = "SRC_IPS_V1"

      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_backend_service" "api" {
  depends_on = [google_project_service.required]

  name                  = "${var.service_name}-backend"
  description           = "Backend service for ${var.api_hostname}."
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  security_policy       = google_compute_security_policy.api.id
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "api" {
  depends_on = [google_project_service.required]

  name            = "${var.service_name}-url-map"
  description     = "Routes ${var.api_hostname} to Cloud Run."
  default_service = google_compute_backend_service.api.id

  host_rule {
    hosts        = [var.api_hostname]
    path_matcher = "api"
  }

  path_matcher {
    name            = "api"
    default_service = google_compute_backend_service.api.id
  }
}

resource "google_compute_url_map" "api_http_redirect" {
  depends_on = [google_project_service.required]

  name        = "${var.service_name}-http-redirect"
  description = "Redirects HTTP requests for ${var.api_hostname} to HTTPS."

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_certificate_manager_dns_authorization" "api" {
  depends_on = [google_project_service.required]

  name        = "${var.service_name}-api-dnsauth"
  description = "DNS authorization for ${var.api_hostname}."
  domain      = var.api_hostname
  type        = "PER_PROJECT_RECORD"
}

resource "cloudflare_dns_record" "api_certificate_dns_authorization" {
  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(google_certificate_manager_dns_authorization.api.dns_resource_record[0].name, ".")
  type    = "CNAME"
  content = trimsuffix(google_certificate_manager_dns_authorization.api.dns_resource_record[0].data, ".")
  ttl     = 300
  proxied = false
  comment = "Google Certificate Manager DNS authorization for ${var.api_hostname}."
}

resource "google_certificate_manager_certificate" "api" {
  depends_on = [
    cloudflare_dns_record.api_certificate_dns_authorization,
    google_project_service.required,
  ]

  name        = "${var.service_name}-api-cert"
  description = "Google-managed certificate for ${var.api_hostname}."

  managed {
    domains            = [var.api_hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.api.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_certificate_manager_certificate_map" "api" {
  depends_on = [google_project_service.required]

  name        = "${var.service_name}-api-certmap"
  description = "Certificate map for ${var.api_hostname}."
}

resource "google_certificate_manager_certificate_map_entry" "api" {
  name         = "${var.service_name}-api-certmap-entry"
  description  = "Certificate map entry for ${var.api_hostname}."
  map          = google_certificate_manager_certificate_map.api.name
  certificates = [google_certificate_manager_certificate.api.id]
  hostname     = var.api_hostname
}

resource "google_compute_target_https_proxy" "api" {
  depends_on = [google_certificate_manager_certificate_map_entry.api]

  name            = "${var.service_name}-https-proxy"
  description     = "HTTPS proxy for ${var.api_hostname}."
  url_map         = google_compute_url_map.api.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.api.id}"
}

resource "google_compute_target_http_proxy" "api_redirect" {
  depends_on = [google_project_service.required]

  name        = "${var.service_name}-http-proxy"
  description = "HTTP redirect proxy for ${var.api_hostname}."
  url_map     = google_compute_url_map.api_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "api_https" {
  depends_on = [google_project_service.required]

  name                  = "${var.service_name}-https"
  description           = "HTTPS forwarding rule for ${var.api_hostname}."
  ip_address            = google_compute_global_address.api.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.api.id
}

resource "google_compute_global_forwarding_rule" "api_http" {
  depends_on = [google_project_service.required]

  name                  = "${var.service_name}-http"
  description           = "HTTP forwarding rule for ${var.api_hostname} redirects."
  ip_address            = google_compute_global_address.api.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.api_redirect.id
}

resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_hostname
  type    = "A"
  content = google_compute_global_address.api.address
  ttl     = 1
  proxied = true
  comment = "Routes ${var.api_hostname} to the Google external HTTPS load balancer."
}
