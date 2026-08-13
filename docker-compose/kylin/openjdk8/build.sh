#!/bin/bash

# 构建麒麟系统的 OpenJDK 镜像，镜像名为：openjdk:8-kylin

docker build -t openjdk:8-kylin .

docker run --rm openjdk:8-kylin

docker save -o openjdk-8-kylin.tar openjdk:8-kylin
