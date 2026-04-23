# Prerequisites:
# 1. RouterOS v7 with installed container package.
# 2. Container mode enabled manually:
#    /system/device-mode/update container=yes
# 3. config.json is already uploaded to RouterOS files root.
# 4. config.json already contains Xray WireGuard private key and this router's WireGuard public key.

:local containerName "xray"
:local imageName "xtls/xray-core:latest"
:local registryUrl "https://ghcr.io"

:local ramSlot "ramdisk1"
:local ramSize "128M"
:local rootDir ($ramSlot . "/xray")
:local tmpDir ($ramSlot . "/tmp")

:local bridgeName "containers-bridge"
:local bridgeAddress "192.168.150.1/24"
:local vethName "veth-xray"
:local vethAddress "192.168.150.2/24"
:local vethGateway "192.168.150.1"
:local containerSubnet "192.168.150.0/24"

:local wgName "wg-xray"
:local routerWgListenPort 7443
:local routerWgPrivateKey "REPLACE_WITH_ROUTER_WG_PRIVATE_KEY"
:local xrayWgPublicKey "REPLACE_WITH_XRAY_WG_PUBLIC_KEY"
:local xrayEndpointAddress "192.168.150.2"
:local xrayEndpointPort 51820

:local mountList "xray-config"
:local configSource "config.json"
:local configTarget "/etc/xray/config.json"

:local natComment "xray-container-nat"

# Cleanup for reruns.
:foreach c in=[/container/find where name=$containerName] do={
    :do {/container/stop $c} on-error={}
    :delay 2s
    :do {/container/remove $c} on-error={}
}

:foreach m in=[/container/mounts/find where list=$mountList] do={
    /container/mounts/remove $m
}

:foreach p in=[/interface/wireguard/peers/find where interface=$wgName] do={
    /interface/wireguard/peers/remove $p
}

:foreach n in=[/ip/firewall/nat/find where comment=$natComment] do={
    /ip/firewall/nat/remove $n
}

:foreach a in=[/ip/address/find where interface=$bridgeName and address=$bridgeAddress] do={
    /ip/address/remove $a
}

:foreach bp in=[/interface/bridge/port/find where bridge=$bridgeName and interface=$vethName] do={
    /interface/bridge/port/remove $bp
}

:foreach wg in=[/interface/wireguard/find where name=$wgName] do={
    /interface/wireguard/remove $wg
}

:foreach v in=[/interface/veth/find where name=$vethName] do={
    /interface/veth/remove $v
}

:foreach b in=[/interface/bridge/find where name=$bridgeName] do={
    /interface/bridge/remove $b
}

# Allocate 128M of RAM as a block device and format it with ext4.
:if ([:len [/disk/find where slot=$ramSlot]] = 0) do={
    /disk/add type=ramdisk slot=$ramSlot ramdisk-size=$ramSize
    :delay 1s
}
/disk/format $ramSlot file-system=ext4

# Container extraction uses tmpdir, container root lives on the same ramdisk.
/container/config/set registry-url=$registryUrl tmpdir=$tmpDir

# Container network.
/interface/bridge/add name=$bridgeName
/ip/address/add address=$bridgeAddress interface=$bridgeName
/interface/veth/add name=$vethName address=$vethAddress gateway=$vethGateway
/interface/bridge/port/add bridge=$bridgeName interface=$vethName
/ip/firewall/nat/add chain=srcnat action=masquerade src-address=$containerSubnet comment=$natComment

# Local RouterOS WireGuard peer towards Xray's WireGuard inbound in the container.
/interface/wireguard/add name=$wgName listen-port=$routerWgListenPort mtu=1420 private-key=$routerWgPrivateKey
/interface/wireguard/peers/add interface=$wgName public-key=$xrayWgPublicKey endpoint-address=$xrayEndpointAddress endpoint-port=$xrayEndpointPort allowed-address=0.0.0.0/0,::/0 persistent-keepalive=25s

# Read-only mount for the already uploaded config file.
/container/mounts/add list=$mountList src=$configSource dst=$configTarget read-only=yes

# Pull and create the official Xray container from GHCR.
/container/add remote-image=$imageName interface=$vethName root-dir=$rootDir mountlists=$mountList cmd="run -config /etc/xray/config.json" name=$containerName start-on-boot=yes logging=yes

# Wait until the image is pulled/extracted, then start the container.
:local c [/container/find where name=$containerName]
:for i from=1 to=180 do={
    :local st [/container/get $c status]
    :if (($st = "stopped") or ($st = "created")) do={
        /container/start $c
        :set i 181
    }
    :if ($st = "running") do={
        :set i 181
    }
    :delay 2s
}

:put "Done. Verify with: /container/print and /log/print where message~\"xray\""
