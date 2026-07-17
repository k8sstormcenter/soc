# Create new secret manager secret
resource "google_secret_manager_secret" "secret-basic" {
  project   = var.project_id
  secret_id = "session-secret"

  replication {
    auto {}
  }
}

# Create new secret manager secret version and add the secret data
resource "google_secret_manager_secret_version" "secret-basic-version" {
  secret      = google_secret_manager_secret.secret-basic.name
  secret_data = "very secret secret"
}


# Create a Role Binding for the Google Service Account to access the Secret Manager
resource "google_secret_manager_secret_iam_binding" "binding" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.secret-basic.name
  role      = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:${google_service_account.cluster_service_account.email}",
  ]
}