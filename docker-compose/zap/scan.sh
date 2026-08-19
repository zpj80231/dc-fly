#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

usage() {
    cat <<EOF
用法：
  $0 <目标URL> [baseline|full] [选项]

选项：
  --config <文件>     指定 Automation Framework 模板
  --template <名称>   报告模板，默认：traditional-html
  --lang <locale>     报告语言，默认：zh_CN
  -h, --help          显示帮助

示例：
  $0 https://example.com
  $0 https://example.com full
  $0 https://example.com baseline --template modern
  $0 https://example.com --config ./my-zap.yaml --lang zh_CN
EOF
}

fail() {
    echo "错误：$*" >&2
    exit 1
}

yaml_quote() {
    escaped_value="$(printf '%s' "$1" | sed "s/'/''/g")"
    printf "'%s'" "${escaped_value}"
}

sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

resolve_config() {
    config_path="$1"
    case "${config_path}" in
        /*)
            ;;
        *)
            if [ -f "${config_path}" ]; then
                config_path="$(CDPATH= cd -- "$(dirname -- "${config_path}")" && pwd)/$(basename -- "${config_path}")"
            else
                config_path="${SCRIPT_DIR}/${config_path}"
            fi
            ;;
    esac
    printf '%s' "${config_path}"
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

TARGET_URL="$1"
shift

SCAN_TYPE="baseline"
if [ "$#" -gt 0 ]; then
    case "$1" in
        baseline|full)
            SCAN_TYPE="$1"
            shift
            ;;
    esac
fi

REPORT_TEMPLATE="${ZAP_REPORT_TEMPLATE:-traditional-html}"
REPORT_LANG="${ZAP_REPORT_LANG:-zh_CN}"
CONFIG_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            [ "$#" -ge 2 ] || fail "--config 缺少文件参数"
            CONFIG_FILE="$2"
            shift 2
            ;;
        --template)
            [ "$#" -ge 2 ] || fail "--template 缺少模板名称"
            REPORT_TEMPLATE="$2"
            shift 2
            ;;
        --lang)
            [ "$#" -ge 2 ] || fail "--lang 缺少 locale"
            REPORT_LANG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知参数：$1"
            ;;
    esac
done

case "${TARGET_URL}" in
    http://*|https://*)
        ;;
    *)
        fail "目标 URL 必须以 http:// 或 https:// 开头"
        ;;
esac

case "${REPORT_TEMPLATE}" in
    *[!A-Za-z0-9._-]*|'')
        fail "报告模板名称只能包含字母、数字、点、下划线和连字符"
        ;;
esac

case "${REPORT_LANG}" in
    *[!A-Za-z0-9_-]*|'')
        fail "locale 只能包含字母、数字、下划线和连字符"
        ;;
esac

if [ -z "${CONFIG_FILE}" ]; then
    case "${SCAN_TYPE}" in
        baseline)
            CONFIG_FILE="zap.yaml"
            ;;
        full)
            CONFIG_FILE="zap-full.yaml"
            ;;
    esac
fi

CONFIG_FILE="$(resolve_config "${CONFIG_FILE}")"
[ -f "${CONFIG_FILE}" ] || fail "配置文件不存在：${CONFIG_FILE}"

for placeholder in __TARGET_URL__ __REPORT_DIR__ __REPORT_TEMPLATE__; do
    grep -F "${placeholder}" "${CONFIG_FILE}" >/dev/null || \
        fail "配置文件缺少占位符：${placeholder}"
done

TARGET_HOST="$(printf '%s' "${TARGET_URL}" | sed -E 's#https?://##; s#/.*##; s/[^A-Za-z0-9._-]/_/g')"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_NAME="${TARGET_HOST}-${SCAN_TYPE}-${TIMESTAMP}"
REPORT_DIR="${SCRIPT_DIR}/reports/${REPORT_NAME}"
RUNTIME_DIR="${SCRIPT_DIR}/.zap-runtime/${REPORT_NAME}"
RUNTIME_PLAN="${RUNTIME_DIR}/zap.yaml"
RUNTIME_PLAN_CONTAINER="/zap/wrk/.zap-runtime/${REPORT_NAME}/zap.yaml"
REPORT_DIR_CONTAINER="/zap/wrk/reports/${REPORT_NAME}"

mkdir -p "${REPORT_DIR}" "${RUNTIME_DIR}"
chmod 0777 "${REPORT_DIR}" "${RUNTIME_DIR}"

cleanup() {
    rm -rf "${RUNTIME_DIR}"
}
trap cleanup EXIT HUP INT TERM

target_yaml="$(sed_replacement "$(yaml_quote "${TARGET_URL}")")"
report_dir_yaml="$(sed_replacement "$(yaml_quote "${REPORT_DIR_CONTAINER}")")"
template_yaml="$(sed_replacement "$(yaml_quote "${REPORT_TEMPLATE}")")"

sed \
    -e "s|__TARGET_URL__|${target_yaml}|g" \
    -e "s|__REPORT_DIR__|${report_dir_yaml}|g" \
    -e "s|__REPORT_TEMPLATE__|${template_yaml}|g" \
    "${CONFIG_FILE}" > "${RUNTIME_PLAN}"

echo "=========================================="
echo "          ZAP Web 漏洞扫描"
echo "=========================================="
echo "扫描目标：${TARGET_URL}"
echo "扫描模式：${SCAN_TYPE}"
echo "配置模板：${CONFIG_FILE}"
echo "报告模板：${REPORT_TEMPLATE}"
echo "报告语言：${REPORT_LANG}"
echo "报告目录：${REPORT_DIR}"
echo "=========================================="
echo ""

set +e
docker compose --project-directory "${SCRIPT_DIR}" run --rm \
    zap \
    zap.sh \
    -cmd \
    -autorun "${RUNTIME_PLAN_CONTAINER}" \
    -config "view.locale=${REPORT_LANG}"
SCAN_STATUS="$?"
set -e

if [ "${SCAN_STATUS}" -ne 0 ]; then
    fail "ZAP 扫描失败，退出码：${SCAN_STATUS}"
fi

echo ""
echo "=========================================="
echo "          扫描完成"
echo "=========================================="
echo "HTML：${REPORT_DIR}/report.html"
echo "=========================================="
