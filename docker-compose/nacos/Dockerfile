# 基础镜像
#FROM nacos/nacos-server:v2.3.0
FROM zhusaidong/nacos-server-m1:2.0.3

# 使用软连接，并且将时区配置覆盖/etc/timezone
RUN ln -snf /usr/share/zoneinfo/$TimeZone /etc/localtime && echo $TimeZone > /etc/timezone