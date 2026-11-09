# vinoguessr-infrastructure

Terraform for the VinoGuessr production environment: Cloud Run (the API and the web), Artifact Registry, Secret Manager, IAM, Workload Identity Federation, the external HTTPS Load Balancer with Cloud Armor and Certificate Manager, and Cloudflare DNS for `vinoguessr.com`.

## How it fits together

- **Images and rollouts**: `vinoguessr-api`'s GitHub Actions builds the image, pushes it to Artifact Registry, applies Atlas migrations, and runs `gcloud run services update --image=...`. `vinoguessr-web`'s GitHub Actions does the same for the web, without migrations. Terraform ignores drift in the running images.
- **Authentication**: Workload Identity Federation. No long-lived JSON keys. Only the Deploy workflow (`.github/workflows/deploy.yml`) running on the `main` branch of `vinoguessr/vinoguessr-api`, checked by repository name, repository ID, and owner ID, can impersonate the API's deployer service account. A second provider (`github-web`) admits only the same workflow of `vinoguessr/vinoguessr-web`, which can impersonate only the web's deployer.
- **Running Terraform**: locally by the owner, after explicit approval. GitHub Actions never runs `terraform apply`; PRs run only `fmt` / `init -backend=false` / `validate`.
- **Environment**: production only.
- **Observability**: an OpenTelemetry Collector sidecar on Cloud Run. Its configuration (`otel/collector-config.yaml`) is not secret and is stored as a Secret Manager version by Terraform.
- **Public path**: `api.vinoguessr.com` and `vinoguessr.com` are Cloudflare proxied DNS records → Google global external HTTPS Load Balancer → Cloud Run serverless NEGs (the API and the web). Cloud Armor allows only Cloudflare proxy IPs.
- **Passkey relying party**: `vinoguessr.com` is the passkey RP ID (ADR-0005) and is served by vinoguessr-web, except `/.well-known/apple-app-site-association`, which the load balancer routes to the API so it is generated from the same `APPLE_APP_ID` the API uses.
- **Exposure**: `allow_unauthenticated = true` stays on. With `restrict_direct_cloud_run_ingress = true` (the default), both Cloud Run services accept traffic only through the load balancer and reject direct `*.run.app` access.

## Bootstrapping a new project

These steps build the environment in an empty project (`vinoguessr`). Run every `terraform apply` only after the owner approves it.

Before starting:

- Link a billing account to the project.
- If the project belongs to an organization, an organization policy such as `iam.allowedPolicyMemberDomains` can reject the `allUsers` Cloud Run invoker binding. Check the policies before step 10.

### 0. Shell variables

Export these first; when you resume in a new terminal, start here again.

```sh
export PROJECT_ID="vinoguessr"
export REGION="asia-northeast1"
export STATE_BUCKET="${PROJECT_ID}-tfstate"
# Token with DNS edit access to vinoguessr.com; read it without echoing so it stays out of shell history.
read -rs CLOUDFLARE_API_TOKEN && export CLOUDFLARE_API_TOKEN
```

### 1. Authenticate as a project Owner

Use a dedicated gcloud configuration, so other accounts and their Application Default Credentials stay untouched, and hand Terraform a short-lived access token from it. The Google provider and the GCS backend both read `GOOGLE_OAUTH_ACCESS_TOKEN`.

```sh
gcloud config configurations create "$PROJECT_ID" --no-activate  # first time only
gcloud auth login --configuration="$PROJECT_ID"                   # first time only
export CLOUDSDK_ACTIVE_CONFIG_NAME="$PROJECT_ID"
gcloud config set project "$PROJECT_ID"
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud config config-helper --force-auth-refresh --format='value(credential.access_token)')"
```

`--force-auth-refresh` mints a new token valid for an hour; `gcloud auth print-access-token` would return a cached one that may expire within minutes, in the middle of an apply. Export it again right before each later `terraform` command. When you resume in a new terminal, run step 0 and the last three lines here again.

### 2. Enable the APIs Terraform needs to start

Terraform enables the remaining APIs with `google_project_service`, but these three must be enabled by hand first, or `terraform init` and the first `apply` fail.

```sh
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com
```

### 3. Create the state bucket

Bucket names are globally unique; `<PROJECT_ID>-tfstate` rarely collides.

```sh
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --location="$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

### 4. Create the variables file

```sh
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

Set `project_number` to the output of `gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)'`, and `cloudflare_zone_id` to the zone ID of `vinoguessr.com`. Leave the `image_tag` placeholder in place until step 9: the variable has no default, so removing or commenting it out makes even the targeted apply in step 6 fail with "No value for required variable". The Cloudflare provider reads `CLOUDFLARE_API_TOKEN` from the environment and needs DNS edit access. It is a different token from the `CLOUDFLARE_API_TOKEN` secret the app reads from Secret Manager; they do not need to match.

Terraform does not change Cloudflare's SSL/TLS mode. Confirm it is `Full (strict)` in the Cloudflare dashboard before publishing `api.vinoguessr.com`.

### 5. `terraform init`

```sh
terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="prefix=vinoguessr"
```

### 6. Create everything except Cloud Run

Cloud Run cannot be created until its image exists, and secrets need a version before a revision can start. Create the APIs, the Artifact Registry repository, the secret containers, the OTel Collector configuration version, and the deployer identity first.

```sh
terraform apply \
  -target=google_project_service.required \
  -target=google_artifact_registry_repository.app \
  -target=google_secret_manager_secret.app \
  -target=google_secret_manager_secret.otel_collector_config \
  -target=google_secret_manager_secret_version.otel_collector_config \
  -target=google_iam_workload_identity_pool.github \
  -target=google_iam_workload_identity_pool_provider.github \
  -target=google_service_account.deployer \
  -target=google_service_account.runtime \
  -target=google_service_account_iam_member.deployer_wif \
  -target=google_service_account_iam_member.deployer_actas_runtime \
  -target=google_artifact_registry_repository_iam_member.deployer_ar_writer \
  -target=google_secret_manager_secret_iam_member.deployer_postgres_password_access
```

### 7. Upload secret values

Terraform creates only the secret containers. Add the values by hand without echoing them, so they never appear on screen or in shell history.

Generate the two keys rather than copying them from another environment. `OTP_SECRET_KEY` is a Base64 32-byte HMAC key; `EDDSA_PRIVATE_KEY` is an unpadded Base64URL 32-byte Ed25519 private key on a single line.

```sh
openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add OTP_SECRET_KEY --data-file=-
openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=\n' | gcloud secrets versions add EDDSA_PRIVATE_KEY --data-file=-
```

For the rest, paste each value and press Enter:

```sh
for secret in POSTGRES_PASSWORD VALKEY_PASSWORD CLOUDFLARE_API_TOKEN; do
  printf '%s: ' "$secret"
  read -rs value && printf '%s' "$value" | gcloud secrets versions add "$secret" --data-file=-
  unset value
done
```

### 8. Point `vinoguessr-api`'s deploy workflow at the new project

In `vinoguessr/vinoguessr-api` → Settings → Secrets and variables → Actions → **Variables** (WIF settings are not secret):

| Variable | Source |
|---|---|
| `GOOGLE_CLOUD_PROJECT` | `project_id` in `terraform.tfvars` |
| `GOOGLE_CLOUD_REGION` | `region` in `terraform.tfvars` |
| `GOOGLE_CLOUD_SERVICE_NAME` | `service_name` in `terraform.tfvars` (default `vinoguessr-api`) |
| `GOOGLE_CLOUD_ARTIFACT_REPO` | `artifact_repo_id` in `terraform.tfvars` (default `vinoguessr-api`) |
| `GOOGLE_CLOUD_WIF_PROVIDER` | `terraform output -raw wif_provider` |
| `GOOGLE_CLOUD_DEPLOYER_SA` | `terraform output -raw deployer_sa_email` |

The Deploy workflow also applies Atlas migrations with `POSTGRES_HOSTNAME`, `POSTGRES_USER`, `POSTGRES_DB`, and `ATLAS_BASELINE_VERSION`, and reads `POSTGRES_PASSWORD` from Secret Manager. They must point at the same database as `app_env` in `terraform.tfvars`. When reusing the existing database, keep them as they are. For a new, empty database, update them and remove `ATLAS_BASELINE_VERSION`, so Atlas applies the baseline migration instead of skipping it.

### 9. Push the first image

Run the Deploy workflow on `main` of `vinoguessr-api`:

```sh
gh workflow run deploy.yml -R vinoguessr/vinoguessr-api --ref main
```

It builds and pushes `vinoguessr-api:<commit SHA>` and applies migrations; its final `gcloud run services update` step fails because the service does not exist yet. That failure is expected until step 10.

From step 8 on, every Deploy run (a push to `main`, the daily 21:00 UTC schedule, or a manual run) targets the new project, and the old project no longer receives deploys.

Wait until that run has finished. Filter by event so the newest push or scheduled run is not picked up instead, then list its steps:

```sh
gh run list -R vinoguessr/vinoguessr-api --workflow deploy.yml --event workflow_dispatch --branch main \
  --limit 1 --json databaseId,headSha,url
gh run view <databaseId> -R vinoguessr/vinoguessr-api --json jobs \
  --jq '.jobs[].steps[] | "\(.conclusion)\t\(.name)"'
```

"Build and push image" and "Apply database migrations" must be `success`; "Require main" is `skipped` on main, and "Update Cloud Run service image" fails as expected. A failed migration means the database is unreachable or step 7's `POSTGRES_PASSWORD` or step 8's database variables are wrong, and Cloud Run would start against an unmigrated database, so fix it and run the workflow again. Then set `image_tag` in `terraform.tfvars` to the run's full 40-character `headSha` (`github.sha`).

### 10. Apply everything with direct ingress open

The first full apply creates both Cloud Run services (the web starts from a placeholder image until step 12), the load balancer, Cloud Armor, Certificate Manager, and the Cloudflare DNS records for `api.vinoguessr.com` and `vinoguessr.com`. Add this to `terraform.tfvars` temporarily so the service is reachable while the certificates are issued. If an `api.vinoguessr.com` or `vinoguessr.com` record already exists in Cloudflare, delete or import it first.

```hcl
restrict_direct_cloud_run_ingress = false
```

```sh
terraform apply
terraform output -raw api_health_url
```

Wait until both certificates and certificate map entries are `ACTIVE`, `https://api.vinoguessr.com/health` returns 200, and the association file is served without a redirect (Apple does not follow redirects for it). Issuance can take from a few minutes to an hour.

```sh
curl -sS -o /dev/null -w '%{http_code} %{content_type}\n' "$(terraform output -raw site_association_url)"  # expect 200 application/json
curl -sS -o /dev/null -w '%{http_code}\n' https://vinoguessr.com/                                          # expect 200 (the placeholder page)
```

Apple fetches the association file through its CDN, and Cloudflare's bot protection can challenge that fetcher. Before relying on passkeys, make sure Bot Fight Mode, Browser Integrity Check, and "Block AI bots" do not apply to `vinoguessr.com/.well-known/apple-app-site-association` (Bot Fight Mode cannot be skipped per path on the Free plan, so turn it off for the zone if needed), then confirm what Apple cached:

```sh
curl -sS https://app-site-association.cdn-apple.com/a/v1/vinoguessr.com  # expect the same JSON, listing PU5HXZ4FZ2.com.vinoguessr.app
```

### 11. Restrict direct ingress

Remove `restrict_direct_cloud_run_ingress = false` from `terraform.tfvars` and apply again. Leaving direct ingress open with `allow_unauthenticated = true` lets requests bypass Cloudflare and Cloud Armor, so `CF-Connecting-IP` can no longer be trusted.

```sh
terraform apply
```

`https://api.vinoguessr.com` keeps working, and direct `*.run.app` access is rejected by Cloud Run ingress. From now on, `vinoguessr-api`'s Deploy workflow rolls out new images.

### 12. Deploy vinoguessr-web

In `vinoguessr/vinoguessr-web` → Settings → Secrets and variables → Actions → **Variables**:

| Variable | Source |
|---|---|
| `GOOGLE_CLOUD_PROJECT` | `project_id` in `terraform.tfvars` |
| `GOOGLE_CLOUD_REGION` | `region` in `terraform.tfvars` |
| `GOOGLE_CLOUD_SERVICE_NAME` | `web_service_name` in `terraform.tfvars` (default `vinoguessr-web`) |
| `GOOGLE_CLOUD_ARTIFACT_REPO` | `web_artifact_repo_id` in `terraform.tfvars` (default `vinoguessr-web`) |
| `GOOGLE_CLOUD_WIF_PROVIDER` | `terraform output -raw web_wif_provider` |
| `GOOGLE_CLOUD_DEPLOYER_SA` | `terraform output -raw web_deployer_sa_email` |

Then run its Deploy workflow on `main` and check that every step succeeded ("Require main" is `skipped` on main):

```sh
gh workflow run deploy.yml -R vinoguessr/vinoguessr-web --ref main
gh run list -R vinoguessr/vinoguessr-web --workflow deploy.yml --event workflow_dispatch --branch main \
  --limit 1 --json databaseId,headSha,url
gh run view <databaseId> -R vinoguessr/vinoguessr-web --json jobs \
  --jq '.jobs[].steps[] | "\(.conclusion)\t\(.name)"'
```

`https://vinoguessr.com/` now serves vinoguessr-web, and the association file is still the API's (200, `application/json`, no redirect). From now on, `vinoguessr-web`'s Deploy workflow rolls out new web images.

## Day-to-day operations

Every command below assumes step 0 and the last three lines of step 1 have been run in the current terminal, so gcloud uses the project's configuration and Terraform has a fresh access token. Refresh the token right before each `terraform` command.

### Configuration changes

Change Cloud Run environment variables, scaling, resources, or the OTel Collector configuration in `terraform.tfvars`, `*.tf`, or `otel/collector-config.yaml`, and run `terraform apply` after approval. This is independent of image rollouts, because Terraform ignores the app image.

A change to `otel/collector-config.yaml` creates a new Secret Manager version, and Cloud Run mounts that exact version, so the apply rolls out a new revision whose Collector starts with the new configuration. Old versions are kept (`deletion_policy = "ABANDON"`) so earlier revisions can still start; disable them by hand once no revision uses them.

### Updating providers

The shared Terraform workflow runs `terraform init -lockfile=readonly` on Linux, so the lockfile must already contain hashes for every platform that runs Terraform. After changing provider versions, regenerate it:

```sh
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

### Rotating a secret

Generate a new `OTP_SECRET_KEY` or `EDDSA_PRIVATE_KEY` with the commands in step 7, so the key never appears on screen. Rotating `EDDSA_PRIVATE_KEY` invalidates every token already issued, so every user has to sign in again; rotating `OTP_SECRET_KEY` only invalidates one-time codes still in flight. Paste any other secret without echoing it:

```sh
read -rs value && printf '%s' "$value" | gcloud secrets versions add <secret-id> --data-file=-; unset value
```

App secrets reference `version = "latest"`, and Cloud Run resolves it when each instance starts, not per revision. Until every instance is replaced, newly started instances use the new value while running ones keep the old one; for `EDDSA_PRIVATE_KEY`, tokens then fail depending on which instance serves the request. So right after adding the version, always roll out a new revision with a no-op update. It keeps the running image and waits until the new revision serves traffic:

```sh
gcloud run services update vinoguessr-api --region="$REGION" --update-env-vars=SECRET_ROTATED_AT="$(date +%s)"
```

The next `terraform apply` removes `SECRET_ROTATED_AT` again, which rolls out one more revision with the same values. Prefer this over the Deploy workflow, which redeploys `main` and runs migrations first, and rolls out nothing if either fails.

### Rolling back the image

With step 0 and the last three lines of step 1 run in this terminal:

```sh
gcloud run services update vinoguessr-api \
  --region="$REGION" \
  --image="$REGION-docker.pkg.dev/$PROJECT_ID/vinoguessr-api/vinoguessr-api:<OLD_SHA>"
```

The web rolls back the same way with `vinoguessr-web` in place of `vinoguessr-api` (service, repository, and image name).

The next Deploy run (a push to `main`, or the nightly schedule: 21:00 UTC for the API, 21:30 UTC for the web) redeploys `main` and undoes the rollback. Keep it by disabling that repository's Deploy workflow (`gh workflow disable deploy.yml -R vinoguessr/<repository>`) until a fix or revert is on `main`, then enable it again.

<!-- vinoguessr-foundation -->
## Scope

Infrastructure code: Terraform / Google Cloud Run / Cloudflare / OpenTelemetry.

## Architecture

The VinoGuessr API and PostgreSQL are the source of truth for business data. Never expose credentials in Terraform state, plans, logs, or the repository. `vinoguessr-api`'s GitHub Actions builds container images and rolls them out to Cloud Run, and Terraform ignores drift in the running image.

## Verification

After implementing, run `terraform fmt -check -recursive` / `terraform init -backend=false` / `terraform validate`. Do not run apply, production deploys, billed resource creation, or broad IAM grants without explicit approval.

Follow [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md): satisfy the Issue's dependencies, then implement with an independent Review Agent running in parallel. Shared rules source: [vinoguessr/.github@01fd9c61bce2](https://github.com/vinoguessr/.github/tree/01fd9c61bce2139beb8ea173339d45c02d49b69f).
