# aks-cluster

A Free-tier AKS cluster with **node auto-provisioning (NAP)**, Azure's built-in, Azure-managed Karpenter, deployed with OpenTofu.

## What gets created

| Resource | Details |
| --- | --- |
| Resource group | `rg-aks-lab` (`southeastasia`) |
| AKS cluster | `aks-lab`, Free control-plane tier, managed identity |
| System node pool | 1 × `Standard_D2s_v5`, runs only the cluster's own add-ons |
| Workload nodes | Provisioned on demand by Karpenter (NAP), capped by the NodePool limits in `karpenter.tf` |
| Networking | Azure CNI overlay + Cilium dataplane and network policy, Standard Load Balancer |
| Upgrades | `patch` auto-upgrade channel, `NodeImage` node OS upgrades |

## Prerequisites

- [OpenTofu](https://opentofu.org) >= 1.8
- Azure CLI, logged in (`az login`)
- `kubectl`

## Deploy

```sh
tofu init
tofu plan -out=tfplan
tofu apply tfplan
$(tofu output -raw get_credentials)
```

## Variables

| Name | Default | Description |
| --- | --- | --- |
| `subscription_id` | `null` | Defaults to the Azure CLI's current subscription |
| `name` | `aks-lab` | Cluster name; the resource group is `rg-<name>` |
| `location` | `southeastasia` | Azure region |
| `kubernetes_version` | `null` | Defaults to the AKS default version |
| `system_node_vm_size` | `Standard_D2s_v5` | System pool VM size |
| `system_node_count` | `1` | System pool node count |
| `tags` | `{ purpose = "az-lab" }` | Tags on all resources |
| `nap_limits` | general: 8 CPU / 16Gi, system_burst: 4 CPU / 16Gi | Total CPU and memory each Karpenter NodePool may provision |
| `nap_max_node_cpu` | `4` | Largest VM size, in vCPUs, Karpenter may pick for one node |

Override them in a `terraform.tfvars` file (gitignored) or with `-var name=value`.

## Try Karpenter

`manifests/inflate.yaml` deploys pause pods. Each one requests 1 CPU and 1.5Gi of memory, so scaling it up forces Karpenter to add nodes:

```sh
kubectl apply -f manifests/inflate.yaml
kubectl scale deploy/inflate --replicas=2
kubectl get nodeclaims -w        # watch Karpenter provision nodes
kubectl get nodes -L karpenter.sh/nodepool,node.kubernetes.io/instance-type

kubectl scale deploy/inflate --replicas=0   # Karpenter removes the extra nodes
```

## Karpenter NodePools and limits

The AKS default NodePools are turned off (`default_node_pools = "None"`) because they have no limits and AKS manages them. `karpenter.tf` defines two NodePools instead, each with an AKSNodeClass, applied with the `alekc/kubectl` provider:

| NodePool | Purpose | Default cap |
| --- | --- | --- |
| `general` | Ordinary workloads (`mode: user`) | 8 vCPU / 16Gi total |
| `system-burst` | Extra room for system pods when the system node is full (`CriticalAddonsOnly` taint) | 4 vCPU / 16Gi total |

Both use on-demand D-series VMs with at most `nap_max_node_cpu` vCPUs each. When a pool reaches its limit, Karpenter stops adding nodes and new pods stay `Pending`. That's intended: it stops a runaway scale-up from running up a bill.

```sh
kubectl get nodepools -o custom-columns=NAME:.metadata.name,CPU:.spec.limits.cpu,MEM:.spec.limits.memory,NODES:.status.resources.nodes
```

## NAP constraints

- Requires Azure CNI with the Cilium dataplane (overlay is recommended). Kubenet and Calico aren't supported.
- Supports managed identity only, not service principals.
- No Windows node pools and no IPv6.
- You can't change the outbound type after the cluster is created.
- **You can't stop the cluster** with `az aks stop`.

## Cost and teardown

The control plane is free, but the system node, its disk, the load balancer, the public IP, and any nodes Karpenter adds are billed. You can't stop a NAP cluster, so destroy it when you're done:

```sh
tofu destroy
```

## References

- [Node auto-provisioning overview](https://learn.microsoft.com/azure/aks/node-auto-provisioning)
- [NAP networking](https://learn.microsoft.com/azure/aks/node-auto-provisioning-networking)
- [AKSNodeClass configuration](https://learn.microsoft.com/azure/aks/node-auto-provisioning-aksnodeclass)
- [Karpenter provider for Azure](https://github.com/Azure/karpenter-provider-azure)
