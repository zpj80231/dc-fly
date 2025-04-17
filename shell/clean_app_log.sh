#!/bin/bash

# 日志文件的根目录
BASE_DIR="/home/dky"

# 符合的日志文件模式
LOG_PATTERN="*.log"

# 定义保留的天数
DAYS_TO_KEEP=5

# 使用 find 查找目标文件并保存到变量
FILES_TO_DELETE=$(find "$BASE_DIR" -type f -name "$LOG_PATTERN" -mtime +$DAYS_TO_KEEP)

# 如果没有找到文件，提示并退出
if [[ -z "$FILES_TO_DELETE" ]]; then
    echo "没有找到需要删除的日志文件。"
    exit 0
fi

# 打印找到的文件
echo "找到以下文件："
echo "$FILES_TO_DELETE"

# 删除文件
echo "$FILES_TO_DELETE" | xargs rm -f

# 遍历 BASE_DIR 下的所有文件夹
# find "$BASE_DIR" -type f -name "$LOG_PATTERN" -mtime +$DAYS_TO_KEEP -exec rm -f {} \;

# 输出操作完成的消息
echo "清理完成：已删除 $BASE_DIR 下超过 $DAYS_TO_KEEP 天的日志文件"

