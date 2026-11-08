resource "google_artifact_registry_repository" "app" {
  depends_on = [google_project_service.required]

  repository_id = var.artifact_repo_id
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for ${var.service_name}."
}

# Scope artifactregistry.writer to the one repo rather than project-wide.
resource "google_artifact_registry_repository_iam_member" "deployer_ar_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}
