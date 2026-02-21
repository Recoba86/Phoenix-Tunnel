# Phoenix Tunnel Automation

This repository contains `phoenix_setup.sh`, a fully automated bash script designed to deploy secure, multi-node tunnels between an Iran server and one or more Foreign servers using the [Phoenix Tunnel](https://github.com/Fox-Fig/phoenix) project and [Xray-core](https://github.com/XTLS/Xray-core).

## Features
- **Multi-Node Support**: Easily tunnel your Iran server to multiple different foreign servers (e.g., Sweden, England) simultaneously.
- **Full-Auto Mode**: Run the script *once* on your Iran server, give it SSH access to your foreign server, and it will automatically set up both ends of the tunnel perfectly.
- **Xray Integration**: The script automatically downloads and configures Xray-core as a local router on the Iran server. It accepts multiple ports (like `2096, 2097`) and safely updates your local configuration to route specific user traffic straight into the tunnel.
- **Tunnel Management**: A built-in management menu allows you to view active tunnels, restart them, stop them, edit Xray routing ports on the fly, or delete specific connection configurations without breaking others.
- **Atomic Uninstallation**: A single `Full Uninstall` option stops all related services, deletes all keys, removes all binaries (`/opt/phoenix`, `/usr/local/bin/xray`), and leaves the server 100% clean.

## Usage

### 1. Download the script (Iran Server)
```bash
wget -O phoenix_setup.sh https://raw.githubusercontent.com/Amin/Phoenix-Tunnel/main/phoenix_setup.sh
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
This script uses **Phoenix mTLS** to securely tunnel traffic. When the Xray router is enabled on the Iran server, it uses `dokodemo-door` inbounds on your specified ports, and passes that traffic directly into the local Phoenix `SOCKS5` outbound. 

`Traffic Flow`: User -> Iran Server (Port X) -> Xray dokodemo-door -> Phoenix Client proxy (SOCKS5) -> Phoenix Server (mTLS) -> Foreign Server -> Internet

## Credits
This automation script uses the incredible [Phoenix Tunnel](https://github.com/Fox-Fig/phoenix) project by Fox-Fig and [Xray-core](https://github.com/XTLS/Xray-core).
