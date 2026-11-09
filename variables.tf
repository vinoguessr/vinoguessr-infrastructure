variable "allow_unauthenticated" {
  description = "Whether to allow public (unauthenticated) invocations of the API and web Cloud Run services."
  type        = bool
  default     = true
}

variable "api_hostname" {
  description = "Public hostname served through Cloudflare and the Google external HTTPS load balancer."
  type        = string
  default     = "api.vinoguessr.com"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.api_hostname))
    error_message = "api_hostname must be a lowercase DNS hostname, e.g. \"api.vinoguessr.com\"."
  }
}

variable "site_hostname" {
  description = "Passkey relying party ID and web hostname (ADR-0005), served by vinoguessr-web except its apple-app-site-association path, which the API serves."
  type        = string
  default     = "vinoguessr.com"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.site_hostname))
    error_message = "site_hostname must be a lowercase DNS hostname, e.g. \"vinoguessr.com\"."
  }
}

variable "app_env" {
  description = "Non-sensitive environment variables passed to the app container."
  type        = map(string)
}

variable "artifact_repo_id" {
  description = "Artifact Registry repository ID."
  type        = string
  default     = "vinoguessr-api"
}

variable "cpu" {
  description = "Cloud Run container CPU limit (vCPU count or millicpu, e.g. \"1\", \"2\", \"500m\")."
  type        = string
  default     = "1"
}

variable "cpu_idle" {
  description = "Whether Cloud Run should allocate CPU only while requests are active."
  type        = bool
  default     = false
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns api_hostname. Provide via terraform.tfvars or TF_VAR_cloudflare_zone_id."
  type        = string
  sensitive   = true
}

variable "github_repository_id" {
  description = "Numeric ID of var.github_repo (`gh api repos/<owner>/<name> --jq .id`)."
  type        = string
  default     = "1047706119"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be the numeric repository ID."
  }
}

variable "github_repository_owner_id" {
  description = "Numeric ID of the owner of var.github_repo and var.web_github_repo (`gh api repos/<owner>/<name> --jq .owner.id`)."
  type        = string
  default     = "350685173"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be the numeric owner ID."
  }
}

variable "deploy_workflow" {
  description = "Path of the only workflow in var.github_repo (and in var.web_github_repo, for the web deployer) allowed to mint deployer tokens."
  type        = string
  default     = ".github/workflows/deploy.yml"
}

variable "deploy_branch" {
  description = "Git ref allowed to mint API and web deployer tokens via Workload Identity Federation."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = startswith(var.deploy_branch, "refs/")
    error_message = "deploy_branch must be a fully-qualified ref, e.g. \"refs/heads/main\"."
  }
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deployer service account, in `owner/name` form."
  type        = string
  default     = "vinoguessr/vinoguessr-api"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in `owner/name` form, e.g. \"vinoguessr/vinoguessr-api\"."
  }
}

variable "image_tag" {
  description = "Image tag (the full commit SHA pushed by vinoguessr-api's Deploy workflow) used when Cloud Run is first created. After that, GitHub Actions updates the running image; Terraform ignores image drift."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be the full 40-character commit SHA of an image that already exists in Artifact Registry."
  }
}

variable "max_instance_count" {
  description = "Maximum number of Cloud Run container instances."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instance_count >= 1
    error_message = "max_instance_count must be at least 1."
  }

  validation {
    condition     = var.min_instance_count <= var.max_instance_count
    error_message = "max_instance_count must be greater than or equal to min_instance_count."
  }
}

variable "memory" {
  description = "Cloud Run container memory limit (e.g. \"512Mi\", \"1Gi\")."
  type        = string
  default     = "512Mi"
}

variable "min_instance_count" {
  description = "Minimum number of Cloud Run container instances kept warm."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must be non-negative."
  }
}

variable "otel_collector_config_secret_id" {
  description = "Secret Manager secret ID that stores the OpenTelemetry Collector config."
  type        = string
  default     = "vinoguessr-otel-collector-config"
}

variable "otel_collector_cpu" {
  description = "Cloud Run CPU limit for the OpenTelemetry Collector sidecar."
  type        = string
  default     = "1"
}

variable "otel_collector_image" {
  description = "Container image for the Google-built OpenTelemetry Collector sidecar."
  type        = string
  default     = "us-docker.pkg.dev/cloud-ops-agents-artifacts/google-cloud-opentelemetry-collector/otelcol-google:0.144.0"
}

variable "otel_collector_memory" {
  description = "Cloud Run memory limit for the OpenTelemetry Collector sidecar."
  type        = string
  default     = "256Mi"
}

variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "project_number" {
  description = "Google Cloud project number. Used in the Workload Identity Federation principalSet."
  type        = string
}

variable "region" {
  description = "Google Cloud region for Cloud Run and Artifact Registry."
  type        = string
  default     = "asia-northeast1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must look like a valid GCP region, e.g. \"asia-northeast1\"."
  }
}

variable "restrict_direct_cloud_run_ingress" {
  description = "When true, the API and web services accept external traffic only through Google Cloud Load Balancing, blocking direct public run.app access."
  type        = bool
  default     = true
}

variable "secret_versions" {
  description = "Secret Manager version number Cloud Run reads for each app secret, keyed by secret ID. Changing one rolls out a new revision."
  type        = map(string)
  nullable    = false

  validation {
    condition     = toset(keys(var.secret_versions)) == local.secret_env_names
    error_message = "secret_versions must have exactly one entry per app secret: CLOUDFLARE_API_TOKEN, EDDSA_PRIVATE_KEY, OTP_SECRET_KEY, POSTGRES_PASSWORD, VALKEY_PASSWORD."
  }

  validation {
    condition     = alltrue([for version in values(var.secret_versions) : can(regex("^[1-9][0-9]*$", version))])
    error_message = "secret_versions values must be version numbers such as \"1\", not \"latest\"."
  }
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "vinoguessr-api"
}

variable "web_service_name" {
  description = "Cloud Run service name for vinoguessr-web, which serves site_hostname."
  type        = string
  default     = "vinoguessr-web"
}

variable "web_artifact_repo_id" {
  description = "Artifact Registry repository for vinoguessr-web images."
  type        = string
  default     = "vinoguessr-web"
}

variable "web_github_repo" {
  description = "GitHub repo allowed to assume the web deployer service account, in `owner/name` form. Its owner ID is checked against var.github_repository_owner_id."
  type        = string
  default     = "vinoguessr/vinoguessr-web"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.web_github_repo))
    error_message = "web_github_repo must be in `owner/name` form, e.g. \"vinoguessr/vinoguessr-web\"."
  }
}

variable "web_github_repository_id" {
  description = "Numeric ID of var.web_github_repo (`gh api repos/<owner>/<name> --jq .id`)."
  type        = string
  default     = "1053443996"

  validation {
    condition     = can(regex("^[0-9]+$", var.web_github_repository_id))
    error_message = "web_github_repository_id must be the numeric repository ID."
  }
}

variable "web_bootstrap_image" {
  description = "Image used only when the web Cloud Run service is first created. vinoguessr-web's Deploy workflow then rolls out its own image; Terraform ignores image drift."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "web_memory" {
  description = "Memory limit for the web Cloud Run container."
  type        = string
  default     = "256Mi"
}

variable "web_max_instance_count" {
  description = "Maximum number of web Cloud Run container instances."
  type        = number
  default     = 3

  validation {
    condition     = var.web_max_instance_count >= 1
    error_message = "web_max_instance_count must be at least 1."
  }
}
