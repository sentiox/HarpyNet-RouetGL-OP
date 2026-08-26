# HarpyNet Router

Public installer and release packages for HarpyNet on GL.iNet and OpenWrt.

This repository intentionally contains only `install.sh`, `uninstall.sh`, and
compiled IPK/APK packages in Releases. HarpyNet source code is developed in a
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
