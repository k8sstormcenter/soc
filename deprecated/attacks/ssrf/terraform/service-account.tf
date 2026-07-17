# Create a Service Account
resource "google_service_account" "cluster_service_account" {
  account_id   = "user-service"
  display_name = "Service Account for GKE Managed Identity"
  project      = var.project_id
}


# We add the KSA to be eligible to be bound to a GCP service account via workload identity
resource "google_service_account_iam_member" "workload_identity_ksa_iam_member" {
  service_account_id = google_service_account.cluster_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[users/user-service]"
}