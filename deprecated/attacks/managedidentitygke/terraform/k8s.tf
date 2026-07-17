

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  project_id                 = var.gcp_project_id
  name                       = "k8s-${var.layer}-${var.env}"
  region                     = var.region
  zones                      = ["${var.region}-b"]
  network                    = "adls-vpc-${var.layer}-${var.env}"
  subnetwork                 = "vpc-snet-${var.layer}-${var.env}"
  ip_range_pods              = "vpc-snet-sec2-${var.layer}-${var.env}"
  ip_range_services          = "vpc-snet-sec1-${var.layer}-${var.env}"
  kubernetes_version         = "latest"
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  datapath_provider          = "ADVANCED_DATAPATH"  #means cilium
  release_channel            = "RAPID"
  filestore_csi_driver       = false
  grant_registry_access      = false
  sandbox_enabled            = false
  enable_private_endpoint    = false
  deletion_protection        = false
  monitoring_enable_managed_prometheus = false
  enable_intranode_visibility = false
  gateway_api_channel        = null  # it doesnt support HTTPS natively, so 
  monitoring_enable_observability_metrics = false
  cluster_telemetry_type     = "DISABLED"
  monitoring_enabled_components = []
  logging_enabled_components = [] 
  enable_cilium_clusterwide_network_policy = true


  master_ipv4_cidr_block     = "172.16.0.0/28" 
  master_authorized_networks = [

                                  { cidr_block   = var.runner_ip
                                  display_name = "github"}
                              
                               ]

  database_encryption = [
    {
      "key_name" : google_kms_crypto_key.key_ephemeral.id,
      "state" : "ENCRYPTED"
    }
  ]

  node_pools = [
    {
      name                      = "default-node-pool"
      machine_type              = "e2-medium"
      node_locations            = "${var.region}-b"
      horizontal_pod_autoscaling = false
      sandbox_enabled            = false
      max_count                 = 2
      spot                      = false
      disk_size_gb              = 100
      disk_type                 = "pd-standard"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      service_account           = "project-service-account@${var.gcp_project_id}.iam.gserviceaccount.com"
      preemptible               = false 
      node_count                = 1
    },
        {
      name                      = "user-pool"
      machine_type              = "n1-standard-2"
      node_locations            = "${var.region}-b"
      min_count                 = 0
      max_count                 = 3
      local_ssd_count           = 0
      spot                      = true
      sandbox_enabled            = false
      horizontal_pod_autoscaling = true
      disk_size_gb              = 100
      disk_type                 = "pd-standard"
      image_type                = "COS_CONTAINERD"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      service_account           = "project-service-account@${var.gcp_project_id}.iam.gserviceaccount.com"
      initial_node_count        = 2
      node_count                = 2
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }


}


# # Create a Service Account

resource "google_service_account" "cluster_service_account" {

  account_id   = "pacman-rancher"
  display_name = "Service Account for GKE Managed Identity"
  project      = var.gcp_project_id
}


# We add the KSA to be eligible to be bound to a GCP service account via workload identity
resource "google_service_account_iam_member" "workload_identity_ksa_iam_member" {
  service_account_id = google_service_account.cluster_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[pacman/pacman-rancher]"
}
 # Create a Role Binding for the Google Service Account
 # here we use the Terraform Google Upstream module default implementation, MITIGATION: apply the key-ring scope correctly
resource "google_project_iam_member" "workload_identity_sa_project_member" {
   project = var.gcp_project_id
   role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
   member  = "serviceAccount:pacman-rancher@${var.gcp_project_id}.iam.gserviceaccount.com"
 }

# Define the Cloud SQL instance
 resource "google_sql_database_instance" "default" {
   project           = var.gcp_project_id
   name             = "storm-cloudsql-instance"
   region           = var.region
   database_version = "POSTGRES_16"
   settings {
     tier = "db-f1-micro" # Adjust tier based on your needs
   }
    
   database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
   deletion_protection = false 
   encryption_key_name  = google_kms_crypto_key.key_ephemeral.id
  
 }

resource "google_sql_database" "default" {
  project  = var.gcp_project_id
  name     = "storm-cloud-sqldb"
  instance = "storm-cloudsql-instance"

}


resource "google_sql_user" "iam_service_account_user" {
  # Note: for PostgreSQL only, Google Cloud requires that you omit the
  # ".gserviceaccount.com" suffix
  # from the service account email due to length limits on database usernames.
  name     = "serviceAccount:pacman-rancher@${var.gcp_project_id}.iam"
  instance = google_sql_database_instance.default.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Define the Cloud SQL database
resource "google_sql_database" "default" {
  project  = var.gcp_project_id
  name     = "storm-cloud-sqldb"
  instance = "storm-cloud-sql"

}

# We want to iam role bind our service account pacman-rancher to the Cloud SQL database
resource "google_project_iam_member" "cloudsqlclient" {
  project   = var.gcp_project_id
  role     = "roles/cloudsql.client"
  member  = "serviceAccount:pacman-rancher@${var.gcp_project_id}.iam.gserviceaccount.com"
}
resource "google_project_iam_binding" "cloud_sql_user" {
  project = data.google_project.project.project_id
  role    = "roles/cloudsql.instanceUser"
  members = [
    "serviceAccount:pacman-rancher@${var.gcp_project_id}.iam.gserviceaccount.com"
  ]
}





