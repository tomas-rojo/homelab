module "argocd" {
  source = "./modules/argocd"
}

resource "google_storage_bucket" "immich_backups" {
  name                        = "trojo-immich-backups"
  location                    = "europe-west4"
  project                     = "tomas-rojo"
  uniform_bucket_level_access = true
  force_destroy               = false
  storage_class               = "ARCHIVE"
  lifecycle_rule {
    condition {
      age            = 365
      matches_prefix = ["db_backups/"]
    }
    action {
      type = "Delete"
    }
  }
}

data "google_project" "this" {
  project_id = "tomas-rojo"
}

resource "google_iam_workload_identity_pool" "homelab" {
  project                   = "tomas-rojo"
  workload_identity_pool_id = "homelab-k3s"
  display_name              = "Homelab k3s"
  description               = "Lets k3s ServiceAccounts authenticate to GCP without key files"
}

resource "google_iam_workload_identity_pool_provider" "k3s" {
  project                            = "tomas-rojo"
  workload_identity_pool_id          = google_iam_workload_identity_pool.homelab.workload_identity_pool_id
  workload_identity_pool_provider_id = "k3s-oidc"
  display_name                       = "k3s ServiceAccount tokens"

  # A projected ServiceAccount token's sub is system:serviceaccount:<ns>:<name>,
  # which becomes the principal:// identity granted access below.
  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  oidc {
    issuer_uri = "kubernetes.default.svc.cluster.local"

    # Regenerate with: kubectl get --raw /openid/v1/jwks
    # These are the cluster's SA token signing keys. Rebuilding k3s rotates them
    # and breaks the backup until this file is refreshed and re-applied.
    jwks_json = file("${path.module}/k3s-jwks.json")
  }
}

locals {
  immich_backup_principal = join("", [
    "principal://iam.googleapis.com/projects/${data.google_project.this.number}",
    "/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.homelab.workload_identity_pool_id}",
    "/subject/system:serviceaccount:immich:immich-backup",
  ])
}

resource "google_storage_bucket_iam_member" "immich_backup_creator" {
  bucket = google_storage_bucket.immich_backups.name
  role   = "roles/storage.objectCreator"
  member = local.immich_backup_principal
}

resource "google_storage_bucket_iam_member" "immich_backup_viewer" {
  bucket = google_storage_bucket.immich_backups.name
  role   = "roles/storage.objectViewer"
  member = local.immich_backup_principal
}