
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "k8s-crcr"
  location            = data.azurerm_resource_group.rgruntime.location
  resource_group_name = data.azurerm_resource_group.rgruntime.name
  dns_prefix          = "k8s-crcr"
  workload_identity_enabled = true
  oidc_issuer_enabled  = true
  http_application_routing_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D4s_v3"
    vnet_subnet_id = azurerm_subnet.snet-student-aks.id
  }

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }


  network_profile {
    pod_cidr            = "10.3.0.0/22"
    service_cidr        = "10.3.4.0/24"
    dns_service_ip      = "10.3.4.10"
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    ebpf_data_plane     = "cilium"
  }
  
api_server_access_profile{
  authorized_ip_ranges = ["89.144.193.145/32"]
}
  
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  azure_policy_enabled              = false
  role_based_access_control_enabled = true
  
    tags         = local.common_tags
}


resource "azurerm_user_assigned_identity" "aks" {
  name                = "aks-identity"
  resource_group_name = data.azurerm_resource_group.rgruntime.name
  location            = data.azurerm_resource_group.rgruntime.location
}
output "clientId" {
  value = azurerm_user_assigned_identity.aks.client_id
}

resource "azurerm_federated_identity_credential" "aks" {
  name                = "aksfederatedidentity"
  resource_group_name = data.azurerm_resource_group.rgruntime.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.aks.id
  subject             = "system:serviceaccount:pacman:pacman-rancher" 
}


resource "azurerm_log_analytics_workspace" "crcr" {
  name                = "crcr-log-analytics"
  location            = data.azurerm_resource_group.rgruntime.location
  resource_group_name = data.azurerm_resource_group.rgruntime.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


