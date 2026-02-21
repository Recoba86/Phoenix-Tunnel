# Changelog

All notable changes to the `Phoenix Tunnel Automation` project will be documented in this file.

## [1.0.0] - 2026-02-22

### Added
- **Initial Release:** Comprehensive `phoenix_setup.sh` automation script.
- **Installation Modes:** Support for Manual Installation and Full-Auto SSH cross-server installation.
- **Multi-Node Support:** Ability to seamlessly add unlimited secondary foreign servers (e.g., run the script again to add England after setting up Sweden).
- **Xray Auto-Routing:** Native Xray-core download and service creation. Dynamically injects and manages JSON rules (`dokodemo-door` to `socks5` outbound) via `jq` to ensure safe, multi-country routing.
- **Tunnel Management Menu:** Added Option 4 to view, restart, stop, safely delete individual tunnels, or edit Xray routing ports specifically for that tunnel.
- **Clean Uninstall:** Added Option 5 to execute a total system scrub, removing all binaries, TOML configs, JSON configs, systemd services, and keys.

### Fixed
- Fixed bug where `enable_udp = false` was used in the Phoenix config; updated to `true` globally to correctly support Xray UDP encapsulation over Dokodemo-door.
