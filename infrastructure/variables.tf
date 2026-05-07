variable "rgname" {
  type        = string
  description = "resource group name"
}

variable "location" {
  type    = string
  default = "WestEurope"
}

variable "service_principal_name" {
  type = string
}

variable "keyvault_name" {
  type = string
}

variable "SUB_ID" {
  type = string
}

variable "db_username" {
  type        = string
  description = "The database admin username"
}
