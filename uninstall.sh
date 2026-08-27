#!/bin/sh
set -eu

PURGE="${HARPYNET_PURGE:-0}"
REMOVE_MIHOMO="${HARPYNET_REMOVE_MIHOMO:-0}"

info() {
	printf '\033[32;1m%s\033[0m\n' "$*" >&2
}

warn() {
	printf '\033[33;1m%s\033[0m\n' "$*" >&2
}

restore_dns() {
	local previous=""
	local noresolv=""
	local item=""

	[ "$(uci -q get harpynet.settings.dnsmasq_backup_done 2>/dev/null || true)" = "1" ] || return 0
	previous="$(uci -q get harpynet.settings.dnsmasq_server_before 2>/dev/null || true)"
	noresolv="$(uci -q get harpynet.settings.dnsmasq_noresolv_before 2>/dev/null || true)"
	uci -q delete dhcp.@dnsmasq[0].server || true
	for item in $previous; do
		uci -q add_list "dhcp.@dnsmasq[0].server=$item"
	done
	uci -q delete dhcp.@dnsmasq[0].strictorder || true
	if [ -n "$noresolv" ]; then
		uci -q set "dhcp.@dnsmasq[0].noresolv=$noresolv"
	else
		uci -q delete dhcp.@dnsmasq[0].noresolv || true
	fi
	uci -q commit dhcp || true
	uci -q delete harpynet.settings.dnsmasq_backup_done || true
	uci -q commit harpynet || true
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || warn "dnsmasq restart failed"
}

[ "$(id -u)" = "0" ] || {
	printf '\033[31;1mRun as root on the router\033[0m\n' >&2
	exit 1
}

case "$PURGE" in 0|1) ;; *) warn "HARPYNET_PURGE must be 0 or 1"; exit 1 ;; esac
case "$REMOVE_MIHOMO" in 0|1) ;; *) warn "HARPYNET_REMOVE_MIHOMO must be 0 or 1"; exit 1 ;; esac

info "Stopping HarpyNet and restoring network routing..."
if [ -x /etc/init.d/harpynet ]; then
	/etc/init.d/harpynet disable >/dev/null 2>&1 || true
	/etc/init.d/harpynet stop >/dev/null 2>&1 || warn "HarpyNet stop returned an error; continuing cleanup"
fi
restore_dns

# These are safe fallbacks when a previous installation is incomplete and the
# backend cleanup command is no longer available.
nft delete table inet HarpyNetTable >/dev/null 2>&1 || true
ip -4 rule del fwmark 0x100000/0x100000 table 105 priority 105 >/dev/null 2>&1 || true
ip -4 route flush table 105 >/dev/null 2>&1 || true
if [ -f /etc/iproute2/rt_tables ]; then
	sed -i '/^[[:space:]]*105[[:space:]]\+harpynet[[:space:]]*$/d' /etc/iproute2/rt_tables
fi

info "Removing GL.iNet and LuCI interfaces..."
rm -f \
	/usr/share/oui/menu.d/harpynet.json \
	/www/views/gl-sdk4-ui-harpynet.common.js \
	/usr/lib/oui-httpd/rpc/harpynet_gl \
	/usr/share/gl-validator.d/harpynet_gl.lua \
	/usr/libexec/rpcd/harpynet_gl \
	/usr/lib/harpynet_direct_monitor.sh \
	/usr/share/rpcd/acl.d/harpynet-gl.json \
	/usr/share/rpcd/acl.d/luci-app-harpynet.json \
	/usr/share/luci/menu.d/luci-app-harpynet.json \
	/www/luci-static/resources/view/harpynet/overview.js
rm -rf /www/harpynet

info "Removing HarpyNet backend..."
rm -f /etc/init.d/harpynet /usr/bin/harpynet
rm -rf /usr/lib/harpynet
rm -f /var/run/harpynet-activate.pid /tmp/harpynet-activate.log /tmp/harpynet.nft
rm -rf /tmp/mihomo /tmp/harpynet-subscription-update.lock

if [ "$PURGE" = "1" ]; then
	info "Purging HarpyNet configuration and cache..."
	rm -f /etc/config/harpynet
	rm -rf /etc/harpynet
else
	info "Keeping /etc/config/harpynet and /etc/harpynet for a future reinstall"
fi

if [ "$REMOVE_MIHOMO" = "1" ]; then
	info "Removing /usr/bin/mihomo as explicitly requested..."
	rm -f /usr/bin/mihomo
else
	info "Keeping /usr/bin/mihomo because another application may use it"
fi

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd restart failed"
if [ -x /etc/init.d/oui-httpd ]; then
	/etc/init.d/oui-httpd restart >/dev/null 2>&1 || warn "OUI reload failed"
elif [ -x /etc/init.d/nginx ]; then
	/etc/init.d/nginx reload >/dev/null 2>&1 || warn "nginx reload failed"
fi
if [ -x /etc/init.d/uhttpd ]; then
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || warn "uHTTPd restart failed"
fi

info "HarpyNet removal completed successfully"
