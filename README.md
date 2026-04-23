# xray_tproxy

Базовый набор для деплоя `Xray-core` с `WireGuard` inbound и тремя `VLESS REALITY` outbound.

Проект не занимается маршрутизацией трафика на хосте или на MikroTik. Здесь только:
- [config.json](/Users/valera/GIT/xray_tproxy/config.json) с конфигом Xray
- [compose.yaml](/Users/valera/GIT/xray_tproxy/compose.yaml) для Linux VM
- [mikrotik-xray-deploy.rsc](/Users/valera/GIT/xray_tproxy/mikrotik-xray-deploy.rsc) для развёртывания контейнера на RouterOS
- [mikrotik-xray-cleanup.rsc](/Users/valera/GIT/xray_tproxy/mikrotik-xray-cleanup.rsc) для полной очистки

## Что внутри config.json

- `WireGuard` inbound на `51820/udp`
- 3 `VLESS REALITY` outbound: `proxy-se`, `proxy-nl`, `proxy-us`
- балансировка через `leastLoad`
- проверка доступности через `burstObservatory`
- fallback в `direct`, если все proxy-outbound недоступны
- блокировка `bittorrent`
- блокировка `.ru` и `geosite:category-ru`

## Подготовка ключей WireGuard

Для Xray и для MikroTik нужна отдельная пара ключей.

Пример на Linux с `wireguard-tools`:

```bash
umask 077

wg genkey | tee xray-wg-private.key | wg pubkey > xray-wg-public.key
wg genkey | tee mikrotik-wg-private.key | wg pubkey > mikrotik-wg-public.key
```

Куда подставлять:

- содержимое `xray-wg-private.key` вставить в `config.json` в `inbounds[0].settings.secretKey`
- содержимое `mikrotik-wg-public.key` вставить в `config.json` в `inbounds[0].settings.peers[0].publicKey`
- содержимое `mikrotik-wg-private.key` вставить в [mikrotik-xray-deploy.rsc](/Users/valera/GIT/xray_tproxy/mikrotik-xray-deploy.rsc) в `routerWgPrivateKey`
- содержимое `xray-wg-public.key` вставить в [mikrotik-xray-deploy.rsc](/Users/valera/GIT/xray_tproxy/mikrotik-xray-deploy.rsc) в `xrayWgPublicKey`

После этого сохраните обновлённый [config.json](/Users/valera/GIT/xray_tproxy/config.json).

## Деплой на Linux VM

Требования:
- Docker Engine
- Docker Compose plugin

Запуск:

```bash
docker compose up -d
```

Проверка:

```bash
docker compose logs -f xray
```

Остановка:

```bash
docker compose down
```

## Деплой на MikroTik

Требования:
- RouterOS v7
- установлен пакет `container`
- вручную включён container mode
- файл `config.json` уже загружен в `/file`

Что делает deploy-скрипт:
- откусывает `128M` RAM под `ramdisk`
- форматирует `ext4`
- создаёт `bridge`, `veth`, NAT и локальный `WireGuard` peer до Xray
- тянет `ghcr.io/xtls/xray-core:latest`
- монтирует `config.json` в контейнер только на чтение
- запускает контейнер `xray`

Запуск:

```routeros
/import file-name=mikrotik-xray-deploy.rsc
```

Очистка:

```routeros
/import file-name=mikrotik-xray-cleanup.rsc
```

## Замечания

- В `config.json` уже зашиты адреса и параметры трёх `VLESS REALITY` узлов.
- `costs` сейчас выставлены так, чтобы предпочитать `proxy-se`, затем `proxy-nl`, затем `proxy-us`.
- Если на MikroTik не хватает памяти для pull/extract образа, первым делом увеличьте `ramSize` в [mikrotik-xray-deploy.rsc](/Users/valera/GIT/xray_tproxy/mikrotik-xray-deploy.rsc).
