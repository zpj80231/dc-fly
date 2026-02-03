#!/bin/bash

# 批量添加SSH已知主机

IPS=(
  192.168.0.71
  192.168.0.174
  192.168.254.2
  192.168.254.206
)

SSH_DIR="$HOME/.ssh"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

mkdir -p "$SSH_DIR"
touch "$KNOWN_HOSTS"

for ip in "${IPS[@]}"; do
    echo ">>> scanning $ip"
    ssh-keyscan -H "$ip" 2>/dev/null | grep -v -f "$KNOWN_HOSTS" >> "$KNOWN_HOSTS"
done

echo "done."

