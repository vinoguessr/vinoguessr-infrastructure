locals {
  image_url = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/${var.service_name}:${var.image_tag}"

  cloudflare_cidr_chunks = chunklist(concat(
    data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs,
    data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs,
  ), 10)

  # CLOUD_RUN_REGION is derived from var.region so it can't drift from where
  # the service actually runs.
  plain_env = merge(var.app_env, {
    CLOUD_RUN_REGION = var.region
  })

  # Sensitive env vars sourced from Secret Manager. The env var name and the
  # Secret Manager secret_id are identical, so a single set is sufficient.
  secret_env_names = toset([
    "CLOUDFLARE_API_TOKEN",
    "EDDSA_PRIVATE_KEY",
    "OTP_SECRET_KEY",
    "POSTGRES_PASSWORD",
    "VALKEY_PASSWORD",
  ])
}
