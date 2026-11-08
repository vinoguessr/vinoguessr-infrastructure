resource "google_iam_workload_identity_pool" "github" {
  depends_on = [google_project_service.required]

  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
  description               = "OIDC pool for GitHub Actions workflows."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.workflow_ref"        = "assertion.workflow_ref"
  }

  # Only the deploy workflow on the deploy branch of this repository may exchange tokens.
  # The numeric IDs stop a deleted-and-recreated repository with the same name from passing,
  # and workflow_ref stops other workflows on the same branch from minting deployer tokens.
  attribute_condition = join(" && ", [
    "assertion.repository == \"${var.github_repo}\"",
    "assertion.repository_id == \"${var.github_repository_id}\"",
    "assertion.repository_owner_id == \"${var.github_repository_owner_id}\"",
    "assertion.ref == \"${var.deploy_branch}\"",
    "assertion.workflow_ref == \"${var.github_repo}/${var.deploy_workflow}@${var.deploy_branch}\"",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Tokens that passed the provider's attribute_condition may impersonate the deployer SA.
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/${var.github_repo}"
}
