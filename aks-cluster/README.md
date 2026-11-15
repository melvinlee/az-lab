# aks-cluster

A Free-tier AKS cluster with **node auto-provisioning (NAP)**, Azure's built-in, Azure-managed Karpenter, deployed with OpenTofu.

## What gets created

| Resource | Details |
| --- | --- |
| Resource group | `rg-aks-lab` (`southeastasia`) |
| AKS cluster | `aks-lab`, Free control-plane tier, managed identity |
| System node pool | 1 × `Standard_D2ps_v6` (arm64, Azure Cobalt 100), runs only the cluster's own add-ons |
| Workload nodes | Provisioned on demand by Karpenter (NAP), capped by the NodePool limits in `karpenter.tf` |
| Networking | Azure CNI overlay + Cilium dataplane and network policy, Standard Load Balancer |
| Kubernetes version | Latest GA minor in the region, from the `azurerm_kubernetes_service_versions` data source |
| Event-driven autoscaling | AKS-managed KEDA add-on |
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

## Kubernetes version

By default the cluster uses the newest generally available (non-preview) Kubernetes minor version AKS offers in the region. It pins the minor version (for example `1.37`) rather than a patch, so:

- New clusters always start on the latest GA minor.
- AKS applies patches automatically through the `patch` auto-upgrade channel, without causing OpenTofu drift.
- When a newer minor becomes GA, the next `tofu plan` shows an in-place upgrade of the control plane and system pool. Karpenter nodes follow the control plane automatically.

To stay on a specific minor, set `kubernetes_version = "1.36"`.

## Variables

| Name | Default | Description |
| --- | --- | --- |
| `subscription_id` | `null` | Defaults to the Azure CLI's current subscription |
| `name` | `aks-lab` | Cluster name; the resource group is `rg-<name>` |
| `location` | `southeastasia` | Azure region |
| `kubernetes_version` | `null` | Minor version such as `"1.36"`. `null` means the latest GA version in the region, looked up at plan time |
| `system_node_vm_size` | `Standard_D2ps_v6` | System pool VM size (arm64). Changes rotate the pool in place through `temporary_name_for_rotation` |
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

Both use D-series VMs with at most `nap_max_node_cpu` vCPUs each. `general` allows both spot and on-demand, and NAP prefers spot, falling back to on-demand when spot capacity isn't available. `system-burst` stays on-demand only, so system pods aren't evicted when Azure reclaims spot capacity. `general` is amd64 only because the workloads aren't multi-arch; `system-burst` is arm64 to match the system pool. When a pool reaches its limit, Karpenter stops adding nodes and new pods stay `Pending`. That's intended: it stops a runaway scale-up from running up a bill.

```sh
kubectl get nodepools -o custom-columns=NAME:.metadata.name,CPU:.spec.limits.cpu,MEM:.spec.limits.memory,NODES:.status.resources.nodes
```

## KEDA

The AKS-managed KEDA add-on (`workload_autoscaler_profile { keda_enabled = true }`) runs the KEDA operator, metrics API server and admission webhook in `kube-system`. The tests only use cron triggers, which need no Azure resources, so there's nothing extra to create or pay for.

### Running the tests

```sh
kubectl apply -f manifests/inflate.yaml   # target for tests 1 and 2
```

| # | Test | Manifest | Expected |
| --- | --- | --- | --- |
| 0 | Smoke test | none | See below |
| 1 | Cron scaler | `keda-1-cron.yaml` | `inflate` 0 → 3 at :00/:10/:20…, back to 0 after the 5-minute window; `keda-hpa-inflate-cron` HPA exists |
| 2 | KEDA + Karpenter | `keda-2-cron-karpenter.yaml` | 10 replicas → 2 NodeClaims, ~6 Running and the rest Pending at the 16Gi cap; after the window, pods → 0 and Karpenter removes the nodes |

Each manifest's header has the exact commands. Tests 1 and 2 use the same ScaledObject name, so applying test 2 replaces test 1.

**Test 0, smoke test:**

```sh
az aks show -g rg-aks-lab -n aks-lab --query workloadAutoScalerProfile.keda.enabled   # true
kubectl get pods -n kube-system -o wide | grep keda       # operator, metrics API server, webhook: Running on the system node
kubectl get apiservice v1beta1.external.metrics.k8s.io    # AVAILABLE=True
```

### How the scale-down timing works

- `cooldownPeriod` only covers the last step, 1 → 0.
- Scaling N → 1 is done by the HPA that KEDA creates. Its default scale-down stabilization is 300s; the manifests shorten it to 60s under `spec.advanced.horizontalPodAutoscalerConfig.behavior`.
- Full scale-down is therefore: HPA stabilization → KEDA cooldown → Karpenter consolidation of the empty nodes.

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
- [KEDA add-on for AKS](https://learn.microsoft.com/azure/aks/keda-about)
- [KEDA cron scaler](https://keda.sh/docs/latest/scalers/cron/)
