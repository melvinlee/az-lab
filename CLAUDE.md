# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

`az-lab` is a personal Azure lab / playground: a place for experiments, prototypes and learning exercises against Azure, not a production codebase.

## Layout and tooling

Each lab is a self-contained top-level directory with its own OpenTofu root module (`tofu`, not `terraform`), local state, and one resource group (`rg-<name>`) so teardown is a single `tofu destroy`. Auth comes from the Azure CLI (`az login`); the subscription defaults to `az account show` unless `subscription_id` is set.

Per-lab commands (run inside the lab directory):

```sh
tofu init
tofu fmt && tofu validate
tofu plan -out=tfplan      # review, then apply exactly that plan
tofu apply tfplan
tofu destroy
```

AKS operations (node pool rotation, version upgrades) take 8–15 minutes and hold the local state lock; run them in the background and don't start another plan until they finish.

## Labs

### `aks-cluster/`

AKS Free tier with node auto-provisioning (NAP, AKS-managed Karpenter). NAP constraints that shape the config: Azure CNI overlay + Cilium dataplane (kubenet/Calico unsupported), managed identity only, and the cluster **cannot be stopped**, so destroy it to stop costs.

- **Two layers of nodes.** `main.tf` defines the AKS system pool (`default_node_pool`: arm64 `Standard_D2ps_v6`, `only_critical_addons_enabled`). `karpenter.tf` defines Karpenter NodePools/AKSNodeClasses that provision every other node. AKS's own default NodePools are off (`default_node_pools = "None"`); AKS deletes them on that switch.
- **`karpenter.tf` is data-driven.** `local.nap_pools` holds per-pool settings (`archs`, `capacity_types`, `sku_names`, `limits`, `taints`, `budget`); shared rules live in `local.nap_common_requirements`. CRs are applied with `alekc/kubectl` (no CRDs needed at plan time), whose provider reads the cluster's `kube_config`, so plans need the cluster reachable. Change caps and pool rules here, not with `kubectl patch`.
  - `general`: amd64 only (workloads aren't multi-arch), spot then on-demand, pinned to `Standard_D4ls_v5` / `Standard_D4als_v6`, limit 8 CPU / 16Gi.
  - `system-burst`: arm64 to match the system pool, on-demand only, `CriticalAddonsOnly` taint.
- **Why `general` is pinned to 8 GiB sizes.** Karpenter counts an in-flight NodeClaim against `spec.limits` at the largest instance type it could become. With 16 GiB candidates allowed, one stuck launch (e.g. spot `SKUNotAvailable`) consumed the whole 16Gi cap and blocked every other pod. Keep candidate sizes small relative to the limits.
- **Kubernetes version** comes from `data.azurerm_kubernetes_service_versions` (latest GA), pinned to the **minor** version for both control plane and `orchestrator_version`, so the `patch` auto-upgrade channel doesn't cause drift. A new GA minor shows up as an in-place upgrade on the next plan. `var.kubernetes_version` overrides.
- **Changing the system pool `vm_size`** relies on `temporary_name_for_rotation`; without it the provider recreates the whole cluster.
- **KEDA** is the AKS-managed add-on (`workload_autoscaler_profile` in `main.tf`). Workload identity is deliberately off. The OIDC issuer isn't set in code but is on anyway: AKS enables it on every new 1.34+ cluster and it can't be disabled, so the plan shows `oidc_issuer_enabled = true`. The tests in `manifests/keda-*.yaml` use only cron and metrics-api triggers, so KEDA needs no Azure resources. Tests 1 and 2 share the ScaledObject name `inflate-cron` (2 replaces 1).
- **Scale test:** `kubectl apply -f manifests/inflate.yaml && kubectl scale deploy/inflate --replicas=10`, then `kubectl get nodeclaims -o wide` (stuck launches show the reason in the NodeClaim's `Launched` condition). Expect about 6 Running and the rest Pending at the 16Gi cap. Scale back to 0 afterwards; Karpenter removes empty nodes.

## Working in this repo

- Azure resources cost money. When creating a lab, include a clear teardown path (e.g. a single resource group per lab that can be deleted).
- Use the Microsoft Learn MCP tools to look up current Azure documentation and samples instead of relying on memory. For VM size comparisons, the public Azure Retail Prices API (`https://prices.azure.com/api/retail/prices`) gives live per-region on-demand and spot prices.
- No Claude attribution: no `Co-Authored-By` trailer in commits and no "Generated with Claude Code" line in commits, PRs, or issues.
