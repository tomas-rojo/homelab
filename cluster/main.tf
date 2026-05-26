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
}
