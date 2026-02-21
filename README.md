# Phoenix Tunnel Automation

This repository contains `phoenix_setup.sh`, a fully automated bash script designed to deploy multi-node tunnels between a client node and one or more foreign servers using the [Phoenix Tunnel](https://github.com/Fox-Fig/phoenix) project and [Xray-core](https://github.com/XTLS/Xray-core).

## Features
- **Multi-Node Support**: Easily tunnel your Iran server to multiple different foreign servers (e.g., Sweden, England) simultaneously.
- **Full-Auto Mode**: Run the script *once* on your Iran server, give it SSH access to your foreign server, and it will automatically set up both ends of the tunnel perfectly.
- **Xray Integration**: The script automatically downloads and configures Xray-core as a local router on the Iran server. It accepts multiple ports (like `2096, 2097`) and safely updates your local configuration to route specific user traffic straight into the tunnel.
- **Tunnel Management**: A built-in management menu allows you to view active tunnels, restart them, stop them, edit Xray routing ports on the fly, or delete specific connection configurations without breaking others.
- **Atomic Uninstallation**: A single `Full Uninstall` option stops all related services, deletes all keys, removes all binaries (`/opt/phoenix`, `/usr/local/bin/xray`), and leaves the server 100% clean.
- **Safer Key Handling**: Public key parsing now handles Phoenix output format variations and fails fast with explicit error messages when parsing fails.

## Usage

### 1. Download the script (Iran Server)
```bash
wget -O phoenix_setup.sh https://raw.githubusercontent.com/Recoba86/Phoenix-Tunnel/main/phoenix_setup.sh
chmod +x phoenix_setup.sh
```

### 2. Run the script
```bash
bash phoenix_setup.sh
```

### 3. Select an Option
From the main menu, select the option that fits your needs:
- **Option 1**: Manual setup of the Server node (run directly on Foreign Server).
- **Option 2**: Manual setup of the Client node + Xray router (run directly on Iran Server).
- **Option 3**: **Full-Auto** setup. Run this on your Iran Server, provide the Foreign Server's SSH credentials, and the script handles the entire deployment.
- **Option 4**: Manage Active Tunnels (Restart, Edit Ports, Delete).
- **Option 5**: Full Clean Uninstall.

## Architecture
By default, this script uses **Phoenix mTLS** to securely tunnel traffic. When the Xray router is enabled on the Iran server, it uses `dokodemo-door` inbounds on your specified ports, and passes that traffic directly into the local Phoenix `SOCKS5` outbound.

`Traffic Flow`: User -> Iran Server (Port X) -> Xray dokodemo-door -> Phoenix Client proxy (SOCKS5) -> Phoenix Server (mTLS) -> Foreign Server -> Internet

## DPI Diagnostic Workflow (Recommended)
When testing a new path/provider, validate in two phases:

1. **Phase 1: Plain transport (`h2c`) smoke test**
- Bring up a temporary Phoenix server config without `private_key` on a dedicated test port.
- Bring up a temporary Phoenix client config with no key fields to that test port.
- Run `curl --socks5-hostname ...` through the local SOCKS listener.
- If this fails consistently, the route/path is blocked at a lower level than mTLS.

2. **Phase 2: mTLS test**
- Generate dedicated test keys.
- Configure server `private_key + authorized_clients`.
- Configure client `private_key + server_public_key`.
- Re-run the same SOCKS curl probes.

3. **Interpretation**
- If plain works but mTLS fails/timeouts, DPI/TLS fingerprint filtering is likely on-path.
- If both fail similarly, basic route quality/filtering is likely the issue.
- If both pass, proceed with production mTLS deployment via `phoenix_setup.sh`.

> Note: Plain mode is for diagnostics only. Use mTLS for real deployment.

## Credits
This automation script uses the incredible [Phoenix Tunnel](https://github.com/Fox-Fig/phoenix) project by Fox-Fig and [Xray-core](https://github.com/XTLS/Xray-core).
