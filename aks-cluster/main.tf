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
  kubernetes_version  = var.kubernetes_version

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

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  tags = var.tags
}
