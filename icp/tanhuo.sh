#!/bin/bash
set -euo pipefail  # 严格模式，确保错误及时暴露

##############################################################################
# 基础路径配置（根据实际目录固定，避免路径错误）
##############################################################################
# 脚本所在目录（icp目录）- 定义的是ICP_DIR，后续统一用这个变量
ICP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# WebScan目录（icp下的WebScan子目录）
WEB_SCAN_DIR="${ICP_DIR}/WebScan"
# WebScan虚拟环境激活脚本路径
VENV_ACTIVATE="${WEB_SCAN_DIR}/venv/bin/activate"
# 目标文件：icp目录下的target.txt（绝对路径，避免找不到）
TARGET_FILE="${ICP_DIR}/target.txt"
# WebScan主脚本路径
WEB_SCAN_SCRIPT="${WEB_SCAN_DIR}/Web-SurvivalScan.py"
MASSCAN_SCRIPT="${ICP_DIR}/masscan_scan.sh"

# 新增：如果run_tanhuo_script要调用其他脚本，需定义其绝对路径（若不需要可删除）
# （当前你的逻辑可能是误加，若只是执行WebScan，此变量可删除，下面会说明）
# TANHUO_SCRIPT="${ICP_DIR}/其他脚本.sh"  # 示例，根据实际需求调整

##############################################################################
# 前置检查：确保所有依赖存在
##############################################################################
check_prerequisites() {
    echo "=================================================="
    echo "    执行 Web-SurvivalScan.py 全自动工具"
    echo "    核心功能：自动用target.txt + 自动跳过交互"
    echo "    目标文件：${TARGET_FILE}"
    echo "    执行时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "==================================================\n"

    echo "=== 前置检查：确保依赖就绪 ==="
    # 1. 检查WebScan目录是否存在
    if [ ! -d "${WEB_SCAN_DIR}" ]; then
        echo "❌ WebScan目录不存在：${WEB_SCAN_DIR}"
        exit 1
    fi

    # 2. 检查虚拟环境是否存在
    if [ ! -f "${VENV_ACTIVATE}" ]; then
        echo "❌ WebScan虚拟环境不存在：${VENV_ACTIVATE}"
        echo "   请先在WebScan目录创建虚拟环境：python3 -m venv venv"
        exit 1
    fi

    # 3. 检查WebScan主脚本是否存在
    if [ ! -f "${WEB_SCAN_SCRIPT}" ]; then
        echo "❌ WebScan主脚本不存在：${WEB_SCAN_SCRIPT}"
        exit 1
    fi

    # 4. 检查目标文件target.txt是否存在（关键：避免找不到文件报错）
    if [ ! -f "${TARGET_FILE}" ]; then
        echo "❌ 目标文件target.txt不存在：${TARGET_FILE}"
        echo "   请先执行oneforall.sh生成target.txt"
        exit 1
    fi

    # 5. 检查target.txt是否有内容（避免空文件）
    if [ $(wc -l < "${TARGET_FILE}") -eq 0 ]; then
        echo "⚠️ 目标文件target.txt为空，可能影响扫描结果"
        read -p "是否继续执行？(y/n) " -n 1 -r
        echo -e "\n"
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    echo -e "✅ 所有前置检查通过！\n"
}

##############################################################################
# 核心执行：激活虚拟环境+自动传入参数（无需手动输入）
##############################################################################
run_webscan() {
    echo "=== 开始执行 Web-SurvivalScan.py ==="
    echo "📌 进入WebScan目录：${WEB_SCAN_DIR}"
    cd "${WEB_SCAN_DIR}" || { echo "❌ 无法进入WebScan目录"; exit 1; }

    echo "📌 激活WebScan虚拟环境..."
    # 激活虚拟环境（必须用source，确保环境生效）
    source "${VENV_ACTIVATE}"
    # 验证虚拟环境是否激活成功（检查Python路径）
    local python_path=$(which python3)
    if [[ ! "${python_path}" =~ "${WEB_SCAN_DIR}/venv/bin/python3" ]]; then
        echo "❌ 虚拟环境激活失败，当前Python路径：${python_path}"
        exit 1
    fi
    echo -e "✅ 虚拟环境激活成功（Python路径：${python_path}）\n"

    echo "📌 自动传入参数并运行脚本..."
    echo "   - 目标文件：${TARGET_FILE}（绝对路径，确保能找到）"
    echo "   - 访问路径：自动跳过（回车）"
    echo "   - 代理配置：自动跳过（回车）"
    echo -e "----------------------------------------\n"

    # 关键：用echo -e 自动传入3个参数（目标文件+2个回车），避免手动输入
    echo -e "${TARGET_FILE}\n\n" | python3 "${WEB_SCAN_SCRIPT}"

    # 退出虚拟环境
    deactivate
    echo -e "\n📌 虚拟环境已退出"
}
##############################################################################
# 新增：执行masscan_scan.sh
##############################################################################
run_masscan_script() {
    echo -e "\n=================================================="
    echo -e "🔗 开始执行 masscan_scan.sh"
    echo -e "=================================================="

    # 检查masscan_scan.sh是否存在
    if [ ! -f "${MASSCAN_SCRIPT}" ]; then
        echo "❌ 未找到 masscan_scan.sh，路径：${MASSCAN_SCRIPT}"
        echo "   跳过执行 masscan_scan.sh"
        return 1  # 不中断流程，仅提示
    fi

    # 检查执行权限，若无则添加
    if [ ! -x "${MASSCAN_SCRIPT}" ]; then
        echo "📌 为 masscan_scan.sh 添加执行权限..."
        chmod +x "${MASSCAN_SCRIPT}" || {
            echo "❌ 无法为 masscan_scan.sh 添加执行权限"
            echo "   跳过执行 masscan_scan.sh"
            return 1
        }
    fi

    # 执行masscan_scan.sh
    echo "📌 开始执行 masscan_scan.sh..."
    "${MASSCAN_SCRIPT}"  # 直接执行脚本
    local exit_code=$?  # 获取退出码

    # 输出执行结果
    if [ "${exit_code}" -eq 0 ]; then
        echo -e "✅ masscan_scan.sh 执行完成"
    else
        echo -e "⚠️ masscan_scan.sh 执行失败（退出码：${exit_code}）"
    fi
}
##############################################################################
# （可选）若需要调用其他脚本，保留此函数；若只是执行WebScan，可删除此函数
# 注意：需先定义TANHUO_SCRIPT变量（在基础配置中），避免未定义错误
##############################################################################
# run_tanhuo_script() {
#     echo -e "\n=================================================="
#     echo -e "🔗 开始调用其他脚本"
#     echo -e "=================================================="

#     # 检查脚本是否存在
#     if [ ! -f "${TANHUO_SCRIPT}" ]; then
#         echo "❌ 未找到目标脚本，路径：${TANHUO_SCRIPT}"
#         echo "   跳过调用"
#         return 1
#     fi

#     # 检查执行权限，若无则添加
#     if [ ! -x "${TANHUO_SCRIPT}" ]; then
#         echo "📌 为目标脚本添加执行权限..."
#         chmod +x "${TANHUO_SCRIPT}" || {
#             echo "❌ 无法添加执行权限"
#             echo "   跳过调用"
#             return 1
#         }
#     fi

#     # 执行脚本
#     echo "📌 开始执行目标脚本..."
#     "${TANHUO_SCRIPT}"
#     local exit_code=$?

#     if [ "${exit_code}" -eq 0 ]; then
#         echo -e "✅ 目标脚本执行完成"
#     else
#         echo -e "⚠️ 目标脚本执行失败（退出码：${exit_code}）"
#     fi
# }

##############################################################################
# 主流程（只保留tanhuo.sh自身的逻辑：前置检查 → 执行WebScan）
##############################################################################
main() {
    echo "=================================================="
    echo "    全自动WebScan扫描流程（tanhuo.sh）"
    echo "    核心功能：基于target.txt自动执行Web-SurvivalScan.py"
    echo "    脚本目录：${ICP_DIR}（icp目录）"
    echo -e "    执行时间：$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "==================================================\n"

    # tanhuo.sh自身流程
    check_prerequisites  # 1. 前置检查
    run_webscan          # 2. 执行WebScan扫描

    # 新增：执行完tanhuo.sh后，自动执行masscan_scan.sh
    run_masscan_script   # 3. 执行masscan_scan.sh

    echo -e "\n=================================================="
    echo -e "🎉 所有流程（tanhuo.sh + masscan_scan.sh）执行结束！"
    echo -e "=================================================="
}
main
