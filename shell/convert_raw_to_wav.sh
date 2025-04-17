#!/bin/bash

# 获取脚本所在的目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# 遍历当前目录下的所有 .raw 文件
for raw_file in *.raw
do
  # 获取文件名，不包括扩展名
  base_name="${raw_file%.raw}"

  # 定义对应的 .wav 文件名
  wav_file="${base_name}.wav"

  # 如果 .wav 文件不存在，则进行转换
  if [ ! -f "$wav_file" ]; then
    echo "Converting $raw_file to $wav_file"
    sox -r 8000 -e signed-integer -b 16 "$raw_file" "$wav_file"
    
    # 如果转换成功，删除原始的 .raw 文件
    if [ $? -eq 0 ]; then
      # echo "Deleting $raw_file..."
      rm "$raw_file"
    else
      echo "Conversion failed for $raw_file. File not deleted."
    fi
  fi
done

echo "Conversion complete."

