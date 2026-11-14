variable "subscription_id" {
  description = "Azure subscription ID. Null = use the Azure CLI's current subscription."
  type        = string
  default     = null
}

variable "name" {
  description = "Base name for the resource group and cluster."
  type        = string
  default     = "aks-lab"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "southeastasia"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Null = AKS default."
  type        = string
  default     = null
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool (arm64 Cobalt 100; Karpenter/NAP provisions the workload nodes)."
  type        = string
  default     = "Standard_D2ps_v6"
}

variable "system_node_count" {
  description = "Number of system nodes. 1 is fine for a lab."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = { purpose = "az-lab" }
}

variable "nap_limits" {
  description = "Total CPU/memory Karpenter may provision per NodePool. Caps over-provisioning."
  type = object({
    general      = object({ cpu = string, memory = string })
    system_burst = object({ cpu = string, memory = string })
  })
  default = {
    general      = { cpu = "8", memory = "16Gi" }
    system_burst = { cpu = "4", memory = "16Gi" }
  }
}

variable "nap_max_node_cpu" {
  description = "Largest VM (vCPUs) Karpenter may pick for a single node."
  type        = number
  default     = 4
}
