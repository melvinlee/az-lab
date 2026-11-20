# ai-agent

A single arm64 VM running **Azure Linux 3**, running [Hermes Agent](https://github.com/NousResearch/hermes-agent) as a **container** (the official multi-arch image), set up by cloud-init on first boot and deployed with OpenTofu.

## What gets created

| Resource | Details |
| --- | --- |
| Resource group | `rg-ai-agent` (`southeastasia`) |
| VM | `vm-ai-agent`, `Standard_D2ps_v5` (2 vCPU / 8 GiB, arm64 Ampere Altra), 64 GiB Standard SSD |
| Image | `MicrosoftCBLMariner:azure-linux-3:azure-linux-3-arm64:latest` (Gen2) |
| Networking | VNet `10.20.0.0/16`, Standard static public IP, NSG allowing SSH **only from your current IP** |
| Access | SSH key only (`~/.ssh/id_ed25519.pub` by default), password auth disabled |
| Boot | cloud-init installs Docker (`moby-engine`), pulls the Hermes image and registers `hermes-gateway.service` |

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

1. `tdnf` installs `moby-engine` and `docker-cli` from Azure Linux's default `base` repo. Nothing else Hermes needs (Python, Node, uv, git) is installed on the host: it's all in the image.
2. `/etc/hermes/hermes.env` gets `HERMES_IMAGE` (from `var.hermes_image`, pinned by digest) and `HERMES_UID`/`HERMES_GID` (`azureuser`'s IDs). `~/.hermes` is created as the container's data volume (`/opt/data`, its `HERMES_HOME`).
3. The image is pre-pulled (log: `/var/log/hermes-pull.log`).
4. `hermes-gateway.service` is enabled. It runs `docker run --rm --name hermes ... gateway run` in the foreground with `Restart=on-failure`, and has `ConditionPathExists=~/.hermes/.env`, so it stays inactive instead of crash-looping until you configure a provider.

API keys are deliberately **not** passed through OpenTofu: `custom_data` is stored in state and on the VM.

### Why Docker and this image

- **Image:** NousResearch publishes `nousresearch/hermes-agent` on Docker Hub as a multi-arch index (`linux/amd64`, `linux/arm64`), with versioned tags (`v0.23.3`) and `stable`/`latest`. We pin a version tag plus its index digest.
- **Runtime:** on Azure Linux 3, `moby-engine` (25.0) and `docker-cli` are in the default `base` repo. `podman` (5.6) exists only in the `extended` repo, which isn't enabled by default. Hermes's own docs and compose file target Docker.

### Container security

- The image's s6-overlay `/init` runs as PID 1 and as root only to remap its `hermes` user to `HERMES_UID` and fix volume ownership. It then runs the gateway (and anything `docker exec ... hermes` starts) as that non-root user. Don't override the entrypoint or add `--init`: that drops s6 supervision and zombie reaping.
- No `--privileged`, no Docker socket mount, no published ports, default bridge network. The gateway only makes outbound connections; its API server stays off.
- The agent's terminal tool runs commands **inside the container** as the `hermes` user, so it sees the image and `/opt/data`, not the host. The Docker terminal backend isn't available (no socket). Browser tools would need `--shm-size=1g`; this lab doesn't use them.

## Configure Hermes (after first boot)

`/usr/local/bin/hermes` is a small wrapper: it runs the CLI inside the running `hermes` container (`docker exec`), or in a throwaway container on the same volume when the gateway isn't running. Either way it acts on `~/.hermes`.

```sh
ssh azureuser@<public_ip>
cloud-init status --wait            # wait for "status: done"
hermes setup                        # pick a model provider, writes ~/.hermes/.env
#   or: echo 'OPENROUTER_API_KEY=...' >> ~/.hermes/.env   (also ANTHROPIC_API_KEY, OPENAI_API_KEY)
hermes gateway setup                # optional: Telegram/Discord/etc.
sudo systemctl start hermes-gateway
```

Without the wrapper, the same thing is:

```sh
. /etc/hermes/hermes.env
sudo docker run --rm -it --env-file /etc/hermes/hermes.env -v ~/.hermes:/opt/data "$HERMES_IMAGE" setup
```

## Logs

```sh
journalctl -u hermes-gateway -f          # unit + container output
sudo docker logs -f hermes               # container output (rotated, 3 x 10 MB)
tail -F ~/.hermes/logs/gateways/default/current   # Hermes's own gateway log
```

## Upgrade and roll back

Edit the image on the VM and restart. Config, `.env`, memory and sessions in `~/.hermes` are kept, and the container runs Hermes's config migrations on start (with backups next to `config.yaml` and `.env`).

```sh
sudo sed -i 's|^HERMES_IMAGE=.*|HERMES_IMAGE=docker.io/nousresearch/hermes-agent:<new-version>|' /etc/hermes/hermes.env
sudo systemctl restart hermes-gateway    # ExecStartPre pulls the new image
# roll back: put the previous value back and restart again
sudo docker image prune                  # later, to drop unused old images
```

Also update `hermes_image` in OpenTofu so a rebuilt VM starts on the same version. Changing that variable on its own **replaces the VM** (it's in `custom_data`) and discards `~/.hermes` with the old OS disk, so copy `~/.hermes` off first if you go that way.

## Verify

```sh
uname -m                                 # aarch64
cat /etc/os-release | head -2            # Azure Linux 3.0
cloud-init status --long                 # status: done, no errors
sudo docker image inspect -f '{{.Architecture}}' "$(. /etc/hermes/hermes.env; echo $HERMES_IMAGE)"   # arm64
systemctl status hermes-gateway          # active (running) once .env exists
sudo docker ps                           # hermes container Up
hermes doctor
sudo reboot                              # then check the service, container and ~/.hermes again
```

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `name` | `ai-agent` | Resource group is `rg-<name>` |
| `location` | `southeastasia` | |
| `vm_size` | `Standard_D2ps_v5` | Must be an Arm64 size |
| `admin_username` | `azureuser` | Owns `~/.hermes`; the container's `hermes` user is remapped to its UID/GID |
| `hermes_image` | `docker.io/nousresearch/hermes-agent:v0.23.3@sha256:3e9f…` | Initial `HERMES_IMAGE`; changing it replaces the VM |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | |
| `ssh_allowed_cidr` | `null` (your IP /32) | |
| `os_disk_size_gb` | `64` | Room for the image, a rollback image and `~/.hermes` |

## Cost

`Standard_D2ps_v5` in `southeastasia`: about **$0.096/h** on-demand (~$70/month), plus the public IP and disk. Spot is ~$0.018/h but not used here, since eviction would interrupt the agent. Stop billing for compute with `az vm deallocate -g rg-ai-agent -n vm-ai-agent`, or remove everything:

```sh
tofu destroy
```

## Notes

- `custom_data` changes force a VM replacement (cloud-init only runs on first boot).
- If the image pull at boot fails, check `/var/log/hermes-pull.log`; the unit pulls again on start anyway.
- Never run two gateway containers on the same `~/.hermes` (Hermes's session and memory stores aren't built for concurrent writers).
- The gateway denies all users until they are allowlisted or paired (Hermes default).
