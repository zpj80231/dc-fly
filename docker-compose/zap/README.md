# OWASP ZAP 扫描

## 基本用法

在本目录运行：

```bash
./scan.sh https://example.com
./scan.sh https://example.com baseline
./scan.sh https://example.com full
```

`baseline` 运行爬虫和被动扫描，`full` 还会运行主动扫描。主动扫描会向目标发送攻击载荷，只应对已获授权的目标使用。

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
reports/<主机>-<扫描模式>-<时间戳>/report.html
```

## 验证模板

修改模板后运行：

```bash
sh ./test_report_template.sh
docker compose config
```

测试会验证模板元数据、HTML 结构、离线资源、Compose 挂载、默认模板名称和中文 locale。真实报告仍建议使用一个已授权的测试目标执行 baseline 扫描确认。
