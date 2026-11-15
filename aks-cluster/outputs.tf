output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "get_credentials" {
  description = "Command to fetch kubeconfig."
  value       = "az aks get-credentials -g ${azurerm_resource_group.this.name} -n ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

output "kubernetes_version" {
  description = "Kubernetes minor version the cluster is pinned to (latest GA unless overridden)."
  value       = local.kubernetes_version
}

# Values the KEDA manifests need. Load them with:
#   eval "$(tofu output -raw keda_env)"
output "keda_env" {
  description = "Shell exports for rendering manifests/keda-*.yaml with envsubst \"$KEDA_SUBST\"."
  value       = <<-EOT
    export KEDA_STORAGE_ACCOUNT=${azurerm_storage_account.keda.name}
    export KEDA_OPERATOR_CLIENT_ID=${azurerm_user_assigned_identity.keda_operator.client_id}
    export KEDA_WORKER_CLIENT_ID=${azurerm_user_assigned_identity.keda_worker.client_id}
    export KEDA_SO_QUEUE=${azurerm_storage_queue.keda["scaledobject"].name}
    export KEDA_JOB_QUEUE=${azurerm_storage_queue.keda["scaledjob"].name}
    # Only these are substituted, so $VARS inside the job scripts survive envsubst.
    export KEDA_SUBST='$KEDA_STORAGE_ACCOUNT $KEDA_OPERATOR_CLIENT_ID $KEDA_WORKER_CLIENT_ID $KEDA_SO_QUEUE $KEDA_JOB_QUEUE'
  EOT
}
