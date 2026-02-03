#!/bin/bash

# 该脚本用于批量注册多个SIP分机，并保持注册

# 配置参数
projectId="20020001001"      # 项目ID
startExtension=3010          # 起始分机号
endExtension=3050            # 结束分机号
password="123456"
registrationInterval=30      # 保持注册间隔（秒）
cleanupOnExit=true           # 是否在退出时清理临时文件
agentLoadUrl="http://localhost/gw2/dial-resource/server/agentLoad?extensionType=1&projectId=${projectId}"

# 安装必要工具
if ! command -v jq &> /dev/null; then
    echo "正在安装jq..."
    sudo yum install -y epel-release
    sudo yum install -y jq
fi

if ! command -v sipsak &> /dev/null; then
    echo "正在安装sipsak编译依赖..."
    sudo yum groupinstall -y 'Development Tools'
    sudo yum install -y autoconf automake pkgconfig libxml2-devel openssl-devel

    echo "下载并编译安装sipsak..."
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    wget https://github.com/nils-ohlmeier/sipsak/releases/download/0.9.8.1/sipsak-0.9.8.1.tar.gz
    tar -zxvf sipsak-0.9.8.1.tar.gz
    cd sipsak-0.9.8.1
    ./configure
    make
    sudo make install
    cd /tmp
    rm -rf "$temp_dir"
fi

# 注册函数
register_extension() {
    local fullExtension=$1
    local realm=$2
    local wanport=$3
    local log_file="/tmp/sipsak_${fullExtension}.log"
    
    # 清除旧日志
    rm -f "$log_file"
    
    # 执行注册并捕获输出到日志文件
    timeout 5s sipsak -U -s "sip:${fullExtension}@${realm}:${wanport}" \
        -a "$password" -i -vvv > "$log_file" 2>&1
    
    # 检查注册结果
    if grep -q "All usrloc tests completed successful" "$log_file"; then
        echo "✅ 分机 sip:${fullExtension}@${realm}:${wanport} 注册成功"
        return 0
    elif grep -q "Unexpected message" "$log_file"; then
        echo "⚠️  分机 ${fullExtension} 可能已注册"
        return 0
    else
        echo "❌ 分机 ${fullExtension} 注册失败"
        # 显示最后3行日志
        tail -n 3 "$log_file"
        return 1
    fi
}

# 保持注册函数
keep_registered() {
    local fullExtension=$1
    local realm=$2
    local wanport=$3
    local log_file="/tmp/sipsak_${fullExtension}.log"
    
    # 记录保持注册开始时间
    local start_time=$(date +%s)
    local registration_count=0
    
    while true; do
        sleep $registrationInterval
        
        # 计算注册次数和耗时
        registration_count=$((registration_count + 1))
        local elapsed_time=$(($(date +%s) - start_time))
        
        # 打印保持注册信息
        echo "注册保持 (${registration_count}次/${elapsed_time}秒): ${fullExtension}@${realm}:${wanport}"
        
        # 执行注册
        sipsak -U -s "sip:${fullExtension}@${realm}:${wanport}" \
            -a "$password" -i -vvv > /dev/null 2>&1
        
        # 定期检查连接状态（每10次检查一次）
        if [ $((registration_count % 10)) -eq 0 ]; then
            if timeout 5s sipsak -C -s "sip:${realm}:${wanport}" > /dev/null 2>&1; then
                echo "🔍 服务器连接正常"
            else
                echo "⚠️  服务器连接异常，尝试重新注册"
                response=$(curl -s "$agentLoadUrl")
                realm=$(echo "$response" | jq -r '.data.registerServer.realm')
                wanport=$(echo "$response" | jq -r '.data.registerServer.wanport')
                # 检查：如果realm为空或无效
                if [[ -z "$realm" || "$realm" == "null" || "$wanport" -eq 0 ]]; then
                    echo "⛔ 获取的注册服务器无效 ($fullExtension, realm: '$realm', wanport: $wanport)，等待10秒后重试..."
                    sleep 10
                    continue # 跳过本次循环的剩余部分，直接重新开始
                fi
                # 执行重新注册
                if register_extension "$fullExtension" "$realm" "$wanport"; then
                    echo "✅ $fullExtension $realm $wanport 重新注册成功，继续保持注册"
                else
                    echo "❌ $fullExtension $realm $wanport 重新注册失败，等待重新注册"
                fi
            fi
        fi
    done
}

# 清理函数
cleanup() {
    echo "清理临时文件..."
    # 清理所有分机的日志文件
    rm -f /tmp/sipsak_${projectId}*.log
    # 清理所有分机的PID文件
    rm -f /tmp/keepalive_${projectId}*.pid
}

# 注册退出处理函数
trap 'handle_exit' EXIT

handle_exit() {
    # 停止所有后台任务
    echo "停止所有后台任务..."
    pids=$(ls /tmp/keepalive_*.pid 2>/dev/null | xargs cat 2>/dev/null)
    
    if [ -n "$pids" ]; then
        kill $pids
        # 等待任务结束
        wait $pids 2>/dev/null
        echo "已停止所有后台任务"
    fi
    
    # 清理临时文件
    if [ "$cleanupOnExit" = true ]; then
        cleanup
    fi
    
    exit 0
}

# 循环分机号
for extension in $(seq $startExtension $endExtension); do
    # 拼接完整分机号
    fullExtension="${projectId}${extension}"
    
    # 注册失败时重新获取注册服务器信息并重试
    while true; do
        # 调用API获取注册服务器信息
        response=$(curl -s "$agentLoadUrl")
        # 提取注册服务器信息
        realm=$(echo "$response" | jq -r '.data.registerServer.realm')
        wanip=$(echo "$response" | jq -r '.data.registerServer.wanip')
        lanip=$(echo "$response" | jq -r '.data.registerServer.lanip')
        wanport=$(echo "$response" | jq -r '.data.registerServer.wanport')
        
        # 检查：如果realm为空或无效
        if [[ -z "$realm" || "$realm" == "null" || "$wanport" -eq 0 ]]; then
            echo "⛔ 获取的注册服务器无效 (realm: '$realm', wanport: $wanport)，等待10秒后重试..."
            sleep 10
            continue # 跳过本次循环的剩余部分，直接重新开始
        fi

        # 执行注册
        if register_extension "$fullExtension" "$realm" "$wanport"; then
            # 注册成功 - 启动后台任务维持注册
            keep_registered "$fullExtension" "$realm" "$wanport" &
            background_pid=$!
            # 保存后台PID用于管理
            echo $background_pid > "/tmp/keepalive_${fullExtension}.pid"
            break
        else
            # 注册失败，等待5秒后重新获取服务器信息并重试
            echo "⏳ 注册失败，等待10秒后重试..."
            sleep 10
        fi
    done

    # 避免请求过于频繁
    sleep 1
done

echo "所有分机处理完成 (${startExtension}-${endExtension})。按 CTRL+C 退出脚本。"

# 保持主脚本运行以维持后台任务
while true; do
    sleep 3600  # 每小时唤醒一次
done