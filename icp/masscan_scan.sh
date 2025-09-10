#!/bin/bash
set -euo pipefail

##############################################################################
# 配置参数（新增dir.sh路径）
##############################################################################
ICP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
WEB_SCAN_OUTPUT="${ICP_DIR}/WebScan/output.txt"
EXTRACTED_URLS="${ICP_DIR}/extracted_urls.txt"
SCAN_TARGETS="${ICP_DIR}/masscan_targets.txt"
MASSCAN_RESULTS="${ICP_DIR}/masscan_results.txt"
PORT_RANGE="80,443,8080,8443,22,3389"
SCAN_RATE="1000"
# 新增：dir.sh的绝对路径（与masscan_scan.sh同目录）
DIR_SCRIPT="${ICP_DIR}/dir.sh"  # 关键：定义dir.sh路径

##############################################################################
# 修正正则表达式（保持不变）
##############################################################################
URL_REGEX='^(https?:\/\/)?([^\/:]+)'
IP_REGEX='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

##############################################################################
# 新增：前置依赖检查（补充masscan和nslookup检查，保持不变）
##############################################################################
check_dependencies() {
    echo -e "=== 前置检查：确保所有依赖就绪 ==="

    # 1. 检查masscan是否安装
    if ! command -v masscan &>/dev/null; then
        echo "❌ 未安装 masscan 工具，请先安装："
        echo "   Ubuntu/Debian: sudo apt install masscan"
        echo "   CentOS: sudo yum install masscan 或源码编译"
        exit 1
    fi

    # 2. 检查nslookup是否存在
    if ! command -v nslookup &>/dev/null; then
        echo "❌ 未找到 nslookup 工具，请安装："
        echo "   Ubuntu/Debian: sudo apt install dnsutils"
        echo "   CentOS: sudo yum install bind-utils"
        exit 1
    fi

    # 3. 检查输入文件（WebScan/output.txt）
    if [ ! -f "${WEB_SCAN_OUTPUT}" ]; then
        echo "❌ 输入文件不存在：${WEB_SCAN_OUTPUT}"
        echo "   请确保 tanhuo.sh 已成功生成该文件（WebScan扫描结果）"
        exit 1
    fi
    if [ $(wc -l < "${WEB_SCAN_OUTPUT}") -eq 0 ]; then
        echo "❌ 输入文件为空：${WEB_SCAN_OUTPUT}"
        echo "   WebScan扫描未发现存活目标，无法继续"
        exit 1
    fi

    echo -e "✅ 所有依赖检查通过\n"
}

##############################################################################
# 步骤1：提取有效URL（保持不变）
##############################################################################
extract_urls() {
    echo -e "=== 步骤1/3：提取有效URL ==="
    if [ ! -f "${WEB_SCAN_OUTPUT}" ]; then
        echo "❌ 未找到WebScan结果文件：${WEB_SCAN_OUTPUT}"
        exit 1
    fi

    awk '{print $2}' "${WEB_SCAN_OUTPUT}" | sort -u > "${EXTRACTED_URLS}"
    local url_count=$(wc -l < "${EXTRACTED_URLS}")

    if [ "${url_count}" -eq 0 ]; then
        echo "❌ 未从${WEB_SCAN_OUTPUT}中提取到有效URL"
        exit 1
    fi

    echo -e "✅ 提取完成："
    echo -e "   - 提取URL数量：${url_count} 个（去重后）"
    echo -e "   - 保存路径：${EXTRACTED_URLS}"
    echo -e "   预览前5个URL："
    head -5 "${EXTRACTED_URLS}"
    echo ""
}

##############################################################################
# 步骤2：解析URL为IP（保持不变）
##############################################################################
resolve_urls_to_ips() {
    echo -e "=== 步骤2/3：解析URL为IP ==="
    > "${SCAN_TARGETS}"

    local url_count=$(wc -l < "${EXTRACTED_URLS}")
    local resolved_count=0

    set +e
    while IFS= read -r url; do
        [ -z "${url}" ] && continue

        if [[ "${url}" =~ ${URL_REGEX} ]]; then
            local target=${BASH_REMATCH[2]}
            echo "   🔍 提取域名：${target}（来自URL：${url}）"

            if [[ "${target}" =~ ${IP_REGEX} ]]; then
                echo "${target}" >> "${SCAN_TARGETS}" || true
                ((resolved_count++))
                echo "   ✅ 目标是IP，直接添加：${target}"
            else
                local ip=$(nslookup -timeout=5 "${target}" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || true)
                if [ -n "${ip}" ]; then
                    echo "${ip}" >> "${SCAN_TARGETS}" || true
                    ((resolved_count++))
                    echo "   ✅ 域名解析成功：${target} → ${ip}"
                else
                    echo "   ⚠️ 域名解析失败：${target}（跳过）"
                fi
            fi
        else
            echo "   ⚠️ URL格式无效：${url}（跳过）"
        fi
    done < "${EXTRACTED_URLS}"
    set -euo pipefail

    sort -u "${SCAN_TARGETS}" -o "${SCAN_TARGETS}"
    local final_ip_count=$(wc -l < "${SCAN_TARGETS}")

    echo -e "\n✅ IP解析完成："
    echo -e "   - 总URL数：${url_count} 个"
    echo -e "   - 成功解析IP数：${resolved_count} 个（去重后 ${final_ip_count} 个）"
    echo -e "   - 目标IP文件：${SCAN_TARGETS}"
    echo ""
}

##############################################################################
# 步骤3：调用masscan扫描IP（保持不变）
##############################################################################
run_masscan() {
    echo -e "=== 步骤3/3：执行masscan端口扫描 ==="
    local final_ip_count=$(wc -l < "${SCAN_TARGETS}")

    if [ "${final_ip_count}" -eq 0 ]; then
        echo "❌ 无有效IP可扫描，终止流程"
        exit 1
    fi

    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ masscan需要root权限，请用 sudo 运行"
        exit 1
    fi

    echo -e "📌 扫描配置："
    echo -e "   - 目标IP：${final_ip_count} 个"
    echo -e "   - 端口范围：${PORT_RANGE}"
    echo -e "   - 速率：${SCAN_RATE} 包/秒"
    echo -e "   - 结果保存：${MASSCAN_RESULTS}"
    echo -e "   开始时间：$(date '+%Y-%m-%d %H:%M:%S')\n"

    masscan -iL "${SCAN_TARGETS}" \
            -p "${PORT_RANGE}" \
            --rate "${SCAN_RATE}" \
            -oG "${MASSCAN_RESULTS}"

    if [ $? -eq 0 ]; then
        local open_count=$(grep -c "open" "${MASSCAN_RESULTS}" 2>/dev/null)
        echo -e "✅ masscan扫描完成！"
        echo -e "   - 开放端口数量：${open_count} 个"
        echo -e "   - 结果文件：${MASSCAN_RESULTS}"
    else
        echo -e "❌ masscan扫描失败"
    fi
}

##############################################################################
# 新增：执行dir.sh（masscan完成后调用）
##############################################################################
run_dir_script() {
    echo -e "\n=================================================="
    echo -e "🔗 开始执行 dir.sh（基于masscan结果的目录扫描）"
    echo -e "=================================================="

    # 检查dir.sh是否存在
    if [ ! -f "${DIR_SCRIPT}" ]; then
        echo "❌ 未找到 dir.sh，路径：${DIR_SCRIPT}"
        echo "   跳过执行 dir.sh"
        return 1
    fi

    # 检查dir.sh是否有执行权限，无则添加
    if [ ! -x "${DIR_SCRIPT}" ]; then
        echo "📌 为 dir.sh 添加执行权限..."
        chmod +x "${DIR_SCRIPT}" || {
            echo "❌ 无法为 dir.sh 添加执行权限"
            echo "   跳过执行 dir.sh"
            return 1
        }
    fi

    # 执行dir.sh
    echo "📌 开始执行 dir.sh..."
    "${DIR_SCRIPT}"  # 调用dir.sh
    local exit_code=$?

    # 输出执行结果
    if [ "${exit_code}" -eq 0 ]; then
        echo -e "✅ dir.sh 执行完成"
    else
        echo -e "⚠️ dir.sh 执行失败（退出码：${exit_code}）"
    fi
}

##############################################################################
# 主流程（新增调用dir.sh步骤）
##############################################################################
main() {
    echo "=================================================="
    echo "    自动URL提取 + masscan端口扫描工具"
    echo "    基于WebScan的output.txt结果"
    echo -e "    执行时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "==================================================\n"

    check_dependencies
    extract_urls
    resolve_urls_to_ips
    run_masscan
    run_dir_script  # 新增：masscan完成后自动执行dir.sh

    echo -e "\n=================================================="
    echo -e "🎉 全流程结束！最终结果："
    echo -e "   - masscan结果：${MASSCAN_RESULTS}"
    echo -e "   - dir.sh扫描结果：${ICP_DIR}/200.txt 和 ${ICP_DIR}/403.txt"
    echo -e "=================================================="
}

main
