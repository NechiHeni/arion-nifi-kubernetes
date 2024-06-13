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

resource "kubernetes_namespace" "nifi" {
  depends_on = [azurerm_kubernetes_cluster.main]
  metadata {
    name = "nifi"
  }
}

resource "azurerm_public_ip" "nifi_lb_ip" {
  name                = "nifi-lb-ip"
  resource_group_name = "MC_arionnifirg_arionnifiaks_eastus"
  location            = "East US"
  allocation_method   = "Static"
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

  set {
    name  = "service.loadBalancerIP"
    value = azurerm_public_ip.nifi_lb_ip.ip_address
  }
}


