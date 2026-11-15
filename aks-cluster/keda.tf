# Azure side of the KEDA test cases (README "KEDA"): a storage account with two queues and
# two user-assigned identities federated to Kubernetes service accounts. Everything lives in
# rg-aks-lab so `tofu destroy` still removes it all.

data "azurerm_client_config" "current" {}

locals {
  # Storage account names are global, 3-24 lowercase alphanumerics. A hash of the RG ID keeps
  # the name stable across plans and unique per subscription without a random provider.
  keda_storage_account_name = substr("st${replace(var.name, "-", "")}${substr(sha1(azurerm_resource_group.this.id), 0, 8)}", 0, 24)

  keda_queues = {
    scaledobject = "keda-scaledobject" # test 3: scales a Deployment on queue length
    scaledjob    = "keda-scaledjob"    # test 4: one Job per message
  }
}

resource "azurerm_storage_account" "keda" {
  name                            = local.keda_storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_queue" "keda" {
  for_each = local.keda_queues

  name               = each.value
  storage_account_id = azurerm_storage_account.keda.id
}

# Lets whoever runs tofu push and clear test messages with `az storage message ... --auth-mode login`.
resource "azurerm_role_assignment" "keda_user_queue_contributor" {
  scope                = azurerm_storage_account.keda.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- KEDA operator identity: reads queue length to make scaling decisions -------------------

resource "azurerm_user_assigned_identity" "keda_operator" {
  name                = "id-${var.name}-keda-operator"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

# Read-only: the scaler only peeks and counts messages. Test 5 deletes this assignment to
# check that the ScaledObject goes Ready=False with an auth error.
resource "azurerm_role_assignment" "keda_operator_queue_reader" {
  scope                = azurerm_storage_account.keda.id
  role_definition_name = "Storage Queue Data Reader"
  principal_id         = azurerm_user_assigned_identity.keda_operator.principal_id
}

# The AKS add-on runs the operator as kube-system/keda-operator. TriggerAuthentications pass
# this identity's client ID as identityId, so the AKS-managed service account isn't annotated.
resource "azurerm_federated_identity_credential" "keda_operator" {
  name                      = "keda-operator"
  user_assigned_identity_id = azurerm_user_assigned_identity.keda_operator.id
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:kube-system:keda-operator"
  audience                  = ["api://AzureADTokenExchange"]
}

# --- Worker identity: ScaledJob pods dequeue and delete messages -----------------------------

resource "azurerm_user_assigned_identity" "keda_worker" {
  name                = "id-${var.name}-keda-worker"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

# Separate from the operator identity so the operator stays read-only and test 5's role
# removal only breaks scaling, not message processing.
resource "azurerm_role_assignment" "keda_worker_queue_processor" {
  scope                = azurerm_storage_queue.keda["scaledjob"].id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azurerm_user_assigned_identity.keda_worker.principal_id
}

resource "azurerm_federated_identity_credential" "keda_worker" {
  name                      = "keda-worker"
  user_assigned_identity_id = azurerm_user_assigned_identity.keda_worker.id
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:default:keda-worker"
  audience                  = ["api://AzureADTokenExchange"]
}
