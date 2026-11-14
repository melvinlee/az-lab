# az-lab

My Azure labs, aka playground: experiments, prototypes and learning exercises on Azure, built with [OpenTofu](https://opentofu.org).

## Labs

| Lab | What it builds |
| --- | --- |
| [`aks-cluster/`](aks-cluster/) | Free-tier AKS cluster with node auto-provisioning (Azure-managed Karpenter): arm64 system node, spot-first Karpenter NodePools with CPU and memory caps, latest GA Kubernetes |

## How labs are organized

- Each lab is a self-contained folder with its own OpenTofu config and local state.
- Each lab deploys into its own resource group (`rg-<name>`), so one `tofu destroy` removes everything.
- Each lab has its own README with details, variables and costs.

## Prerequisites

- [OpenTofu](https://opentofu.org) >= 1.8
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged in with `az login`
- `kubectl` for the Kubernetes labs

The labs deploy into the Azure CLI's current subscription (`az account show`) unless `subscription_id` is set.

## Usage

```sh
cd <lab>
tofu init
tofu plan -out=tfplan
tofu apply tfplan

# when finished
tofu destroy
```

## Cost

These labs create real, billable Azure resources. Check each lab's README for what it costs, and destroy labs you aren't using. Some resources can't be stopped: for example, an AKS cluster with node auto-provisioning has to be destroyed to stop billing.
