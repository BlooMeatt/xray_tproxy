:local containerName "xray"
:local ramSlot "ramdisk1"

:local bridgeName "containers-bridge"
:local bridgeAddress "192.168.150.1/24"
:local vethName "veth-xray"
:local wgName "wg-xray"

:local mountList "xray-config"
:local natComment "xray-container-nat"

# Stop and remove the container.
:foreach c in=[/container/find where name=$containerName] do={
    :do {/container/stop $c} on-error={}
    :delay 2s
    :do {/container/remove $c} on-error={}
}

# Remove mounts created for Xray config.
:foreach m in=[/container/mounts/find where list=$mountList] do={
    :do {/container/mounts/remove $m} on-error={}
}

# Remove NAT rule created for container egress.
:foreach n in=[/ip/firewall/nat/find where comment=$natComment] do={
    :do {/ip/firewall/nat/remove $n} on-error={}
}

# Remove WireGuard peers and interface.
:foreach p in=[/interface/wireguard/peers/find where interface=$wgName] do={
    :do {/interface/wireguard/peers/remove $p} on-error={}
}

:foreach wg in=[/interface/wireguard/find where name=$wgName] do={
    :do {/interface/wireguard/remove $wg} on-error={}
}

# Remove IP address from bridge.
:foreach a in=[/ip/address/find where interface=$bridgeName and address=$bridgeAddress] do={
    :do {/ip/address/remove $a} on-error={}
}

# Remove bridge port, veth and bridge.
:foreach bp in=[/interface/bridge/port/find where bridge=$bridgeName and interface=$vethName] do={
    :do {/interface/bridge/port/remove $bp} on-error={}
}

:foreach v in=[/interface/veth/find where name=$vethName] do={
    :do {/interface/veth/remove $v} on-error={}
}

:foreach b in=[/interface/bridge/find where name=$bridgeName] do={
    :do {/interface/bridge/remove $b} on-error={}
}

# Remove ramdisk last, after the container root-dir is no longer used.
:foreach d in=[/disk/find where slot=$ramSlot] do={
    :do {/disk/remove $d} on-error={}
}

:put "Cleanup completed. Verify with: /container/print, /interface/print, /disk/print"
