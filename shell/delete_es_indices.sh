#!/bin/bash

# 设置当前日期和删除日期（20 天前）
today=$(date +%Y-%m-%d)
delete_before=$(date -d "$today -20 days" +%Y.%m.%d)

# 获取所有索引，按存储大小降序排列，并过滤出有效的索引名（跳过表头等无关信息）
indices=$(curl -s -X GET "localhost:9200/_cat/indices?v&s=store.size:desc" | awk 'NR>1 {print $3}')

# 循环遍历索引列表，删除 20 天前的索引
for index in $indices; do
  # 跳过.kibana和其他系统索引，避免误删
  if [[ $index == .* ]]; then
    echo "Skipping system index: $index"
    continue
  fi
  
  # 提取索引中的日期部分，例如 service-logs-2024.08.01 -> 2024.08.01
  index_date=$(echo $index | grep -oP '\d{4}\.\d{2}\.\d{2}')
  
  if [[ -z "$index_date" ]]; then
    echo "Skipping index without date: $index"
    continue
  fi

  if [[ "$index_date" < "$delete_before" ]]; then
    echo "Deleting index: $index"
    curl -X DELETE "localhost:9200/$index"
  fi
done

