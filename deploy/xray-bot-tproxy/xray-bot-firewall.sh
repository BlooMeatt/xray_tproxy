#!/usr/bin/env bash
set -euo pipefail

BOT_CONTAINER="${BOT_CONTAINER:-bot}"
BOT_IP="${BOT_IP:-}"
DOCKER_BRIDGE="${DOCKER_BRIDGE:-}"
TPROXY_PORT="${TPROXY_PORT:-12345}"
NAT_CHAIN="${NAT_CHAIN:-XRAY_BOT_TPROXY}"
INPUT_CHAIN="${INPUT_CHAIN:-XRAY_BOT_TPROXY_INPUT}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"

usage() {
  echo "Usage: $0 apply|remove|status"
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root or via sudo" >&2
    exit 1
  fi
}

detect_docker_defaults() {
  if [ -n "$BOT_IP" ] && [ -n "$DOCKER_BRIDGE" ]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI not found; set BOT_IP and DOCKER_BRIDGE explicitly" >&2
    exit 1
  fi

  local inspect network_id bridge_name
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  until docker inspect "$BOT_CONTAINER" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "Container ${BOT_CONTAINER} was not found within ${WAIT_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 2
  done

  until [ "$(docker inspect --format '{{.State.Running}}' "$BOT_CONTAINER" 2>/dev/null)" = "true" ]; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "Container ${BOT_CONTAINER} did not become running within ${WAIT_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 2
  done

  inspect="$(docker inspect --format '{{range $name, $net := .NetworkSettings.Networks}}{{$net.IPAddress}} {{$net.NetworkID}}{{"\n"}}{{end}}' "$BOT_CONTAINER")"
  BOT_IP="${BOT_IP:-$(printf '%s\n' "$inspect" | awk 'NF {print $1; exit}')}"
  network_id="$(printf '%s\n' "$inspect" | awk 'NF {print $2; exit}')"

  if [ -z "$BOT_IP" ] || [ -z "$network_id" ]; then
    echo "Could not detect Docker network details for container ${BOT_CONTAINER}" >&2
    exit 1
  fi

  bridge_name="$(docker network inspect --format '{{index .Options "com.docker.network.bridge.name"}}' "$network_id" 2>/dev/null || true)"
  if [ -z "$bridge_name" ] || [ "$bridge_name" = "<no value>" ]; then
    bridge_name="br-${network_id:0:12}"
  fi
  DOCKER_BRIDGE="${DOCKER_BRIDGE:-$bridge_name}"
}

delete_rule_loop() {
  local table="$1"
  shift
  while iptables -t "$table" -C "$@" 2>/dev/null; do
    iptables -t "$table" -D "$@"
  done
}

apply_rules() {
  need_root
  detect_docker_defaults

  iptables -t nat -N "$NAT_CHAIN" 2>/dev/null || true
  iptables -t nat -F "$NAT_CHAIN"

  iptables -t nat -A "$NAT_CHAIN" -d 0.0.0.0/8 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 10.0.0.0/8 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 100.64.0.0/10 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 127.0.0.0/8 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 169.254.0.0/16 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 172.16.0.0/12 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 192.168.0.0/16 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 224.0.0.0/4 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -d 240.0.0.0/4 -j RETURN
  iptables -t nat -A "$NAT_CHAIN" -p tcp -j REDIRECT --to-ports "$TPROXY_PORT"

  delete_rule_loop nat PREROUTING -i "$DOCKER_BRIDGE" -s "$BOT_IP" -p tcp -m conntrack --ctstate NEW -j "$NAT_CHAIN"
  iptables -t nat -I PREROUTING 1 -i "$DOCKER_BRIDGE" -s "$BOT_IP" -p tcp -m conntrack --ctstate NEW -j "$NAT_CHAIN"

  iptables -N "$INPUT_CHAIN" 2>/dev/null || true
  iptables -F "$INPUT_CHAIN"
  iptables -A "$INPUT_CHAIN" -i "$DOCKER_BRIDGE" -j RETURN
  iptables -A "$INPUT_CHAIN" -i lo -j RETURN
  iptables -A "$INPUT_CHAIN" -j DROP

  delete_rule_loop filter INPUT -p tcp --dport "$TPROXY_PORT" -j "$INPUT_CHAIN"
  iptables -I INPUT 1 -p tcp --dport "$TPROXY_PORT" -j "$INPUT_CHAIN"

  echo "Applied transparent redirect for ${BOT_IP} on ${DOCKER_BRIDGE} to TCP ${TPROXY_PORT}"
}

remove_rules() {
  need_root
  detect_docker_defaults

  delete_rule_loop nat PREROUTING -i "$DOCKER_BRIDGE" -s "$BOT_IP" -p tcp -m conntrack --ctstate NEW -j "$NAT_CHAIN"
  iptables -t nat -F "$NAT_CHAIN" 2>/dev/null || true
  iptables -t nat -X "$NAT_CHAIN" 2>/dev/null || true

  delete_rule_loop filter INPUT -p tcp --dport "$TPROXY_PORT" -j "$INPUT_CHAIN"
  iptables -F "$INPUT_CHAIN" 2>/dev/null || true
  iptables -X "$INPUT_CHAIN" 2>/dev/null || true

  echo "Removed transparent redirect rules"
}

status_rules() {
  need_root
  detect_docker_defaults
  echo "BOT_CONTAINER=${BOT_CONTAINER}"
  echo "BOT_IP=${BOT_IP}"
  echo "DOCKER_BRIDGE=${DOCKER_BRIDGE}"
  echo "TPROXY_PORT=${TPROXY_PORT}"
  echo
  echo "### nat/${NAT_CHAIN}"
  iptables -t nat -S "$NAT_CHAIN" 2>/dev/null || true
  echo
  echo "### nat/PREROUTING hooks"
  iptables -t nat -S PREROUTING | grep -F "$NAT_CHAIN" || true
  echo
  echo "### filter/${INPUT_CHAIN}"
  iptables -S "$INPUT_CHAIN" 2>/dev/null || true
  echo
  echo "### filter/INPUT hooks"
  iptables -S INPUT | grep -F "$INPUT_CHAIN" || true
}

case "${1:-}" in
  apply)
    apply_rules
    ;;
  remove)
    remove_rules
    ;;
  status)
    status_rules
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
