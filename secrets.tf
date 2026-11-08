resource "google_secret_manager_secret" "app" {
  for_each   = local.secret_env_names
  depends_on = [google_project_service.required]

  secret_id = each.value

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each = local.secret_env_names

  secret_id = google_secret_manager_secret.app[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "deployer_postgres_password_access" {
  secret_id = google_secret_manager_secret.app["POSTGRES_PASSWORD"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_secret_manager_secret" "otel_collector_config" {
  depends_on = [google_project_service.required]

  secret_id = var.otel_collector_config_secret_id

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_version" "otel_collector_config" {
  secret      = google_secret_manager_secret.otel_collector_config.id
  secret_data = file("${path.module}/otel/collector-config.yaml")
}

resource "google_secret_manager_secret_iam_member" "otel_collector_config_runtime_access" {
  secret_id = google_secret_manager_secret.otel_collector_config.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
