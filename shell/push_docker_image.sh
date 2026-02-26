#!/bin/bash

# 批量推送Docker镜像到多台服务器
# 单个镜像推送：docker save openjdk:8 | ssh root@192.168.1.119 "docker load"

set -e

IMAGE="openjdk:8"
TMP_FILE="/tmp/openjdk8.tar.gz"

IPS=(
  192.168.0.10
  192.168.1.119
  192.168.0.111
  192.168.0.220
  192.168.0.221
  192.168.1.88
  192.168.1.226
  192.168.1.60
  192.168.1.211
  192.168.1.186
  192.168.1.11
  192.168.1.102
  192.168.1.176
)

echo ">>> 保存镜像：$IMAGE"
docker save "$IMAGE" | gzip > "$TMP_FILE"

for ip in "${IPS[@]}"; do
  echo "=============================="
  echo ">>> 推送并加载到 $ip"
  cat "$TMP_FILE" | ssh root@$ip "gunzip | docker load" \
    && echo "[$ip] ✔ 加载成功" \
    || echo "[$ip] ✘ 加载失败"
done

echo ">>> 全部完成"

