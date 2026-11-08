provider "cloudflare" {}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed_by = "terraform"
    service    = "vinoguessr-api"
  }
}
