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
  description = "Admin user on the VM. Owns ~/.hermes (the container's data volume); the container's hermes user is remapped to its UID/GID."
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
  description = "OS disk size. Holds the Hermes image (1.1 GB compressed, several GB unpacked), the previous image for rollback, and ~/.hermes."
  type        = number
  default     = 64
}

# Pinned by the multi-arch index digest (linux/amd64 + linux/arm64), so a re-pushed tag
# can't change what runs; the tag is kept for readability. Docker uses the digest.
variable "hermes_image" {
  description = "Hermes Agent container image (initial value of HERMES_IMAGE in /etc/hermes/hermes.env). Changing it replaces the VM."
  type        = string
  default     = "docker.io/nousresearch/hermes-agent:v0.23.3@sha256:3e9fe4c6ef36490f43aa0d0d80f9df64e9c92a576eee3042f1a97c8813c05355"
}

variable "tags" {
  type    = map(string)
  default = { purpose = "az-lab" }
}
