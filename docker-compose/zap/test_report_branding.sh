#!/bin/sh

set -eu

TEMPLATE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/report-templates/security-review" && pwd)"
REPORT_FILE="${TEMPLATE_DIR}/report.html"

if rg -n -i 'zap|owasp|zapversion|security review' "${REPORT_FILE}" >/dev/null; then
    echo "FAIL: 报告模板仍包含扫描工具品牌信息" >&2
    exit 1
fi

for heading in "站点概况" "风险分类统计" "Web风险分布" "漏洞详情" "安全建议"; do
    rg -F "${heading}" "${REPORT_FILE}" >/dev/null || {
        echo "FAIL: 缺少正式报告章节：${heading}" >&2
        exit 1
    }
done

rg -F 'font-family: "SimSun"' "${TEMPLATE_DIR}/resources/report.css" >/dev/null || {
    echo "FAIL: 未使用正式报告中文字体" >&2
    exit 1
}

echo "PASS: 报告品牌脱敏与正式版式"
