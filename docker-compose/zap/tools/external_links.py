#!/usr/bin/env python3
"""从 ZAP 导出的 HAR 流量中提取外部链接，并写回报告的「外部链接列表」章节。

用法：
  external_links.py --har traffic.har --target https://example.com \
      --report report.html [--json external-links.json]

报告模板需要包含以下标记，脚本会替换两个标记之间的内容：
  <!-- EXTERNAL_LINKS_BEGIN --> ... <!-- EXTERNAL_LINKS_END -->
"""

import argparse
import html
import json
import re
import sys
from collections import OrderedDict
from urllib.parse import urljoin, urlsplit

BEGIN_MARK = "<!-- EXTERNAL_LINKS_BEGIN -->"
END_MARK = "<!-- EXTERNAL_LINKS_END -->"

# 需要按三级后缀切分基础域名的常见公共后缀
MULTI_LABEL_SUFFIXES = (
    "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
    "com.hk", "com.tw", "com.mo", "co.jp", "co.kr", "co.uk", "org.uk",
    "com.au", "com.sg", "com.br",
)

TEXT_MIME_HINTS = ("html", "javascript", "json", "css", "xml", "text/plain")

TAG_KIND = {
    "a": "页面链接",
    "area": "页面链接",
    "script": "外部脚本",
    "link": "外部样式/资源",
    "img": "外部图片",
    "source": "外部媒体",
    "video": "外部媒体",
    "audio": "外部媒体",
    "iframe": "内嵌框架",
    "frame": "内嵌框架",
    "embed": "内嵌对象",
    "object": "内嵌对象",
    "form": "表单提交",
}

TAG_RE = re.compile(
    r"<\s*(a|area|script|link|img|source|video|audio|iframe|frame|embed|object|form)\b([^>]*)>",
    re.IGNORECASE,
)
ATTR_RE = re.compile(
    r"""\b(href|src|action|data|data-src|poster)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))""",
    re.IGNORECASE,
)
CSS_URL_RE = re.compile(r"""url\(\s*['"]?([^'")]+)""", re.IGNORECASE)
BARE_URL_RE = re.compile(r"""https?://[^\s'"<>()\\`]+""", re.IGNORECASE)


def base_domain(host):
    host = (host or "").lower().strip(".")
    if not host or re.fullmatch(r"[\d.]+", host) or ":" in host:
        return host
    labels = host.split(".")
    if len(labels) <= 2:
        return host
    for suffix in MULTI_LABEL_SUFFIXES:
        if host.endswith("." + suffix):
            return ".".join(labels[-3:])
    return ".".join(labels[-2:])


def is_internal(host, internal_domains):
    host = (host or "").lower()
    if not host:
        return True
    return base_domain(host) in internal_domains


def iter_entries(har):
    entries = har.get("log", {}).get("entries") or []
    for entry in entries:
        request = entry.get("request") or {}
        response = entry.get("response") or {}
        content = response.get("content") or {}
        text = content.get("text")
        if not text or content.get("encoding") == "base64":
            continue
        mime = (content.get("mimeType") or "").lower()
        if mime and not any(hint in mime for hint in TEXT_MIME_HINTS):
            continue
        page_url = request.get("url") or ""
        if not page_url:
            continue
        yield page_url, text


def collect_candidates(page_url, body):
    """返回 [(绝对链接, 引用类型)]，同一页面内去重。"""
    found = OrderedDict()

    def add(raw, kind):
        raw = (raw or "").strip().strip("\"'")
        if not raw or raw.startswith(("#", "javascript:", "data:", "mailto:", "tel:")):
            return
        if raw.startswith("//"):
            raw = urlsplit(page_url).scheme + ":" + raw
        elif not raw.lower().startswith(("http://", "https://")):
            return
        absolute = urljoin(page_url, raw)
        found.setdefault(absolute, kind)

    for match in TAG_RE.finditer(body):
        tag = match.group(1).lower()
        kind = TAG_KIND.get(tag, "其他引用")
        for attr in ATTR_RE.finditer(match.group(2)):
            value = attr.group(2) or attr.group(3) or attr.group(4)
            add(value, kind)

    for match in CSS_URL_RE.finditer(body):
        add(match.group(1), "样式表引用")

    for match in BARE_URL_RE.finditer(body):
        add(match.group(0).rstrip(".,;:)]}\"'"), "脚本/文本引用")

    return list(found.items())


def analyse(har, target_url):
    internal_domains = {base_domain(urlsplit(target_url).hostname)}
    hosts = OrderedDict()
    total_links = 0

    for page_url, body in iter_entries(har):
        for link, kind in collect_candidates(page_url, body):
            host = (urlsplit(link).hostname or "").lower()
            if is_internal(host, internal_domains):
                continue
            record = hosts.setdefault(
                host,
                {"host": host, "count": 0, "kinds": OrderedDict(), "links": OrderedDict()},
            )
            record["count"] += 1
            total_links += 1
            record["kinds"][kind] = record["kinds"].get(kind, 0) + 1
            if link not in record["links"]:
                record["links"][link] = page_url

    ordered = sorted(hosts.values(), key=lambda item: (-item["count"], item["host"]))
    for record in ordered:
        record["kinds"] = list(record["kinds"].keys())
        record["links"] = [
            {"url": url, "from": page} for url, page in list(record["links"].items())
        ]
    return {"totalHosts": len(ordered), "totalLinks": total_links, "hosts": ordered}


def esc(text):
    return html.escape(str(text), quote=True)


def shorten(text, limit=110):
    text = str(text)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def render_fragment(result, max_hosts=200, max_links=3):
    if not result["hosts"]:
        return '<div class="empty">本次扫描未在页面内容中发现外部域名引用。</div>'

    parts = [
        '<div class="metrics">',
        '<div class="metric"><div class="metric-label">外部域名</div>'
        f'<div class="metric-value">{result["totalHosts"]}</div></div>',
        '<div class="metric"><div class="metric-label">外部链接</div>'
        f'<div class="metric-value">{result["totalLinks"]}</div></div>',
        "</div>",
        '<div class="table-wrap">',
        "<table>",
        "<thead><tr><th>序号</th><th>外部域名</th><th>引用次数</th>"
        "<th>引用类型</th><th>示例链接</th><th>来源页面</th></tr></thead>",
        "<tbody>",
    ]

    for index, record in enumerate(result["hosts"][:max_hosts], start=1):
        links = record["links"][:max_links]
        samples = "".join(
            f'<div><a href="{esc(item["url"])}">{esc(shorten(item["url"]))}</a></div>'
            for item in links
        )
        if len(record["links"]) > len(links):
            samples += f'<div>等共 {len(record["links"])} 条</div>'
        sources = "".join(
            f"<div>{esc(shorten(item['from'], 90))}</div>" for item in links
        )
        parts.append(
            "<tr>"
            f"<td>{index}</td>"
            f'<td>{esc(record["host"])}</td>'
            f'<td>{record["count"]}</td>'
            f'<td>{esc("、".join(record["kinds"]))}</td>'
            f"<td>{samples}</td>"
            f"<td>{sources}</td>"
            "</tr>"
        )

    parts += ["</tbody>", "</table>", "</div>"]
    if len(result["hosts"]) > max_hosts:
        parts.append(
            f'<p class="section-note">仅展示引用次数最多的 {max_hosts} 个外部域名，'
            f'完整明细见 external-links.json。</p>'
        )
    return "\n".join(parts)


def inject(report_path, fragment):
    with open(report_path, "r", encoding="utf-8") as handle:
        content = handle.read()
    start = content.find(BEGIN_MARK)
    end = content.find(END_MARK)
    if start < 0 or end < 0 or end < start:
        return False
    updated = (
        content[: start + len(BEGIN_MARK)] + "\n" + fragment + "\n" + content[end:]
    )
    with open(report_path, "w", encoding="utf-8") as handle:
        handle.write(updated)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description="提取外部链接并写入安全检测报告")
    parser.add_argument("--har", required=True, help="ZAP 导出的 HAR 文件")
    parser.add_argument("--target", required=True, help="扫描目标 URL")
    parser.add_argument("--report", help="待写入的报告 HTML 文件")
    parser.add_argument("--json", dest="json_out", help="外部链接明细 JSON 输出路径")
    args = parser.parse_args(argv)

    try:
        with open(args.har, "r", encoding="utf-8", errors="replace") as handle:
            har = json.load(handle)
    except (OSError, ValueError) as error:
        print(f"外部链接提取跳过：无法读取 HAR（{error}）", file=sys.stderr)
        return 1

    result = analyse(har, args.target)

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)

    if args.report:
        if not inject(args.report, render_fragment(result)):
            print("外部链接提取跳过：报告中缺少 EXTERNAL_LINKS 标记", file=sys.stderr)
            return 2

    print(
        f"外部链接：{result['totalHosts']} 个域名 / {result['totalLinks']} 条引用"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
