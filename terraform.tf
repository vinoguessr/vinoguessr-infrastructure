terraform {
  required_version = "~> 1.14"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }

    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  backend "gcs" {
    # bucket and prefix are supplied via `terraform init -backend-config=...`.
    # See Terraform/README.md §5 for the exact init command.
  }
}
