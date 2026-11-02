# HarpyNet Router

Public installer and release packages for HarpyNet on GL.iNet and OpenWrt.

This repository intentionally contains only `install.sh`, `uninstall.sh`, and
compiled IPK/APK packages and compatible Mihomo cores in Releases. The exact
Mihomo core source archive is included with each release. HarpyNet source code is developed in a
private repository and is not published here.

## Install or update

Run as `root` on the router:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/install.sh)"
```

The installer detects GL.iNet OUI or OpenWrt LuCI, downloads the matching
backend and UI packages from the latest public Release, preserves existing
HarpyNet configuration, and restarts the appropriate services.

## Uninstall

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/uninstall.sh)"
```

Mihomo is updated to the tested Firefox 148 / X25519MLKEM768 build when needed.
The previous executable is kept as `/usr/bin/mihomo.harpynet-backup`.
