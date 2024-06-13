terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.92.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">=2.10.0"
    }
  }
}


provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.app_name}rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.app_name}aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.app_name}-aks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  storage_profile {
    blob_driver_enabled = true
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }
}

resource "azurerm_storage_account" "nifi" {
  name                     = "${var.app_name}nifisa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "nifi_registry_flows" {
  name                  = "nifi-registry-flows"
  storage_account_name  = azurerm_storage_account.nifi.name
  container_access_type = "private"
}


resource "kubernetes_namespace" "nifi" {
  depends_on = [azurerm_kubernetes_cluster.main]
  metadata {
    name = "nifi"
  }
}

resource "kubernetes_secret" "storage_account_credentials" {
  depends_on = [azurerm_kubernetes_cluster.main]
  metadata {
    name      = "storage-account-credentials"
    namespace = kubernetes_namespace.nifi.metadata[0].name 
  }
  data = {
    azurestorageaccountname = azurerm_storage_account.nifi.name
    azurestorageaccountkey  = azurerm_storage_account.nifi.primary_access_key
  }
  type = "Opaque"
}



resource "helm_release" "nifi" {
  depends_on = [azurerm_kubernetes_cluster.main]
  name       = "nifi"
  repository = "https://cetic.github.io/helm-charts"
  chart      = "nifi"
  namespace  = "nifi"
  values     = [file("${path.module}/../nifi/values.yaml")]
  timeout = 600
  wait = false
  atomic = false
}


