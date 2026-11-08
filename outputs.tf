output "artifact_repo" {
  description = "Artifact Registry path (host/project/repo). Prefix for pushed image tags."
  value       = "${google_artifact_registry_repository.app.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "api_health_url" {
  description = "Health endpoint served through the public custom domain."
  value       = "https://${var.api_hostname}/health"
}

output "api_hostname" {
  description = "Public hostname served through Cloudflare and the Google external HTTPS load balancer."
  value       = var.api_hostname
}

output "api_load_balancer_ip" {
  description = "Global IPv4 address for the external HTTPS load balancer."
  value       = google_compute_global_address.api.address
}

output "certificate_map" {
  description = "Certificate Manager certificate map attached to the HTTPS proxy."
  value       = google_certificate_manager_certificate_map.api.id
}

output "deployer_sa_email" {
  description = "Service account email impersonated by GitHub Actions. Pass to google-github-actions/auth as `service_account`."
  value       = google_service_account.deployer.email
}

output "project_id" {
  description = "Google Cloud project ID. Echoed for use in CI variable wiring."
  value       = var.project_id
}

output "region" {
  description = "Region the service runs in. Echoed for use in CI variable wiring."
  value       = var.region
}

output "runtime_sa_email" {
  description = "Service account used by Cloud Run at runtime."
  value       = google_service_account.runtime.email
}

output "secrets" {
  description = "Map of Secret Manager secrets created for the app. Use `gcloud secrets versions add <id> --data-file=-` to upload values."
  value       = { for k, v in google_secret_manager_secret.app : k => v.id }
}

output "service_url" {
  description = "Public URL of the Cloud Run service."
  value       = google_cloud_run_v2_service.api.uri
}

output "wif_provider" {
  description = "Full resource name of the WIF provider. Pass to google-github-actions/auth as `workload_identity_provider`."
  value       = google_iam_workload_identity_pool_provider.github.name
}
