resource "google_cloud_run_v2_service" "api" {
  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_iam_member.otel_collector_config_runtime_access,
    google_secret_manager_secret_version.otel_collector_config,
    google_secret_manager_secret_iam_member.runtime_access,
  ]

  name                = var.service_name
  location            = var.region
  ingress             = var.restrict_direct_cloud_run_ingress ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      depends_on = ["collector"]

      name  = "app"
      image = local.image_url

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = true
      }

      # Non-sensitive env vars, including Terraform-controlled Cloud Run/OTel settings.
      dynamic "env" {
        for_each = local.plain_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Sensitive env vars sourced from Secret Manager.
      dynamic "env" {
        for_each = local.secret_env_names
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.app[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      # Match existing prod probe (long timeout, single attempt). Tuned so a
      # cold start that triggers DB migrations doesn't get killed prematurely.
      startup_probe {
        tcp_socket {
          port = 8080
        }
        timeout_seconds   = 240
        period_seconds    = 240
        failure_threshold = 1
      }
    }

    containers {
      name  = "collector"
      image = var.otel_collector_image
      args  = ["--config=/etc/otelcol-google/config.yaml"]

      resources {
        limits = {
          cpu    = var.otel_collector_cpu
          memory = var.otel_collector_memory
        }
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = true
      }

      startup_probe {
        http_get {
          path = "/"
          port = 13133
        }
        timeout_seconds = 30
        period_seconds  = 30
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 13133
        }
        timeout_seconds = 30
        period_seconds  = 30
      }

      volume_mounts {
        name       = "otel-collector-config"
        mount_path = "/etc/otelcol-google/"
      }
    }

    volumes {
      name = "otel-collector-config"

      secret {
        secret = google_secret_manager_secret.otel_collector_config.secret_id

        items {
          version = "latest"
          path    = "config.yaml"
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # GitHub Actions updates the running image via `gcloud run services update`.
      # Keeping this ignored prevents `terraform apply` from reverting prod.
      template[0].containers[0].image,
      # Cloud Build / gcloud deploy auto-stamps these on each revision.
      template[0].labels,
      template[0].annotations,
      client,
      client_version,
    ]
  }
}

# Scope deployer's Cloud Run permissions to the one service rather than project-wide.
# `roles/run.developer` includes `run.services.update` which is what the GHA
# workflow calls via `gcloud run services update --image=...`.
resource "google_cloud_run_v2_service_iam_member" "deployer_developer" {
  project  = google_cloud_run_v2_service.api.project
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.api.project
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
