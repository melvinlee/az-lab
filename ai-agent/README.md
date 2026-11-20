# ai-agent

A single arm64 VM running **Azure Linux 3**, with [Hermes Agent](https://github.com/NousResearch/hermes-agent) installed by cloud-init on first boot, deployed with OpenTofu.

## What gets created

| Resource | Details |
| --- | --- |
| Resource group | `rg-ai-agent` (`southeastasia`) |
| VM | `vm-ai-agent`, `Standard_D2ps_v5` (2 vCPU / 8 GiB, arm64 Ampere Altra), 64 GiB Standard SSD |
| Image | `MicrosoftCBLMariner:azure-linux-3:azure-linux-3-arm64:latest` (Gen2) |
| Networking | VNet `10.20.0.0/16`, Standard static public IP, NSG allowing SSH **only from your current IP** |
| Access | SSH key only (`~/.ssh/id_ed25519.pub` by default), password auth disabled |
| Boot | cloud-init installs Hermes as `azureuser` and registers `hermes-gateway.service` |

## Deploy

```sh
cd ai-agent
tofu init
tofu plan -out=tfplan
tofu apply tfplan
tofu output ssh_command
```

The SSH source IP is looked up from `api.ipify.org` at plan time. If your IP changes, re-run plan/apply, or set `ssh_allowed_cidr`.

## What happens at boot

1. `tdnf` installs `git`, `curl`, `tar`, `ca-certificates`, `libatomic` (the Hermes installer doesn't use a distro package manager, so these must exist first).
2. The Hermes installer runs as `azureuser` from the stable channel with `--non-interactive --skip-browser --skip-computer-use` (headless VM, no Chromium). Output: `/var/log/hermes-install.log`; Hermes lives in `~/.hermes`.
3. `hermes-gateway.service` (a system unit, so it starts at boot without user lingering) is enabled. It has `ConditionPathExists=~/.hermes/.env`, so it stays inactive instead of crash-looping until you configure a provider.

API keys are deliberately **not** passed through OpenTofu: `custom_data` is stored in state and on the VM.

## Configure Hermes (after first boot)

```sh
ssh azureuser@<public_ip>
cloud-init status --wait            # wait for "status: done"
hermes setup                        # pick a model provider, writes ~/.hermes/.env
#   or: echo 'OPENROUTER_API_KEY=...' >> ~/.hermes/.env   (also ANTHROPIC_API_KEY, OPENAI_API_KEY)
hermes gateway setup                # optional: Telegram/Discord/etc.
sudo systemctl start hermes-gateway
```

## Verify

```sh
uname -m                                 # aarch64
cat /etc/os-release | head -2            # Azure Linux 3.0
cloud-init status --long                 # status: done, no errors
hermes doctor
systemctl status hermes-gateway          # active (running) once .env exists
sudo reboot                              # then check the service again
```

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `name` | `ai-agent` | Resource group is `rg-<name>` |
| `location` | `southeastasia` | |
| `vm_size` | `Standard_D2ps_v5` | Must be an Arm64 size |
| `admin_username` | `azureuser` | Hermes runs as this user |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | |
| `ssh_allowed_cidr` | `null` (your IP /32) | |
| `os_disk_size_gb` | `64` | |

## Cost

`Standard_D2ps_v5` in `southeastasia`: about **$0.096/h** on-demand (~$70/month), plus the public IP and disk. Spot is ~$0.018/h but not used here, since eviction would interrupt the agent. Stop billing for compute with `az vm deallocate -g rg-ai-agent -n vm-ai-agent`, or remove everything:

```sh
tofu destroy
```

## Notes

- `custom_data` changes force a VM replacement (cloud-init only runs on first boot).
- The Hermes installer doesn't list Azure Linux explicitly; it supports linux-arm64 (glibc) and needs only git and curl. If boot install fails, check `/var/log/hermes-install.log` and `~/.hermes/logs/install.log`.
- The gateway denies all users until they are allowlisted or paired (Hermes default).
