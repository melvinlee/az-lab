# Karpenter (NAP) NodePools managed here so limits are enforced in code.
# Mirrors the AKS defaults ("default" -> general, "system-surge" -> system-burst; renamed to
# avoid colliding with the AKS-managed objects) plus limits and a per-node size cap.

locals {
  nap_common_requirements = [
    { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
    { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
    { key = "karpenter.azure.com/sku-family", operator = "In", values = ["D"] },
    { key = "karpenter.azure.com/sku-cpu", operator = "Lt", values = [tostring(var.nap_max_node_cpu + 1)] },
  ]

  nap_startup_taints = [
    { key = "node.cilium.io/agent-not-ready", value = "true", effect = "NoExecute" },
  ]

  nap_pools = {
    general = {
      description = "General purpose NodePool for workloads"
      mode        = "user"
      # NAP prefers spot when both are allowed, falling back to on-demand.
      capacity_types = ["spot", "on-demand"]
      budget         = "30%"
      limits         = var.nap_limits.general
      taints         = []
    }
    system-burst = {
      description    = "Surge capacity for system pods when the system pool is full"
      mode           = "system"
      capacity_types = ["on-demand"]
      budget         = "10%"
      limits         = var.nap_limits.system_burst
      taints         = [{ key = "CriticalAddonsOnly", value = "true", effect = "NoSchedule" }]
    }
  }
}

resource "kubectl_manifest" "aks_node_class" {
  for_each = local.nap_pools

  server_side_apply = true
  yaml_body = yamlencode({
    apiVersion = "karpenter.azure.com/v1beta1"
    kind       = "AKSNodeClass"
    metadata   = { name = each.key }
    spec       = { imageFamily = "Ubuntu" }
  })

  # Ensure default_node_pools = "None" has been applied first.
  depends_on = [azurerm_kubernetes_cluster.this]
}

resource "kubectl_manifest" "node_pool" {
  for_each = local.nap_pools

  server_side_apply = true
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name        = each.key
      annotations = { "kubernetes.io/description" = each.value.description }
    }
    spec = {
      limits = each.value.limits
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "0s"
        budgets             = [{ nodes = each.value.budget }]
      }
      template = {
        metadata = { labels = { "kubernetes.azure.com/mode" = each.value.mode } }
        spec = merge(
          {
            nodeClassRef = { group = "karpenter.azure.com", kind = "AKSNodeClass", name = each.key }
            expireAfter  = "Never"
            requirements = concat(local.nap_common_requirements, [
              { key = "karpenter.sh/capacity-type", operator = "In", values = each.value.capacity_types },
            ])
            startupTaints = local.nap_startup_taints
          },
          length(each.value.taints) > 0 ? { taints = each.value.taints } : {}
        )
      }
    }
  })

  depends_on = [kubectl_manifest.aks_node_class]
}
