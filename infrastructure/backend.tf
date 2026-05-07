 terraform {
  backend "azurerm" {
    resource_group_name  = "crud-rg"
    storage_account_name = "crudstorage123"
    container_name      = "tfstate"
    key                 = "terraform.tfstate"
  }
}