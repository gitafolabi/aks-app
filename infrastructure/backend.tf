 terraform {
  backend "azurerm" {
    resource_group_name  = "crud-rg"
    storage_account_name = "crudstoragetf"
    container_name      = "tfstate"
    key                 = "terraform.tfstate"
    subscription_id      = "7c101cde-202f-446c-a3dd-00545f97f22c"

  }
}