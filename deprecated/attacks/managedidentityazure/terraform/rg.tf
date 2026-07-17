

data "azurerm_client_config" "current" {}


#Read my target RG 

data "azurerm_resource_group" "rgruntime" {
  name     = "rg-service-crcr"

}

################################################################
# IF you are generating any secrets, you need to put them somewhere
# most ideally, you put them into a keyvault of the same lifecycle-stage as the asset the key belongs to
##################################################################


 
resource "azurerm_key_vault" "kvservice" {
  name                        = "kv-service-crcr"
  location                    = data.azurerm_resource_group.rgruntime.location
  resource_group_name         = data.azurerm_resource_group.rgruntime.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"


  network_acls {
    ip_rules = ["0.0.0.0/0" ] #change this
    default_action= "Deny"
    bypass = "AzureServices"
  }


   access_policy {
     tenant_id = data.azurerm_client_config.current.tenant_id
     ## Students you must look up your Users Object id in Entra ID and put it here
     object_id = var.myuser



     secret_permissions = [
       "Get",
       "List",
       "Restore",
       "Delete",
       "Set",
       "Recover",
       "Backup",
     ]


   }
   # We are giving this SP access over the current vault
    access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id



    secret_permissions = [
      "Get",
      "List",
      "Restore",
      "Delete",
      "Set",
      "Recover",
      "Backup",
      "Purge",
    ]


  }

 
tags     = local.common_tags

}

resource "azurerm_key_vault_access_policy" "user_assigned_identity" {
  key_vault_id            = azurerm_key_vault.kvservice.id
  tenant_id               = data.azurerm_client_config.current.tenant_id
  object_id               = azurerm_user_assigned_identity.aks.principal_id
  certificate_permissions = ["Get", "List"]
  key_permissions         = ["Get", "List"]
  secret_permissions      = ["Get", "List", "Set", "Delete"]
  storage_permissions     = ["Get", "List"]
}


