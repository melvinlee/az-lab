variable "subscription_id" {
  description = "Azure subscription ID. Null = use the Azure CLI's current subscription."
  type        = string
  default     = null
}

variable "name" {
  description = "Base name for the resource group and VM."
  type        = string
  default     = "ai-agent"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "southeastasia"
}

variable "vm_size" {
  description = "arm64 VM size. Must be an Arm64 SKU to match the Azure Linux arm64 image."
  type        = string
  default     = "Standard_D2ps_v5"
}

variable "admin_username" {
  description = "Admin user on the VM. Hermes is installed and runs as this user."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Public key for SSH. Password auth is disabled."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "Source CIDR allowed to SSH in. Null = the caller's current public IP (/32)."
  type        = string
  default     = null
}

variable "os_disk_size_gb" {
  description = "OS disk size. Hermes pulls Python, Node and tool runtimes, so the image default is tight."
  type        = number
  default     = 64
}

variable "tags" {
  type    = map(string)
  default = { purpose = "az-lab" }
}
