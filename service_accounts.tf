resource "google_service_account" "runtime" {
  depends_on = [google_project_service.required]

  account_id   = "${var.service_name}-runtime"
  display_name = "${var.service_name} Cloud Run runtime"
  description  = "Identity for the Cloud Run service at runtime."
}

resource "google_project_iam_member" "runtime_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_service_account" "deployer" {
  depends_on = [google_project_service.required]

  account_id   = "${var.service_name}-deployer"
  display_name = "${var.service_name} GitHub Actions deployer"
  description  = "Impersonated by GitHub Actions (via WIF) to push images and update Cloud Run."
}

# Required so deployer can deploy a Cloud Run service that runs-as the runtime SA.
resource "google_service_account_iam_member" "deployer_actas_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
