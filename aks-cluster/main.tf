# Latest GA (non-preview) Kubernetes version AKS offers in this region.
data "azurerm_kubernetes_service_versions" "current" {
  location        = var.location
  include_preview = false
}

locals {
  # Pin to minor ("1.37"), not patch: the "patch" auto-upgrade channel then applies
  # patches without causing drift, and a new GA minor shows up as an in-place upgrade on plan.
  latest_minor       = join(".", slice(split(".", data.azurerm_kubernetes_service_versions.current.latest_version), 0, 2))
  kubernetes_version = coalesce(var.kubernetes_version, local.latest_minor)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name
  kubernetes_version  = local.kubernetes_version

  # Free control plane (no uptime SLA).
  sku_tier = "Free"

  # Node auto-provisioning = AKS-managed Karpenter.
  # NodePools are defined in karpenter.tf (with limits) instead of the
  # AKS-managed defaults, which have no limits and get reconciled by AKS.
  node_provisioning_profile {
    mode               = "Auto"
    default_node_pools = "None"
  }

  # System pool for critical add-ons only; Karpenter provisions workload nodes.
  default_node_pool {
    name = "system"
    # Lets vm_size changes rotate the pool in place instead of recreating the cluster.
    temporary_name_for_rotation  = "systemtmp"
    vm_size                      = var.system_node_vm_size
    orchestrator_version         = local.kubernetes_version
    node_count                   = var.system_node_count
    only_critical_addons_enabled = true
    os_disk_size_gb              = 64

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # NAP requires managed identity (service principals are unsupported).
  identity {
    type = "SystemAssigned"
  }

  # NAP supports Azure CNI (overlay recommended) with the Cilium dataplane;
  # kubenet and Calico are unsupported.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # AKS-managed KEDA add-on: operator, metrics API server and admission webhook in kube-system.
  workload_autoscaler_profile {
    keda_enabled = true
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  tags = var.tags
}
