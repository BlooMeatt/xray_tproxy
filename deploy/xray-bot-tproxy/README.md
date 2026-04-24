# Xray transparent proxy for Intradesk bot

This directory stores the runtime files deployed to `srv-intradesk-bot-01`
for transparent proxying of the existing Docker container named `bot`.

The bot compose project itself is not modified. Traffic is redirected by
iptables from the bot container on its Docker bridge to Xray's local
`dokodemo-door` inbound.

## Installed paths on the VM

```text
/opt/xray-bot/config.json
/opt/xray-bot/compose.yaml
/opt/xray-bot/xray-bot-firewall.sh
/etc/systemd/system/xray-bot-firewall.service
```

## Behavior

- Xray listens on TCP `12345` in host network mode.
- `xray-bot-firewall.service` applies dynamic iptables rules at boot.
- The firewall script detects the current IP and bridge of container `bot`.
- Private, localhost, multicast, and reserved ranges are excluded.
- `api.telegram.org` goes through `proxy-auto`.
- `apigw.intradesk.ru` also goes through `proxy-auto` via the
  `proxy-intradesk-api` rule before the generic `.ru` block rule.

## Deploy

```bash
sudo mkdir -p /opt/xray-bot
sudo install -m 0644 config.json /opt/xray-bot/config.json
sudo install -m 0644 compose.yaml /opt/xray-bot/compose.yaml
sudo install -m 0755 xray-bot-firewall.sh /opt/xray-bot/xray-bot-firewall.sh
sudo install -m 0644 xray-bot-firewall.service /etc/systemd/system/xray-bot-firewall.service

cd /opt/xray-bot
sudo docker compose -f compose.yaml up -d

sudo systemctl daemon-reload
sudo systemctl enable --now xray-bot-firewall.service
```

## Verify

```bash
sudo docker logs --tail 200 xray-bot-tproxy
sudo docker logs --tail 200 bot
sudo /opt/xray-bot/xray-bot-firewall.sh status
```

Expected route examples in Xray logs:

```text
api.telegram.org -> transparent-to-balanced-vless -> proxy-*
apigw.intradesk.ru -> proxy-intradesk-api -> proxy-*
```

## Rollback

```bash
sudo systemctl disable --now xray-bot-firewall.service
sudo /opt/xray-bot/xray-bot-firewall.sh remove
cd /opt/xray-bot && sudo docker compose -f compose.yaml down
```
