# LaunchDarkly Apex Bridge — Azure Deployment Guide

This document covers running the [bridge daemon](bridge/) on Azure: deployment options, required environment variables, and whether a VNet + NAT Gateway is needed.

## What the bridge does on the network

The bridge is an **outbound-only** daemon. Looking at [bridge/main.go](bridge/main.go), all traffic flows out:

- → LaunchDarkly stream / events / SDK endpoints
- → Salesforce OAuth (`login.salesforce.com` or sandbox)
- → Salesforce Apex REST URL (your org)

There is no inbound listener.

## Required environment variables

The bridge reads configuration from environment variables (see [bridge/README.md](bridge/README.md)).

| Variable | Required | Notes |
|---|---|---|
| `LD_SDK_KEY` | Yes | LaunchDarkly server-side SDK key |
| `SALESFORCE_URL` | Yes | e.g. `https://na123.salesforce.com/services/apexrest/` |
| `OAUTH_ID` | Yes | Salesforce connected app consumer key |
| `OAUTH_USERNAME` | Yes | Salesforce username |
| `OAUTH_JWT_KEY` | One of | Base64-encoded PEM RSA private key (JWT auth — recommended) |
| `OAUTH_PASSWORD` + `OAUTH_SECRET` | One of | Password + connected app consumer secret (password auth) |
| `OAUTH_URI` | No | Defaults to `https://login.salesforce.com/services/oauth2/token` |
| `HTTP_TIMEOUT` | No | e.g. `1500ms` |
| `LD_EVENTS_URI` | No | Overrides the default LaunchDarkly events URI |

If neither `OAUTH_JWT_KEY` nor (`OAUTH_PASSWORD` + `OAUTH_SECRET`) is set, the bridge exits with `Error creating bridge: OAUTH_SECRET not set` (or the equivalent for whichever variable is missing) — see [bridge/main.go:93-102](bridge/main.go#L93-L102).

## Deployment options

### Option 1 — Azure App Service (no Docker)

Deploys the compiled Go binary; Azure manages the host.

```powershell
# Build a Linux binary
cd c:\amitabh\fork-ld\apex-server-sdk\bridge
$env:GOOS='linux'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
go build -o bridge .

# Create resources
az group create -n ld-bridge-rg -l eastus
az appservice plan create -n ld-bridge-plan -g ld-bridge-rg --is-linux --sku B1
az webapp create -n ld-bridge-app -g ld-bridge-rg -p ld-bridge-plan --runtime "GO:1.19"

# Set env vars
az webapp config appsettings set -g ld-bridge-rg -n ld-bridge-app --settings `
  LD_SDK_KEY=sdk-... `
  SALESFORCE_URL=https://yourorg.salesforce.com/services/apexrest/ `
  OAUTH_ID=... `
  OAUTH_USERNAME=you@example.com `
  OAUTH_PASSWORD='password+token' `
  OAUTH_SECRET=...

# Deploy
Compress-Archive -Path bridge -DestinationPath bridge.zip -Force
az webapp deploy -g ld-bridge-rg -n ld-bridge-app --src-path bridge.zip --type zip
```

### Option 2 — Azure Container Apps (Azure builds the container)

```powershell
az group create -n ld-bridge-rg -l eastus
az containerapp env create -n ld-bridge-env -g ld-bridge-rg -l eastus

az containerapp up `
  -n ld-bridge `
  -g ld-bridge-rg `
  --environment ld-bridge-env `
  --source c:\amitabh\fork-ld\apex-server-sdk `
  --env-vars LD_SDK_KEY=sdk-... SALESFORCE_URL=... OAUTH_ID=... `
             OAUTH_USERNAME=... OAUTH_PASSWORD=... OAUTH_SECRET=...
```

### Option 3 — Azure VM

Closest to "just run the binary" — you manage the OS, systemd, patching.

```powershell
az vm create -n ld-bridge-vm -g ld-bridge-rg --image Ubuntu2204 `
  --admin-username azureuser --generate-ssh-keys
# scp the binary, ssh in, export env vars, run as a systemd service
```

### Comparison

| Path | Docker needed | Effort | Approx. cost |
|---|---|---|---|
| App Service Go runtime | No | Low | ~$13/mo (B1) |
| Container Apps | Azure builds it | Lowest | Pay-per-use |
| VM | No | Highest | ~$8/mo (B1s) |

Store OAuth secrets in **Key Vault** and reference them from app settings rather than putting them in CLI history.

## Do we need a VNet with NAT Gateway?

**Short answer:** only if Salesforce-side controls require predictable egress IPs. The bridge will *function* without one.

### When VNet + NAT Gateway IS needed

| Driver | Why |
|---|---|
| Salesforce **Login IP Ranges** on the user profile, or **Trusted IPs** / Connected App set to "Enforce IP restrictions" | Egress must come from a known static IP. App Service / Container Apps use shared egress pools that can change. NAT Gateway provides a dedicated static public IP. |
| Corporate policy requires controlled egress | Forces traffic through NAT Gateway or Azure Firewall |
| Need **Private Endpoints** to Key Vault / Storage / etc. | Private Endpoints require a VNet |
| Bursty outbound, SNAT port exhaustion risk | NAT Gateway scales SNAT ports far better than the platform default |

### When you DON'T need it

- Salesforce connected app set to **"Relax IP restrictions"** (typical for server-to-server OAuth)
- No corporate egress policy
- Single low-volume daemon — SNAT exhaustion is unlikely with this traffic profile

### Reference architecture (if needed)

```
[App Service / Container App]
        │ (regional VNet integration)
        ▼
   [Subnet in VNet]
        │
        ▼
   [NAT Gateway] ── [Static Public IP] ──► Salesforce + LaunchDarkly
```

- **App Service**: enable regional VNet integration, route all outbound via the subnet's NAT Gateway.
- **Container Apps**: deploy the environment with a custom VNet in *workload profiles* mode, attach NAT Gateway to the subnet.
- Add the NAT Gateway's static IP to Salesforce **Trusted IP Ranges**.

### Cost impact

Approximately **~$32/mo** for the NAT Gateway plus **~$4/mo** for the static public IP, on top of compute.

### Recommendation

Start without a VNet. If Salesforce admins confirm the connected app or user profile enforces IP restrictions, add VNet integration + NAT Gateway later — it's an additive change, not a redesign.

The deciding question to ask the Salesforce admin: **is the connected app set to "Relax IP restrictions"?**
