 terraform {
  backend "azurerm" {
    resource_group_name  = "crud-rg"
    storage_account_name = "crudstoragetf"
    container_name      = "tfstate"
    key                 = "terraform.tfstate"
    subscription_id      = var.SUB_ID

  }
}