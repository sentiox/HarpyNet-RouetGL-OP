# HarpyNet for GL.iNet and OpenWrt

HarpyNet is a selective-routing interface backed by Mihomo. One repository now
supports both the native GL.iNet web interface and standard OpenWrt LuCI.

## One-command install

Run as `root` on the router:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/install.sh)"
```

The installer detects the available router interface:

- GL.iNet OUI only: installs the native GL.iNet page automatically.
- LuCI only: installs the OpenWrt LuCI page automatically.
- both interfaces: asks whether to install `1) GL.iNet` or `2) LuCI`.
- neither interface: stops without installing an incompatible UI.

For unattended installation, choose explicitly:

```sh
HARPYNET_UI=gl sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/install.sh)"
HARPYNET_UI=luci sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/install.sh)"
```

The existing `/etc/config/harpynet` is preserved during reinstall and upgrade.
The installer checks required packages, downloads the current Mihomo build for
the router architecture, prepares GeoIP data, reloads the correct web service,
and reports the page URL when installation succeeds.

## Repository layout

- `harpynet/` — shared OpenWrt service and Mihomo backend.
- `harpynet-gl-ui/` — native GL.iNet OUI page and shared UI component.
- `luci-app-harpynet/` — LuCI integration for ordinary OpenWrt devices.
- `install.sh` — detecting router-side installer.
- `scripts/build-openwrt-packages.sh` — builds backend, GL.iNet UI, and LuCI
  packages in both IPK and APK formats.

## Interfaces

On GL.iNet firmware, HarpyNet appears under `VPN -> HarpyNet` in the stock UI:

```text
http://<router-ip>/#/harpynet
```

On OpenWrt, it appears under `Services -> HarpyNet` in LuCI:

```text
http://<router-ip>/cgi-bin/luci/admin/services/harpynet
```

Both interfaces use the same `harpynet_gl` rpcd bridge and the same backend;
only the web integration differs. HarpyNet does not use sing-box.

## Release packages

The release workflow produces three packages per format:

- `harpynet` — shared backend;
- `harpynet-gl-ui` — native GL.iNet UI;
- `luci-app-harpynet` — OpenWrt LuCI UI.

Install the backend plus exactly one UI package appropriate for the router.

## Private development and public updates

Development can remain in the private `sentiox/harpynet.gl` repository while
routers install and update from the public `sentiox/HarpyNet-RouetGL-OP`
repository. Create a fine-grained GitHub token with `Contents: Read and write`
access to the public repository, then save it in the private repository as the
Actions secret `PUBLIC_REPO_TOKEN`.

When a release tag is published from the private repository, the release
workflow mirrors the deployable source tree and tag to the public repository.
The public repository keeps its own `.github` configuration and commit history.
If the secret is absent, the private build and release still complete, but the
public mirror step is skipped.

The router updater uses only the public installer channel. For local testing
against the private development repository, override it explicitly:

```sh
HARPYNET_REPO=sentiox/harpynet.gl sh ./install.sh
```

## Uninstall

Run as `root` to remove the service and both possible web interfaces:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/uninstall.sh)"
```

The default removal keeps `/etc/config/harpynet`, `/etc/harpynet`, and the
Mihomo binary so a reinstall does not lose the subscription or affect another
application. To delete all HarpyNet settings and Mihomo explicitly:

```sh
HARPYNET_PURGE=1 HARPYNET_REMOVE_MIHOMO=1 sh -c "$(wget -O - https://raw.githubusercontent.com/sentiox/HarpyNet-RouetGL-OP/main/uninstall.sh)"
```
