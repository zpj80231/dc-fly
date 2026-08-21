# OWASP ZAP 扫描

## 基本用法

在本目录运行：

```bash
./scan.sh https://example.com
./scan.sh https://example.com baseline
./scan.sh https://example.com full
```

`baseline` 运行爬虫和被动扫描，`full` 还会运行主动扫描。主动扫描会向目标发送攻击载荷，只应对已获授权的目标使用。

默认扫描计划为了尽量接近整站扫描工具的覆盖范围，会依次执行：

1. 传统 Spider，最多运行 15 分钟，负责快速发现普通 HTML、静态资源、robots.txt 和 sitemap.xml 链接；
2. Ajax Spider，最多运行 10 分钟，使用无头浏览器发现 JavaScript 动态路由和默认可点击元素；
3. 等待所有已发现响应完成被动扫描；
4. `full` 模式再对当前 Context 内已发现的 URL 执行主动扫描。

Spider 的时间上限不是 URL 数量保证。实际数量还取决于入口页面、登录状态、链接是否由前端动态生成、Context 范围、站点响应速度和 robots/排除规则。要与其他工具进行有效对比，应使用相同目标、相同认证状态、相同时间窗口，并确认扫描链接数后再比较漏洞数量。

默认计划不会自动登录业务系统，也不会随机填写表单；需要覆盖登录后页面时，应在 Context 中配置认证和用户，或提供经过授权的入口流量。对于需要登录的系统，仅延长 Spider 时间不能替代认证配置。

## 配置不会再被覆盖

ZAP 的 `zap-baseline.py` 和 `zap-full-scan.py` 默认使用 Automation Framework，并会把动态生成的计划复制成挂载目录中的 `zap.yaml`。本脚本不再调用这两个 packaged scan，而是：

1. baseline 读取 `zap.yaml`，full 读取 `zap-full.yaml`；
2. 在 `.zap-runtime/` 生成一次性计划；
3. 使用 `zap.sh -cmd -autorun` 执行该计划；
4. 扫描结束后删除一次性计划。

因此可以直接维护两个 YAML 文件。自定义计划必须保留以下占位符：

- `__TARGET_URL__`
- `__REPORT_DIR__`
- `__REPORT_TEMPLATE__`

也可以指定其他配置模板：

```bash
./scan.sh https://example.com --config ./my-zap.yaml
```

## 自定义中文报告模板

默认使用本项目提供的 `security-review` 模板，目录为：

```text
report-templates/security-review/
├── template.yaml
├── report.html
├── Messages.properties
├── Messages_zh_CN.properties
└── resources/report.css
```

模板会由 Compose 只读挂载到 ZAP Home 的
`/home/zap/.ZAP/reports/security-review`。报告包含：

- 高危、中危、低危、信息类告警的横向柱状图；
- 漏洞类型、风险级别、实例数、规则 ID、CWE、WASC 汇总；
- URL、方法、参数、攻击载荷、证据、描述和参考资料等漏洞详情；
- 站点页面引用的外部链接列表（域名、引用次数、引用类型、示例链接、来源页面）；
- 根据风险数量自动生成的总结分析；
- 每条 ZAP 规则自带的修复方案和报告级总体修复建议。

横向柱状图使用纯 HTML/CSS 实现，不依赖公网资源或特定版本的
Chart.js，生成的报告可以离线打开。

继续定制时，各文件职责如下：

- `template.yaml`：模板名称、格式和可选报告区块；
- `report.html`：Thymeleaf 页面结构和 ZAP 数据绑定；
- `resources/report.css`：屏幕、移动端和打印样式；
- `Messages.properties`：模板区块的英文名称；
- `Messages_zh_CN.properties`：模板区块的中文名称。

`report.html` 中常用的数据对象：

- `${alertCounts}`：按风险等级统计唯一漏洞类型；
- `${alertTree.children}`：所有漏洞类型；
- `${alert.children}`：同一漏洞类型的 URL 实例；
- `${alert.userObject}`：描述、证据、修复方案、CWE、WASC 等字段；
- `${helper}`：风险等级、置信度等本地化辅助方法。

直接运行：

```bash
./scan.sh https://example.com
./scan.sh https://example.com full
```

## 外部链接列表

ZAP 的报告数据只暴露告警树和站点列表，模板本身拿不到「页面里引用了哪些第三方域名」。
因此外部链接列表由三步拼出来：

1. 扫描计划最后追加一个 `export` 任务（Import/Export add-on 提供），把本次会话的
   HTTP 历史导出成 `reports/<目录>/traffic.har`：

   ```yaml
   - type: export
     parameters:
       fileName: __HAR_FILE__
       type: har
       source: all
   ```

   自定义计划想要这一章节时，需要保留 `__HAR_FILE__` 占位符（该占位符是可选的，
   缺失时 `scan.sh` 不会报错，只是跳过外部链接提取）。

2. `scan.sh` 在扫描结束后调用 `tools/external_links.py`，解析 HAR 中 HTML/CSS/JS
   响应体，抽取 `a/script/link/img/iframe/form` 等标签属性、CSS `url()` 以及脚本里的
   绝对 URL，按域名归并并剔除与目标同基础域名（含子域）的链接。

3. 提取结果写入报告模板 `<!-- EXTERNAL_LINKS_BEGIN -->` 与
   `<!-- EXTERNAL_LINKS_END -->` 之间，同时输出机器可读的
   `reports/<目录>/external-links.json`。

`source: all` 会包含 Spider、Ajax Spider 和其他扫描任务产生的流量；`history` 只适合导出部分 HTTP 历史，可能遗漏爬虫请求。缺少 HAR、没装 `python3` 或未发现外部域名时，报告会保留占位说明，扫描本身不受影响。

验证提取与注入逻辑（不需要 Docker）：

```bash
sh ./tools/test_external_links.sh
```

## 切换到其他报告模板

如需临时切回 ZAP 内置模板：

```bash
./scan.sh https://example.com --template traditional-html
./scan.sh https://example.com --template traditional-html-plus
./scan.sh https://example.com --template high-level-report
./scan.sh https://example.com --template risk-confidence-html
```

除 `security-review` 外，模板必须已经包含在当前 ZAP 镜像的 Reports add-on 中。模板名无效时，ZAP 会在运行计划时列出错误。

## 中文报告

默认传入 `view.locale=zh_CN`，Reports add-on 会使用简体中文资源：

```bash
./scan.sh https://example.com --lang zh_CN
```

可用环境变量设置默认值：

```bash
ZAP_REPORT_TEMPLATE=traditional-html-plus \
ZAP_REPORT_LANG=zh_CN \
./scan.sh https://example.com
```

注意：报告的栏目、风险等级等界面文本会中文化；漏洞名称、说明和解决方案是否完整中文，取决于对应 ZAP 扫描规则是否提供中文翻译。未翻译的规则内容仍可能显示英文。

## 输出

每次扫描会生成独立目录：

```text
reports/<主机>-<扫描模式>-<时间戳>/
├── report.html            # 安全检测报告
├── traffic.har            # 会话流量导出（外部链接提取输入）
└── external-links.json    # 外部链接明细
```

## 验证模板

修改模板后运行：

```bash
sh ./test_report_branding.sh
sh ./test_scan_configuration.sh
sh ./tools/test_external_links.sh
docker compose config
```

测试会验证模板元数据、HTML 结构、离线资源、Compose 挂载、默认模板名称和中文 locale。真实报告仍建议使用一个已授权的测试目标执行 baseline 扫描确认。
