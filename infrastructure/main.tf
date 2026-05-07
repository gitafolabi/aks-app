module "ServicePrincipal" {
  source                 = "./modules/ServicePrincipal"
  service_principal_name = var.service_principal_name
}

# Data source to get the object ID and subscription ID of the current caller
data "azurerm_client_config" "current_caller" {}

resource "azurerm_role_assignment" "rolespn" {

  # Narrowing scope from Subscription to Resource Group for better security
  scope                = "/subscriptions/${data.azurerm_client_config.current_caller.subscription_id}/resourceGroups/${var.rgname}"
  role_definition_name = "Contributor"
  principal_id         = module.ServicePrincipal.service_principal_object_id
}

# Grant the Service Principal "Key Vault Secrets User" role on the Key Vault
# This allows the External Secrets Operator to pull secrets from the vault.
resource "azurerm_role_assignment" "sp_keyvault_secrets_user" {
  scope                = module.keyvault.keyvault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.ServicePrincipal.service_principal_object_id

  depends_on = [module.keyvault]
}

# Grant the current caller (Terraform runner) "Key Vault Secrets Officer" role on the Key Vault
# This allows Terraform to create/manage secrets in the Key Vault.
resource "azurerm_role_assignment" "terraform_runner_keyvault_secrets_officer" {
  scope                = module.keyvault.keyvault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current_caller.object_id

  depends_on = [module.keyvault]
}

module "keyvault" {
  source                      = "./modules/keyvault"
  keyvault_name               = var.keyvault_name
  location                    = var.location
  resource_group_name         = var.rgname
  service_principal_name      = var.service_principal_name
  service_principal_object_id = module.ServicePrincipal.service_principal_object_id
  service_principal_tenant_id = module.ServicePrincipal.service_principal_tenant_id

  depends_on = [
    module.ServicePrincipal
  ]
}

resource "azurerm_key_vault_secret" "example" {
  name         = module.ServicePrincipal.client_id
  value        = module.ServicePrincipal.client_secret
  key_vault_id = module.keyvault.keyvault_id
}

# Generate a secure, random password for the database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Provision the actual secrets required by the application
resource "azurerm_key_vault_secret" "db_user" {
  name         = "db-user"
  value        = var.db_username # Ensure this is defined in variables.tf
  key_vault_id = module.keyvault.keyvault_id

  depends_on = [
    module.keyvault,
    azurerm_role_assignment.terraform_runner_keyvault_secrets_officer
  ]
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = random_password.db_password.result
  key_vault_id = module.keyvault.keyvault_id

  depends_on = [
    module.keyvault,
    azurerm_role_assignment.terraform_runner_keyvault_secrets_officer
  ]
}

#create Azure Kubernetes Service
module "aks" {
  source                 = "./modules/aks/"
  service_principal_name = var.service_principal_name
  client_id              = module.ServicePrincipal.client_id
  client_secret          = module.ServicePrincipal.client_secret
  location               = var.location
  resource_group_name    = var.rgname

  depends_on = [
    module.ServicePrincipal
  ]

}

resource "local_file" "kubeconfig" {
  depends_on   = [module.aks]
  filename     = "./kubeconfig"
  content      = module.aks.config
  

  # Restrict permissions so only the owner can read/write the config
  file_permission = "0600"
}