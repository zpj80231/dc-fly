#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

ruby -ryaml -e '
  baseline, full = ARGV.map { |path| YAML.load_file(path) }

  [baseline, full].each do |plan|
    jobs = plan.fetch("jobs")
    spider = jobs.find { |job| job["type"] == "spider" }
    ajax_spider = jobs.find { |job| job["type"] == "spiderAjax" }
    report_index = jobs.index { |job| job["type"] == "report" }
    passive_wait_indexes = jobs.each_index.select { |index| jobs[index]["type"] == "passiveScan-wait" }

    abort "traditional spider must run at least ten minutes" unless spider.dig("parameters", "maxDuration").to_i >= 10
    abort "ajax spider is required for modern web applications" unless ajax_spider
    abort "ajax spider must run at least ten minutes" unless ajax_spider.dig("parameters", "maxDuration").to_i >= 10
    abort "ajax spider must stay in scope" unless ajax_spider.dig("parameters", "inScopeOnly") == true
    abort "report must run after passive scan wait" unless passive_wait_indexes.any? { |index| index < report_index }
  end

  full_jobs = full.fetch("jobs")
  active_index = full_jobs.index { |job| job["type"] == "activeScan" }
  report_index = full_jobs.index { |job| job["type"] == "report" }
  abort "full scan must actively scan after spidering" unless active_index && active_index < report_index
' "${SCRIPT_DIR}/zap.yaml" "${SCRIPT_DIR}/zap-full.yaml"

echo "扫描配置检查通过"
