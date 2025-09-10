#!/bin/bash
set -euo pipefail  # 严格模式

##############################################################################
# 基础配置（保留所有原配置，新增清理标识）
##############################################################################
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
WEB_RESULTS_FILE="${SCRIPT_DIR}/web_results.txt"       # 源域名/IP文件
ONEFORALL_PATH="${SCRIPT_DIR}/../OneForAll-master"     # OneForAll目录
ONEFORALL_VENV_ACTIVATE="${ONEFORALL_PATH}/venv/bin/activate"  # 虚拟环境激活脚本
OUTPUT_DIR="${ONEFORALL_PATH}/results"                 # OneForAll结果目录（待清理CSV）
IP_FILE="${SCRIPT_DIR}/ip.txt"                          # 提取的IP文件
URL_OUTPUT_FILE="${SCRIPT_DIR}/ziyu.txt"                # 提取的URL文件
COMBINED_IPS_FILE="${SCRIPT_DIR}/combined_ips.txt"      # IP整合结果（IP+URL转IP）
TARGET_FILE="${SCRIPT_DIR}/target.txt"                  # ip.txt和ziyu.txt合并结果
TANHUO_SCRIPT="${SCRIPT_DIR}/tanhuo.sh"                             # 新增：tanhuo.sh路径

# 正则表达式
IP_REGEX='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
URL_REGEX='^(https?:\/\/)?([^:\/]+)(:.*)?$'

##############################################################################
# 1. 提取IP到ip.txt（保持不变）
##############################################################################
extract_ip_to_file() {
    echo -e "\n=== 步骤1/5：提取IP地址（保存至 ${IP_FILE}） ==="

    local extracted_ip_count=$(
        grep -v -E "【|=|domain列表" "${WEB_RESULTS_FILE}" | 
        sed '/^$/d' | 
        grep -E "${IP_REGEX}" | 
        sort -u | 
        tee "${IP_FILE}" | 
        wc -l
    )

    if [ "${extracted_ip_count}" -gt 0 ]; then
        echo -e "✅ 成功提取 ${extracted_ip_count} 个IP地址"
        echo -e "   预览前3个IP："
        head -3 "${IP_FILE}"
        [ "${extracted_ip_count}" -gt 3 ] && echo "   ...（省略 ${extracted_ip_count}-3 个IP）"
    else
        rm -f "${IP_FILE}"
        echo -e "⚠️ 未从源文件中提取到IP地址"
    fi
    echo ""
}

##############################################################################
# 2. 前置检查（保持不变）
##############################################################################
check_prerequisites() {
    echo -e "=== 初始化：前置检查 ==="

    if [ ! -f "${WEB_RESULTS_FILE}" ]; then
        echo "❌ 未找到源文件：${WEB_RESULTS_FILE}"
        exit 1
    fi

    if [ ! -d "${ONEFORALL_PATH}" ] || [ ! -f "${ONEFORALL_VENV_ACTIVATE}" ]; then
        echo "❌ OneForAll目录或虚拟环境不存在，请确认路径正确"
        exit 1
    fi

    if ! command -v nslookup &>/dev/null; then
        echo "❌ 未找到nslookup工具，请先安装：yum install -y bind-utils"
        exit 1
    fi

    local valid_domain_count=$(
        grep -v -E "【|=|domain列表" "${WEB_RESULTS_FILE}" | 
        sed '/^$/d' | 
        grep -vE "${IP_REGEX}" | 
        sort -u | 
        wc -l
    )
    local total_ip_count=$(
        grep -v -E "【|=|domain列表" "${WEB_RESULTS_FILE}" | 
        sed '/^$/d' | 
        grep -E "${IP_REGEX}" | 
        wc -l
    )

    if [ "${valid_domain_count}" -eq 0 ]; then
        echo "❌ 源文件中无有效域名"
        exit 1
    fi

    echo -e "✅ 前置检查通过："
    echo -e "   - 源文件：${WEB_RESULTS_FILE}（共 $(wc -l < "${WEB_RESULTS_FILE}") 行）"
    echo -e "   - 待处理域名：${valid_domain_count} 个 | 可提取IP：${total_ip_count} 个"
    echo -e "   - 工具就绪：nslookup"
    echo ""
}

##############################################################################
# 3. OneForAll子域名收集（保持不变）
##############################################################################
collect_subdomains() {
    echo -e "=== 步骤2/5：执行OneForAll子域名收集（用于提取URL） ==="
    echo -e "   结果保存：${OUTPUT_DIR}\n"

    cd "${ONEFORALL_PATH}" || { echo "❌ 无法进入OneForAll目录"; exit 1; }

    echo -e "📌 激活虚拟环境..."
    source "${ONEFORALL_VENV_ACTIVATE}"
    echo -e "✅ 虚拟环境激活成功（Python：$(python3 --version | awk '{print $2}')）\n"

    grep -v -E "【|=|domain列表" "${WEB_RESULTS_FILE}" | \
    sed '/^$/d' | \
    grep -vE "${IP_REGEX}" | \
    sort -u | \
    while IFS= read -r DOMAIN; do
        [ -z "${DOMAIN}" ] && continue

        echo -e "=================================================="
        echo -e "处理域名：${DOMAIN} | 时间：$(date '+%Y-%m-%d %H:%M:%S')"
        oneforall_cmd="python3 oneforall.py --target '${DOMAIN}' --fmt csv run"
        echo -e "执行命令：${oneforall_cmd}"
        echo -e "=================================================="

        if eval "${oneforall_cmd}"; then
            echo -e "✅ ${DOMAIN} 收集完成 → ${OUTPUT_DIR}/${DOMAIN}.csv\n"
        else
            echo -e "⚠️ ${DOMAIN} 收集失败 → 建议后续排查\n"
        fi
    done

    deactivate
    echo -e "📌 虚拟环境已退出\n"
}

##############################################################################
# 4. 从CSV提取URL到ziyu.txt（保持不变，依赖CSV文件）
##############################################################################
extract_url_from_csv() {
    echo -e "=== 步骤3/5：从CSV提取URL（保存至 ${URL_OUTPUT_FILE}） ==="

    if [ ! -d "${OUTPUT_DIR}" ] || [ $(ls -1 "${OUTPUT_DIR}"/*.csv 2>/dev/null | wc -l) -eq 0 ]; then
        echo "⚠️ 未找到OneForAll CSV结果文件 → 生成空URL文件"
        > "${URL_OUTPUT_FILE}"
        echo "✅ 空 ${URL_OUTPUT_FILE} 已生成"
        echo ""
        return 1
    fi

    local all_urls=""
    for csv_file in "${OUTPUT_DIR}"/*.csv; do
        [ ! -f "${csv_file}" ] && continue
        local urls=$(awk -F ',' 'NR>1 {print $5}' "${csv_file}")
        all_urls="${all_urls}\n${urls}"
    done

    local unique_url_count=$(
        echo -e "${all_urls}" | 
        sed '/^$/d' | 
        sort -u | 
        tee "${URL_OUTPUT_FILE}" | 
        wc -l
    )

    echo -e "✅ URL提取完成："
    echo -e "   - 唯一URL数量：${unique_url_count} 个"
    echo -e "   - 保存路径：${URL_OUTPUT_FILE}"
    echo -e "   预览前5个URL："
    head -5 "${URL_OUTPUT_FILE}"
    [ "${unique_url_count}" -gt 5 ] && echo "   ...（省略 ${unique_url_count}-5 个）"
    echo ""
}

##############################################################################
# 5. 合并IP（ip.txt + ziyu.txt转IP）→ combined_ips.txt（保持不变）
##############################################################################
merge_ips() {
    echo -e "=== 步骤4/5：合并IP（ip.txt + ziyu.txt转IP）并去重 ==="

    > "${COMBINED_IPS_FILE}"

    local ip_count=0
    if [ -f "${IP_FILE}" ] && [ $(wc -l < "${IP_FILE}") -gt 0 ]; then
        ip_count=$(wc -l < "${IP_FILE}")
        cat "${IP_FILE}" >> "${COMBINED_IPS_FILE}"
        echo -e "📌 从 ${IP_FILE} 读取 ${ip_count} 个IP"
    else
        echo -e "📌 ${IP_FILE} 为空或不存在，跳过"
    fi

    local url_count=0
    local url_ip_count=0
    if [ -f "${URL_OUTPUT_FILE}" ] && [ $(wc -l < "${URL_OUTPUT_FILE}") -gt 0 ]; then
        url_count=$(wc -l < "${URL_OUTPUT_FILE}")
        echo -e "📌 开始处理 ${URL_OUTPUT_FILE} 中的 ${url_count} 个URL（提取/解析IP）..."

        # 关键修改：暂时关闭严格模式，避免单条URL处理失败导致脚本中断
        set +e
        while IFS= read -r url; do
            [ -z "${url}" ] && continue

            # 为每个步骤添加错误捕获，确保单条URL处理失败不影响循环
            if [[ "${url}" =~ ${URL_REGEX} ]]; then
                local target=${BASH_REMATCH[2]}

                if [[ "${target}" =~ ${IP_REGEX} ]]; then
                    # 写入IP时忽略错误
                    echo "${target}" >> "${COMBINED_IPS_FILE}" || true
                    ((url_ip_count++))
                    echo "   ✅ URL(${url}) → 直接提取IP：${target}"
                else
                    # 解析域名时忽略错误，即使nslookup失败也继续
                    local resolved_ip=$(nslookup "${target}" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
                    if [ -n "${resolved_ip}" ]; then
                        echo "${resolved_ip}" >> "${COMBINED_IPS_FILE}" || true
                        ((url_ip_count++))
                        echo "   ✅ URL(${url}) → 解析域名(${target}) → IP：${resolved_ip}"
                    else
                        echo "   ⚠️ URL(${url}) → 域名(${target})解析失败，跳过"
                    fi
                fi
            else
                echo "   ⚠️ URL(${url}) 格式无效，跳过"
            fi
        done < "${URL_OUTPUT_FILE}"
        # 恢复严格模式
        set -euo pipefail

        echo -e "📌 URL处理完成：共 ${url_count} 个URL，成功提取/解析 ${url_ip_count} 个IP"
    else
        echo -e "📌 ${URL_OUTPUT_FILE} 为空或不存在，跳过URL处理"
    fi

    local final_ip_count=$(
        sort -u "${COMBINED_IPS_FILE}" | 
        tee "${COMBINED_IPS_FILE}.tmp" | 
        wc -l
    )
    mv -f "${COMBINED_IPS_FILE}.tmp" "${COMBINED_IPS_FILE}"

    echo -e "\n✅ IP整合去重完成："
    echo -e "   - 合并来源：ip.txt（${ip_count}个） + ziyu.txt（${url_ip_count}个）"
    echo -e "   - 去重后总IP数：${final_ip_count} 个"
    echo -e "   - 结果保存至：${COMBINED_IPS_FILE}"
    echo -e "   预览前5个整合IP："
    head -5 "${COMBINED_IPS_FILE}"
    [ "${final_ip_count}" -gt 5 ] && echo "   ...（省略 ${final_ip_count}-5 个IP）"
    echo ""
}

##############################################################################
# 6. 合并ip.txt和ziyu.txt → target.txt（保持不变）
##############################################################################
merge_ip_url_to_target() {
    echo -e "=== 步骤5/5：合并ip.txt和ziyu.txt（直接去重） ==="

    # 合并两个文件内容（忽略不存在的文件），去重后保存到target.txt
    cat "${IP_FILE}" 2>/dev/null > "${TARGET_FILE}"  # 先写入ip.txt内容（若存在）
    cat "${URL_OUTPUT_FILE}" 2>/dev/null >> "${TARGET_FILE}"  # 追加ziyu.txt内容（若存在）
    sort -u "${TARGET_FILE}" -o "${TARGET_FILE}"  # 去重并覆盖原文件

    # 统计合并后的总条数
    local total_count=$(wc -l < "${TARGET_FILE}" 2>/dev/null)

    echo -e "✅ ip.txt和ziyu.txt合并去重完成："
    echo -e "   - 合并来源：ip.txt（$( [ -f "${IP_FILE}" ] && wc -l < "${IP_FILE}" || echo 0 ) 行） + ziyu.txt（$( [ -f "${URL_OUTPUT_FILE}" ] && wc -l < "${URL_OUTPUT_FILE}" || echo 0 ) 行）"
    echo -e "   - 去重后总条数：${total_count} 行（包含IP和URL）"
    echo -e "   - 结果保存至：${TARGET_FILE}"
    echo -e "   预览前5行内容："
    head -5 "${TARGET_FILE}" 2>/dev/null || echo "   无内容"
    [ "${total_count}" -gt 5 ] && echo "   ...（省略 ${total_count}-5 行）"
    echo ""
}

##############################################################################
# 7. 新增：删除OneForAll结果目录中的所有CSV文件（核心清理功能）
##############################################################################
clean_oneforall_csv() {
    echo -e "=== 额外步骤：清理OneForAll结果目录中的CSV文件 ==="

    # 检查结果目录是否存在
    if [ ! -d "${OUTPUT_DIR}" ]; then
        echo -e "⚠️ OneForAll结果目录 ${OUTPUT_DIR} 不存在，无需清理"
        echo ""
        return 0
    fi

    # 统计待删除的CSV文件数量
    local csv_count=$(ls -1 "${OUTPUT_DIR}"/*.csv 2>/dev/null | wc -l)
    if [ "${csv_count}" -eq 0 ]; then
        echo -e "⚠️ OneForAll结果目录中无CSV文件，无需清理"
        echo ""
        return 0
    fi

    # 执行删除（-f避免文件不存在报错，-v显示删除过程）
    echo -e "📌 开始删除 ${csv_count} 个CSV文件："
    rm -fv "${OUTPUT_DIR}"/*.csv

    echo -e "\n✅ 清理完成：共删除 ${csv_count} 个CSV文件（路径：${OUTPUT_DIR}）"
    echo ""
}

##############################################################################
# 8. 最终结果提示（新增清理状态）
##############################################################################
final_prompt() {
    echo -e "=================================================="
    echo -e "🎉 全流程执行结束！"
    echo -e "=================================================="
    echo -e "📊 结果汇总："
    # IP提取结果
    if [ -f "${IP_FILE}" ] && [ $(wc -l < "${IP_FILE}") -gt 0 ]; then
        echo -e "   1. IP提取：✅ ${IP_FILE}（$(wc -l < "${IP_FILE}") 个唯一IP）"
    else
        echo -e "   1. IP提取：⚠️ 未提取到有效IP"
    fi
    # URL提取结果
    if [ $(wc -l < "${URL_OUTPUT_FILE}") -gt 0 ]; then
        echo -e "   2. URL提取：✅ ${URL_OUTPUT_FILE}（$(wc -l < "${URL_OUTPUT_FILE}") 个唯一URL）"
    else
        echo -e "   2. URL提取：⚠️ 未提取到有效URL"
    fi
    # IP整合结果
    echo -e "   3. IP整合（IP+URL转IP）：✅ ${COMBINED_IPS_FILE}（$(wc -l < "${COMBINED_IPS_FILE}") 个唯一IP）"
    # IP+URL合并结果
    echo -e "   4. IP+URL直接合并：✅ ${TARGET_FILE}（$(wc -l < "${TARGET_FILE}") 行内容，含IP和URL）"
    # 清理结果
    echo -e "   5. CSV清理：✅ OneForAll结果目录（${OUTPUT_DIR}）中的CSV文件已删除"
    echo -e "=================================================="
}

##############################################################################
# 9. 新增：执行tanhuo.sh
##############################################################################
run_tanhuo_script() {
    echo -e "\n=== 开始执行当前目录的tanhuo.sh ==="
    
    # 检查tanhuo.sh是否存在
    if [ ! -f "${TANHUO_SCRIPT}" ]; then
        echo "❌ 未找到 ${TANHUO_SCRIPT}，无法执行"
        return 1
    fi

    # 检查是否有执行权限，没有则尝试添加
    if [ ! -x "${TANHUO_SCRIPT}" ]; then
        echo "⚠️ ${TANHUO_SCRIPT} 缺少执行权限，尝试添加..."
        if ! chmod +x "${TANHUO_SCRIPT}"; then
            echo "❌ 无法为 ${TANHUO_SCRIPT} 添加执行权限，执行失败"
            return 1
        fi
    fi

    # 执行tanhuo.sh
    echo "✅ 开始执行 ${TANHUO_SCRIPT}..."
    "${TANHUO_SCRIPT}"
    local exit_code=$?
    if [ ${exit_code} -eq 0 ]; then
        echo "✅ ${TANHUO_SCRIPT} 执行完成"
    else
        echo "❌ ${TANHUO_SCRIPT} 执行失败，退出码：${exit_code}"
    fi
}

##############################################################################
# 主流程（调整顺序：先完成所有依赖CSV的步骤，最后清理CSV，再执行tanhuo.sh）
##############################################################################
main() {
    echo "=================================================="
    echo "    全流程：OneForAll + IP/URL提取 + 双重合并 + CSV清理 + 执行tanhuo.sh"
    echo "    核心特性："
    echo "    1. 合并IP（ip.txt + URL转IP）→ combined_ips.txt"
    echo "    2. 直接合并ip.txt和ziyu.txt → target.txt"
    echo "    3. 流程结束后自动删除OneForAll的CSV临时文件"
    echo "    4. 最终自动执行当前目录的tanhuo.sh"
    echo "    适配目录：${SCRIPT_DIR}（icp目录）"
    echo -e "    执行时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "==================================================\n"

    # 执行顺序：前置检查→提IP→子域名收集→提URL→IP整合→IP+URL合并→清理CSV→最终提示→执行tanhuo.sh
    check_prerequisites    # 1. 前置检查
    extract_ip_to_file     # 2. 提取IP到ip.txt
    collect_subdomains     # 3. 子域名收集（生成CSV）
    extract_url_from_csv   # 4. 从CSV提取URL（依赖CSV，必须在清理前）
    merge_ips              # 5. IP整合（不依赖CSV）
    merge_ip_url_to_target # 6. IP+URL合并（不依赖CSV）
    clean_oneforall_csv    # 7. 清理CSV（所有依赖步骤完成后执行）
    final_prompt           # 8. 最终结果提示
    run_tanhuo_script      # 9. 新增：执行tanhuo.sh
}

main
