terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.2"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.identifier}"
  location = var.location
}

resource "azurerm_iothub" "main" {
  name                = "iot-${var.identifier}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = var.iothub.sku_name
    capacity = 1
  }

  route {
    name           = "default-endpoint"
    source         = "DeviceMessages"
    endpoint_names = ["events"]
    enabled        = true
  }
}

resource "azurerm_iothub_consumer_group" "for_func" {
  name                   = "functions"
  iothub_name            = azurerm_iothub.main.name
  eventhub_endpoint_name = "events"
  resource_group_name    = azurerm_resource_group.main.name
}

resource "azurerm_iothub_shared_access_policy" "for_func" {
  name                = "functions"
  resource_group_name = azurerm_resource_group.main.name
  iothub_name         = azurerm_iothub.main.name
  registry_read       = true
  registry_write      = false
  service_connect     = true
}

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.identifier}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "devices" {
  name                = "devices"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "telemeteries" {
  name                = "telemetries"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.devices.name
  partition_key_path  = "/device/id"
}

resource "random_string" "storage_for_func" {
  length  = 22
  upper   = false
  special = false
  keepers = {
    resource_group_id = azurerm_resource_group.main.id
  }
}

resource "azurerm_storage_account" "for_func" {
  name                     = "st${random_string.storage_for_func.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "for_func" {
  name                = "plan-${var.identifier}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "Y1"
  os_type             = "Windows"
}

resource "azurerm_windows_function_app" "main" {
  name                       = "func-${var.identifier}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.for_func.id
  storage_account_name       = azurerm_storage_account.for_func.name
  storage_account_access_key = azurerm_storage_account.for_func.primary_access_key

  site_config {
    application_stack {
      node_version = "~16"
    }
  }

  app_settings = {
    COSMOSDB_CONNECTION_STRING = azurerm_cosmosdb_account.main.primary_key
  }
}
