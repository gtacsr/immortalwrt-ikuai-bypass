#!/bin/sh
# 记录执行日志：写到 /root/setup.log（ext4 持久化，重启后仍在）
# 说明：25.12 的首次开机脚本执行时机早于真正的 /tmp 挂载，写 /tmp 会丢，所以改 /root。
mkdir -p /root
exec >>/root/setup.log 2>&1
echo "===== $(date '+%F %T') 首次开机初始化开始 ====="

# ========================================================
# 1. 旁路由参数设置（严格遵循 25.12 的 CIDR 规范）
# ========================================================
lan_ip="192.168.123.2/24"    # 重点：带上 /24，杜绝 /32 单机掩码
gateway_ip="192.168.123.1"   # 主路由 iKuai 的 IP
dns_ip="192.168.123.1"       # DNS 指向 iKuai

# 同网段自检：LAN 与网关不在同一个 /24 时旁路由没有默认路由（只记录告警，不阻断开机）
lan_net="${lan_ip%%/*}"; lan_net="${lan_net%.*}"
gw_net="${gateway_ip%.*}"
[ "$lan_net" = "$gw_net" ] || echo "警告: LAN $lan_ip 与网关 $gateway_ip 不在同一 /24 网段，旁路由将无默认路由"

# 密码为空，登录后提示用户设置密码
passwd -d root >/dev/null 2>&1

# ========================================================
# 2. 清理无用的 WAN/WAN6 拨号口
# ========================================================
uci -q delete network.wan
uci -q delete network.wan6

# ========================================================
# 3. 设置静态网络与主路由网关/DNS
# ========================================================
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$lan_ip"
uci set network.lan.gateway="$gateway_ip"
uci set network.lan.dns="$dns_ip"
uci commit network

# ========================================================
# 4. 彻底关闭旁路由 DHCP 与 IPv6 广播（完全交给 iKuai）
# ========================================================
uci set dhcp.lan.ignore='1'
uci -q delete dhcp.lan.ra
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ndp
uci commit dhcp

# ========================================================
# 5. 强制界面语言为简体中文并设置 Argon 为默认主题
# ========================================================
uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# ========================================================
# 6. 预热 iKuai Bypass 本地离线检测缓存（免联网）
# ========================================================
if [ -d /opt/ikuai-bypass/install-cache ]; then
  mkdir -p /tmp/ikuai-bypass-install-cache/install-file
  cp -rf /opt/ikuai-bypass/install-cache/install.sh /tmp/ikuai-bypass-install-cache/install.sh 2>/dev/null || true
  cp -rf /opt/ikuai-bypass/install-cache/install-file/common.sh /tmp/ikuai-bypass-install-cache/install-file/common.sh 2>/dev/null || true
  chmod +x /tmp/ikuai-bypass-install-cache/install.sh /tmp/ikuai-bypass-install-cache/install-file/common.sh 2>/dev/null || true
  date +%s > /tmp/ikuai-bypass-install-cache/.stamp 2>/dev/null || true
fi

# ========================================================
# 7. 激活并开启 iKuai Bypass 服务开机自启
# ========================================================
if [ -f /etc/init.d/ikuai-bypass ]; then
  chmod +x /etc/init.d/ikuai-bypass
  /etc/init.d/ikuai-bypass enable
  /etc/init.d/ikuai-bypass start
fi

# ========================================================
# 8. 预置 OpenClash 黄金运行参数 (Meta 内核 + linux-amd64-v3 + 禁用开机自动联网更新)
# ========================================================
touch /etc/config/openclash 2>/dev/null || true
uci -q set openclash.config.core_type='Meta'
uci -q set openclash.config.core_version='linux-amd64-v3'
uci -q set openclash.config.auto_update_core='0'
uci -q set openclash.config.auto_update='0'
uci -q commit openclash

if [ -f /etc/openclash/core/clash_meta ]; then
  chmod +x /etc/openclash/core/clash_meta
  ln -sf /etc/openclash/core/clash_meta /etc/openclash/core/clash 2>/dev/null || true
fi

# ========================================================
# 9. 只跑一次：执行完自我删除，避免每次开机重跑覆盖手工配置
# ========================================================
echo "===== $(date '+%F %T') 初始化完成，删除首次开机脚本 ====="
sync
rm -f /etc/uci-defaults/99-custom-setup.sh
[ -f /etc/uci-defaults/99-custom-setup.sh ] && echo "警告: 自删除失败，脚本可能仍会重复执行"
echo "===== 完成 ====="

exit 0
