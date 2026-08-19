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

## 切换报告模板

默认模板为 `modern`：

```bash
./scan.sh https://example.com --template traditional-html
./scan.sh https://example.com --template traditional-html-plus
./scan.sh https://example.com --template high-level-report
./scan.sh https://example.com --template risk-confidence-html
```

模板必须已经包含在当前 ZAP 镜像的 Reports add-on 中。模板名无效时，ZAP 会在运行计划时列出错误。

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

