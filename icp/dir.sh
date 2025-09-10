#!/bin/bash
set -euo pipefail

##############################################################################
# 路径配置（新增masscan结果文件路径）
##############################################################################
ICP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# masscan结果文件路径（来自masscan_scan.sh的输出）
MASSCAN_RESULTS="${ICP_DIR}/masscan_results.txt"
# 生成的目录扫描目标文件（由masscan结果解析而来）
TARGET_LIST="${ICP_DIR}/dir.txt"
DIRSEARCH_DIR="${ICP_DIR}/../dirsearch"
DIRSEARCH_SCRIPT="${DIRSEARCH_DIR}/dirsearch.py"
DIRSEARCH_VENV="${DIRSEARCH_DIR}/venv"
RESULTS_DIR="${DIRSEARCH_DIR}/results"
# 筛选结果保存路径（icp目录下）
OUTPUT_200="${ICP_DIR}/200.txt"
OUTPUT_403="${ICP_DIR}/403.txt"

##############################################################################
# 新增步骤0：解析masscan_results.txt生成dir.txt（核心功能）
##############################################################################
process_masscan_results() {
    echo "=== 步骤0/5：解析masscan结果生成扫描目标（dir.txt） ==="

    # 检查masscan结果文件是否存在
    if [ ! -f "${MASSCAN_RESULTS}" ]; then
        echo "❌ masscan结果文件不存在：${MASSCAN_RESULTS}"
        echo "   请先执行masscan_scan.sh生成扫描结果"
        exit 1
    fi

    # 清空旧目标文件（避免追加）
    > "${TARGET_LIST}"

    # 解析masscan结果，提取IP和开放的web端口，生成URL
    # masscan结果行格式示例：
    # Timestamp: 1757319525	Host: 47.52.97.29 ()	Ports: 443/open/tcp//https//
    local ip_port_regex='Host: ([0-9.]+) .*Ports: ([0-9]+)/open/tcp'
    local web_ports=("80" "443" "8080" "8443")  # 只保留web相关端口

    # 遍历masscan结果行，提取有效IP和端口
    grep "Ports: " "${MASSCAN_RESULTS}" | while IFS= read -r line; do
        if [[ "${line}" =~ ${ip_port_regex} ]]; then
            local ip="${BASH_REMATCH[1]}"
            local port="${BASH_REMATCH[2]}"

            # 只处理web相关端口
            if [[ " ${web_ports[@]} " =~ " ${port} " ]]; then
                # 根据端口生成对应的URL（http/https）
                case "${port}" in
                    80|8080)  local url="http://${ip}:${port}" ;;
                    443|8443) local url="https://${ip}:${port}" ;;
                esac
                echo "${url}" >> "${TARGET_LIST}"
                echo "   ✅ 解析生成目标：${url}（IP:${ip}，端口:${port}）"
            else
                echo "   ⚠️ 跳过非web端口：${ip}:${port}（端口不在web端口列表中）"
            fi
        else
            echo "   ⚠️ 无法解析行：${line}"
        fi
    done

    # 去重目标URL（避免重复扫描）
    sort -u "${TARGET_LIST}" -o "${TARGET_LIST}"
    local target_count=$(wc -l < "${TARGET_LIST}")

    if [ "${target_count}" -eq 0 ]; then
        echo "❌ 未从masscan结果中解析到有效web目标（需开放80/443/8080/8443端口）"
        exit 1
    fi

    echo -e "✅ 目标生成完成："
    echo -e "   - 有效web目标数量：${target_count} 个（去重后）"
    echo -e "   - 目标文件路径：${TARGET_LIST}"
    echo -e "   预览前5个目标："
    head -5 "${TARGET_LIST}"
    echo ""
}

##############################################################################
# 步骤1：检查依赖（调整目标文件检查逻辑）
##############################################################################
check_prerequisites() {
    echo "=================================================="
    echo "    遍历扫描 + 结果筛选（200/403响应）"
    echo "    结果保存：${OUTPUT_200} 和 ${OUTPUT_403}"
    echo -e "    执行时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "==================================================\n"

    # 清空旧筛选结果（避免追加）
    > "${OUTPUT_200}"
    > "${OUTPUT_403}"

    # 检查生成的目标文件（由masscan结果解析而来）
    if [ ! -f "${TARGET_LIST}" ] || [ $(wc -l < "${TARGET_LIST}") -eq 0 ]; then
        echo "❌ 目标文件${TARGET_LIST}不存在或为空"
        exit 1
    fi
    local target_count=$(wc -l < "${TARGET_LIST}")

    # 检查dirsearch环境
    if [ ! -d "${DIRSEARCH_DIR}" ] || [ ! -f "${DIRSEARCH_SCRIPT}" ]; then
        echo "❌ dirsearch脚本不存在：${DIRSEARCH_SCRIPT}"
        exit 1
    fi
    if [ ! -d "${DIRSEARCH_VENV}" ] || [ ! -f "${DIRSEARCH_VENV}/bin/activate" ]; then
        echo "❌ 虚拟环境未配置，请先执行："
        echo "   cd ${DIRSEARCH_DIR} && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
        exit 1
    fi

    # 创建结果目录
    mkdir -p "${RESULTS_DIR}" || { echo "❌ 无法创建结果目录${RESULTS_DIR}"; exit 1; }

    echo -e "✅ 依赖检查通过："
    echo -e "   - 目标数量：${target_count} 个"
    echo -e "   - 结果目录：${RESULTS_DIR}\n"
}

##############################################################################
# 步骤2：激活虚拟环境
##############################################################################
activate_venv() {
    echo "=== 步骤2/5：激活dirsearch虚拟环境 ==="
    cd "${DIRSEARCH_DIR}" || { echo "❌ 无法进入dirsearch目录"; exit 1; }

    source "${DIRSEARCH_VENV}/bin/activate"
    local python_path=$(which python3)
    if [[ ! "${python_path}" == *"/dirsearch/venv/bin/python3"* ]]; then
        echo "❌ 虚拟环境激活失败，当前Python路径：${python_path}"
        exit 1
    fi

    echo -e "✅ 虚拟环境激活成功（Python路径：${python_path}）\n"
}

##############################################################################
# 步骤3：遍历目标并执行扫描
##############################################################################
scan_targets() {
    echo "=== 步骤3/5：开始逐个扫描目标 ==="
    local target_count=$(wc -l < "${TARGET_LIST}")
    local current=1

    while IFS= read -r target; do
        [ -z "${target}" ] && continue

        local safe_target="${target//:/-}"  # 替换URL中的特殊字符，避免文件名错误
        local output_file="${RESULTS_DIR}/${safe_target}.txt"

        echo -e "=================================================="
        echo -e "📌 扫描进度：${current}/${target_count}"
        echo -e "📌 目标：${target}"
        echo -e "📌 执行命令：python3 ${DIRSEARCH_SCRIPT} -u ${target} -o ${output_file}"
        echo -e "=================================================="

        if python3 "${DIRSEARCH_SCRIPT}" -u "${target}" -o "${output_file}"; then
            echo -e "✅ 扫描完成，结果保存至：${output_file}\n"
        else
            echo -e "⚠️ 扫描失败（继续处理下一个目标）\n"
        fi

        ((current++))
    done < "${TARGET_LIST}"
}

##############################################################################
# 步骤4：筛选200和403响应结果
##############################################################################
filter_results() {
    echo "=== 步骤4/5：筛选200和403响应结果 ==="
    local result_files=$(find "${RESULTS_DIR}" -type f -name "*.txt" 2>/dev/null)

    if [ -z "${result_files}" ]; then
        echo "⚠️ 未找到任何扫描结果文件，跳过筛选"
        return
    fi

    # 遍历所有结果文件，提取200和403响应
    for file in ${result_files}; do
        # 提取格式："403   350B https://xxx" → 保留完整行
        grep -E '^200[[:space:]]' "${file}" >> "${OUTPUT_200}"
        grep -E '^403[[:space:]]' "${file}" >> "${OUTPUT_403}"
    done

    # 统计筛选结果
    local count_200=$(wc -l < "${OUTPUT_200}")
    local count_403=$(wc -l < "${OUTPUT_403}")

    echo -e "✅ 结果筛选完成："
    echo -e "   - 200响应数量：${count_200} 条（保存至${OUTPUT_200}）"
    echo -e "   - 403响应数量：${count_403} 条（保存至${OUTPUT_403}）"
}

##############################################################################
# 步骤5：退出虚拟环境
##############################################################################
deactivate_venv() {
    deactivate
    echo -e "📌 已退出虚拟环境，当前Python路径：$(which python3)"
}

##############################################################################
# 主流程（新增masscan结果处理步骤）
##############################################################################
main() {
    # 流程顺序：解析masscan结果→检查依赖→激活环境→扫描→筛选→退出环境
    process_masscan_results  # 新增：生成dir.txt目标
    check_prerequisites
    activate_venv
    scan_targets
    filter_results
    deactivate_venv

    # 统计最终结果
    local target_count=$(wc -l < "${TARGET_LIST}")
    local count_200=$(wc -l < "${OUTPUT_200}")
    local count_403=$(wc -l < "${OUTPUT_403}")

    echo -e "\n=================================================="
    echo -e "🎉 全流程结束！"
    echo -e "   扫描目标总数：${target_count} 个"
    echo -e "   200结果：${OUTPUT_200}（${count_200}条）"
    echo -e "   403结果：${OUTPUT_403}（${count_403}条）"
    echo -e "=================================================="
}

main
