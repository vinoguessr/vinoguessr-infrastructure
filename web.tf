# vinoguessr-web serves site_hostname behind the same load balancer as the API.
# It has its own image repository, runtime identity, and deployer, so the web's
# Deploy workflow can never push API images or touch the API service.

resource "google_artifact_registry_repository" "web" {
  depends_on = [google_project_service.required]

  repository_id = var.web_artifact_repo_id
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for ${var.web_service_name}."

  # Overrides the provider's default `service` label so billing and filters count the web separately.
  labels = {
    service = var.web_service_name
  }
}

resource "google_artifact_registry_repository_iam_member" "web_deployer_ar_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.web.location
  repository = google_artifact_registry_repository.web.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.web_deployer.email}"
}

# The web keeps no business data and calls no Google APIs, so its runtime identity has no roles.
resource "google_service_account" "web_runtime" {
  depends_on = [google_project_service.required]

  account_id   = "${var.web_service_name}-runtime"
  display_name = "${var.web_service_name} Cloud Run runtime"
  description  = "Identity for the web Cloud Run service at runtime."
}

resource "google_service_account" "web_deployer" {
  depends_on = [google_project_service.required]

  account_id   = "${var.web_service_name}-deployer"
  display_name = "${var.web_service_name} GitHub Actions deployer"
  description  = "Impersonated by vinoguessr-web's GitHub Actions (via WIF) to push images and update the web service."
}

resource "google_service_account_iam_member" "web_deployer_actas_runtime" {
  service_account_id = google_service_account.web_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.web_deployer.email}"
}

# A separate provider in the same pool, with the same checks as the API's provider, so each
# provider admits exactly one repository's Deploy workflow on the deploy branch.
resource "google_iam_workload_identity_pool_provider" "github_web" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-web"
  display_name                       = "GitHub OIDC (web)"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.workflow_ref"        = "assertion.workflow_ref"
  }

  attribute_condition = join(" && ", [
    "assertion.repository == \"${var.web_github_repo}\"",
    "assertion.repository_id == \"${var.web_github_repository_id}\"",
    "assertion.repository_owner_id == \"${var.github_repository_owner_id}\"",
    "assertion.ref == \"${var.deploy_branch}\"",
    "assertion.workflow_ref == \"${var.web_github_repo}/${var.deploy_workflow}@${var.deploy_branch}\"",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Bindings are per pool, not per provider: only tokens for var.web_github_repo, which only the
# web provider admits, may impersonate the web deployer.
resource "google_service_account_iam_member" "web_deployer_wif" {
  service_account_id = google_service_account.web_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/${var.web_github_repo}"
}

resource "google_cloud_run_v2_service" "web" {
  depends_on = [google_project_service.required]

  name                = var.web_service_name
  location            = var.region
  ingress             = var.restrict_direct_cloud_run_ingress ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  labels = {
    service = var.web_service_name
  }

  template {
    service_account = google_service_account.web_runtime.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.web_max_instance_count
    }

    containers {
      name  = "app"
      image = var.web_bootstrap_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = var.web_memory
        }
        # The web does no work outside requests, so CPU is billed only while serving them.
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "LOG_LEVEL"
        value = "info"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # vinoguessr-web's Deploy workflow updates the running image via `gcloud run services update`.
      template[0].containers[0].image,
      template[0].labels,
      template[0].annotations,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "web_deployer_developer" {
  project  = google_cloud_run_v2_service.web.project
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.web_deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "web_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.web.project
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_compute_region_network_endpoint_group" "web" {
  depends_on = [google_project_service.required]

  name                  = "${var.web_service_name}-neg"
  description           = "Serverless NEG for ${google_cloud_run_v2_service.web.name}."
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.web.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "web" {
  depends_on = [google_project_service.required]

  name                  = "${var.web_service_name}-backend"
  description           = "Backend service for ${var.site_hostname}."
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"
  security_policy       = google_compute_security_policy.api.id
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.web.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}
