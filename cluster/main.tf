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

resource "google_service_account" "immich_backup" {
  project      = "tomas-rojo"
  account_id   = "immich-backup"
  display_name = "Immich backup writer (homelab k3s)"
}

resource "google_storage_bucket_iam_member" "immich_backup_creator" {
  bucket = google_storage_bucket.immich_backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.immich_backup.email}"
}

resource "google_storage_bucket_iam_member" "immich_backup_viewer" {
  bucket = google_storage_bucket.immich_backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.immich_backup.email}"
}
