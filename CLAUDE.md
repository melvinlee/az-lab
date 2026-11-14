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
tofu plan
tofu apply
tofu destroy
```

## Labs

- `aks-cluster/` — AKS Free tier with node auto-provisioning (AKS-managed Karpenter, `node_provisioning_profile { mode = "Auto" }`). NAP constraints that shape the config: Azure CNI overlay + Cilium dataplane (kubenet/Calico unsupported), managed identity only, and the cluster **cannot be stopped** — destroy it to stop costs. The single `system` pool is critical-addons-only; workload nodes come from Karpenter. AKS default NodePools are disabled (`default_node_pools = "None"`); `karpenter.tf` owns the `general` and `system-burst` NodePools/AKSNodeClasses (via `alekc/kubectl`, configured from the cluster's `kube_config`) with `spec.limits` from `var.nap_limits` to cap over-provisioning — change caps there, not with `kubectl patch`. `manifests/inflate.yaml` is a scale test (`kubectl get nodeclaims -w`).

## Working in this repo

- Azure resources cost money. When creating a lab, include a clear teardown path (e.g. a single resource group per lab that can be deleted).
- Use the Microsoft Learn MCP tools to look up current Azure documentation and samples instead of relying on memory.
