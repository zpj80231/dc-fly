#!/bin/sh
# 验证外部链接提取与报告注入（不需要 Docker）
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT HUP INT TERM

cat > "${WORK_DIR}/traffic.har" <<'HAR'
{
  "log": {
    "entries": [
      {
        "request": {"url": "https://example.com/index.html"},
        "response": {"content": {"mimeType": "text/html;charset=utf-8", "text":
          "<html><head><link href=\"https://cdn.bootcss.com/a.css\" rel=\"stylesheet\"><script src=\"//cdn.bootcss.com/b.js\"></script></head><body><a href=\"https://www.baidu.com/s?wd=1\">百度</a><a href=\"/local/page\">本站</a><a href=\"https://sub.example.com/ok\">同域</a><img src=\"https://img.thirdparty.cn/x.png\"><iframe src=\"https://player.youku.com/v\"></iframe><form action=\"https://pay.thirdparty.cn/submit\"></form></body></html>"
        }}
      },
      {
        "request": {"url": "https://example.com/app.css"},
        "response": {"content": {"mimeType": "text/css", "text":
          "body{background:url(https://img.thirdparty.cn/bg.png)}"
        }}
      },
      {
        "request": {"url": "https://example.com/app.js"},
        "response": {"content": {"mimeType": "application/javascript", "text":
          "var api='https://api.thirdparty.cn/v1/track';"
        }}
      },
      {
        "request": {"url": "https://example.com/logo.png"},
        "response": {"content": {"mimeType": "image/png", "encoding": "base64", "text": "iVBORw0KGgo="}}
      }
    ]
  }
}
HAR

cat > "${WORK_DIR}/report.html" <<'HTML'
<html><body>
<section class="section" id="external-links">
  <h2>外部链接列表</h2>
  <!-- EXTERNAL_LINKS_BEGIN -->
  <div class="empty">占位说明</div>
  <!-- EXTERNAL_LINKS_END -->
</section>
</body></html>
HTML

python3 "${SCRIPT_DIR}/external_links.py" \
    --har "${WORK_DIR}/traffic.har" \
    --target "https://example.com" \
    --report "${WORK_DIR}/report.html" \
    --json "${WORK_DIR}/external-links.json"

assert_contains() {
    grep -F "$2" "$1" >/dev/null || { echo "FAIL: $1 缺少内容：$2" >&2; exit 1; }
}
assert_missing() {
    if grep -F "$2" "$1" >/dev/null; then
        echo "FAIL: $1 不应包含：$2" >&2
        exit 1
    fi
}

for host in cdn.bootcss.com www.baidu.com img.thirdparty.cn api.thirdparty.cn player.youku.com pay.thirdparty.cn; do
    assert_contains "${WORK_DIR}/report.html" "${host}"
done

assert_missing "${WORK_DIR}/report.html" "占位说明"
assert_missing "${WORK_DIR}/report.html" "sub.example.com"
assert_missing "${WORK_DIR}/report.html" "/local/page"
assert_contains "${WORK_DIR}/report.html" "外部域名"
assert_contains "${WORK_DIR}/report.html" "外部脚本"
assert_contains "${WORK_DIR}/report.html" "表单提交"
assert_contains "${WORK_DIR}/report.html" "内嵌框架"
assert_contains "${WORK_DIR}/external-links.json" "totalHosts"

python3 - "${WORK_DIR}/external-links.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
hosts = {item["host"] for item in data["hosts"]}
assert "sub.example.com" not in hosts, "同基础域名不应计入外部链接"
assert data["totalHosts"] == len(hosts) == 6, data["totalHosts"]
assert data["totalLinks"] >= 7, data["totalLinks"]
img = next(item for item in data["hosts"] if item["host"] == "img.thirdparty.cn")
assert img["count"] == 2, img
print("JSON 校验通过：", data["totalHosts"], "域名 /", data["totalLinks"], "链接")
PY

# 模板中必须保留注入标记
assert_contains "${SCRIPT_DIR}/../report-templates/security-review/report.html" "EXTERNAL_LINKS_BEGIN"
assert_contains "${SCRIPT_DIR}/../report-templates/security-review/report.html" "EXTERNAL_LINKS_END"

echo "PASS: 外部链接提取与报告注入"
