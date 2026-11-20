# az-lab

My Azure labs, aka playground: experiments, prototypes and learning exercises on Azure, built with [OpenTofu](https://opentofu.org).

## Labs

| Lab | What it builds |
| --- | --- |
| [`aks-cluster/`](aks-cluster/) | Free-tier AKS cluster with node auto-provisioning (Azure-managed Karpenter): arm64 system node, spot-first Karpenter NodePools with CPU and memory caps, latest GA Kubernetes |
| [`ai-agent/`](ai-agent/) | arm64 VM (`Standard_D2ps_v5`) on Azure Linux 3 with Hermes Agent installed by cloud-init at first boot |

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

## Secret scanning

A [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook (`.githooks/pre-commit`, rules in `.gitleaks.toml`) blocks commits whose staged changes contain secrets. Set it up once per clone:

```sh
brew install gitleaks
git config core.hooksPath .githooks
```

For a false positive, add a `gitleaks:allow` comment on the line, or bypass the hook once with `SKIP=gitleaks git commit ...` or `git commit --no-verify`.

A [TruffleHog](https://github.com/trufflesecurity/trufflehog) pre-push hook (`.githooks/pre-push`) scans the commits being pushed and blocks the push if a secret is **verified** live against its provider (or can't be verified). It's the second line of defence: it catches real credentials that got past gitleaks, e.g. in a `--no-verify` commit. Unverified pattern matches don't block, since gitleaks already covers those. Verification sends candidate secrets to their provider's API (e.g. AWS STS).

```sh
brew install trufflehog
```

Same `core.hooksPath` setup. If a push is blocked, rotate the credential first, then rewrite the commit. Bypass a false positive with `SKIP=trufflehog git push ...` or `git push --no-verify`.

## Cost

These labs create real, billable Azure resources. Check each lab's README for what it costs, and destroy labs you aren't using. Some resources can't be stopped: for example, an AKS cluster with node auto-provisioning has to be destroyed to stop billing.
