import subprocess
import urllib.parse
import os
import time
import json
import random  # 新增：用于生成随机延迟和UA
from datetime import datetime

# 新增：常见浏览器UA头池（可自行扩展，越多越难被识别）
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edge/128.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
]


def get_random_ua():
    """随机获取一个UA头"""
    return random.choice(USER_AGENTS)


def get_target_file_input():
    """获取目标列表文件路径（逻辑不变）"""
    while True:
        file_path = input("请输入目标列表文件路径（每行一个目标）：").strip()
        if not file_path:
            print("文件路径不能为空！请重新输入：")
            continue
        if not os.path.exists(file_path):
            print(f"文件不存在：{file_path}！请重新输入：")
            continue
        if not os.path.isfile(file_path):
            print(f"{file_path} 不是有效文件！请重新输入：")
            continue
        with open(file_path, "r", encoding="utf-8") as f:
            targets = [line.strip() for line in f if line.strip()]
        if not targets:
            print(f"文件 {file_path} 中未找到有效目标！请检查文件内容：")
            continue
        print(f"\n成功读取目标列表（共 {len(targets)} 个有效目标）：")
        for i, target in enumerate(targets, 1):
            print(f"  {i}. {target}")
        return file_path, targets


def build_curl_command(resource_type, search_keyword, base_url="http://127.0.0.1:16181/query"):
    """修改：curl命令添加随机UA头"""
    encoded_keyword = urllib.parse.quote(search_keyword, safe='')
    url = f"{base_url}/{resource_type}?search={encoded_keyword}&pageSize=1000"
    random_ua = get_random_ua()  # 随机选一个UA
    # 新增 -A 参数指定UA头，--connect-timeout 增加连接超时（避免快速失败被识别）
    return f'curl -A "{random_ua}" --connect-timeout 10 --max-time 60 "{url}"'


def log_to_file(message, resource_type, target=""):
    """日志记录（逻辑不变）"""
    log_dir = "request_logs"
    os.makedirs(log_dir, exist_ok=True)
    log_file = f"{log_dir}/{resource_type}_{datetime.now().strftime('%Y%m%d')}.log"
    target_prefix = f"[目标：{target}] " if target else ""
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {target_prefix}{message}\n")


def extract_field(response_content, resource_type, target):
    """数据提取（逻辑不变）"""
    if not response_content.strip():
        log_to_file(f"响应内容为空", resource_type, target)
        return [f"【{target}】{resource_type} 服务器未返回有效数据"]

    try:
        log_to_file(f"原始响应（前500字符）：{response_content[:500]}...", resource_type, target)
        json_data = json.loads(response_content)

        if json_data.get("code") != 200:
            log_to_file(f"响应code非200（实际：{json_data.get('code')}）", resource_type, target)
            return [f"【{target}】{resource_type} 服务器响应失败（code：{json_data.get('code')}）"]
        if "params" not in json_data:
            log_to_file("响应缺少params字段", resource_type, target)
            return [f"【{target}】{resource_type} 响应格式错误（缺少params）"]

        list_data = json_data["params"].get("list", [])
        if not isinstance(list_data, list):
            log_to_file(f"params.list不是数组（实际类型：{type(list_data)}）", resource_type, target)
            return [f"【{target}】{resource_type} 数据格式错误（list不是数组）"]
        log_to_file(f"有效list长度：{len(list_data)}", resource_type, target)

        field_map = {"web": "domain", "app": "serviceName", "mapp": "serviceName"}
        target_field = field_map[resource_type]
        fields = []
        valid_count = 0
        invalid_count = 0

        for idx, item in enumerate(list_data):
            value = item.get(target_field, "").strip()
            if value:
                fields.append(value)
                valid_count += 1
            else:
                invalid_count += 1
        log_to_file(f"提取统计：有效{valid_count}个，无效{invalid_count}个", resource_type, target)

        if not fields:
            log_to_file(f"未提取到任何{target_field}", resource_type, target)
            return [f"【{target}】{resource_type} 未找到有效{target_field}"]
        return fields

    except json.JSONDecodeError as e:
        log_to_file(f"JSON解析失败：{str(e)}，原始响应：{response_content[:200]}", resource_type, target)
        return [f"【{target}】{resource_type} 数据解析失败（JSON格式错误）"]
    except Exception as e:
        log_to_file(f"提取异常：{str(e)}", resource_type, target)
        return [f"【{target}】{resource_type} 提取失败：{str(e)}"]


def run_curl_and_save(resource_type, target, output_file):
    """执行curl请求（逻辑不变，UA已在build_curl_command中添加）"""
    max_retries = 2
    retry_count = 0

    while retry_count <= max_retries:
        try:
            curl_cmd = build_curl_command(resource_type, target)
            log_to_file(f"执行命令：{curl_cmd}", resource_type, target)
            print(f"\n=== 处理目标【{target}】- 资源类型【{resource_type}】（重试：{retry_count}）===")
            print(f"执行命令：{curl_cmd}")

            result = subprocess.run(
                curl_cmd,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60
            )

            if result.returncode != 0:
                log_to_file(f"curl执行失败（状态码：{result.returncode}，错误：{result.stderr}）", resource_type, target)
                retry_count += 1
                if retry_count <= max_retries:
                    # 新增：重试前随机延迟（5-10秒），避免固定重试间隔被识别
                    retry_delay = random.randint(5, 10)
                    print(f"⚠️ 请求失败，{max_retries - retry_count + 1}次重试中（等待{retry_delay}秒）...")
                    time.sleep(retry_delay)
                continue

            response_content = result.stdout
            extracted_values = extract_field(response_content, resource_type, target)
            target_field = "domain" if resource_type == "web" else "serviceName"

            append_content = f"\n{'=' * 50}\n"
            append_content += f"【目标：{target}】{resource_type} 类型 {target_field} 列表（{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}）\n"
            append_content += f"{'=' * 50}\n"
            append_content += "\n".join(extracted_values)
            append_content += "\n"

            with open(output_file, "a+", encoding="utf-8") as f:
                f.write(append_content)

            log_to_file(f"提取完成，共{len(extracted_values)}个{target_field}（已追加到文件）", resource_type, target)
            print(f"✅ 【{target}】-【{resource_type}】结果已追加到：{os.path.abspath(output_file)}")
            print(f"   共提取到 {len(extracted_values)} 个{target_field}")
            return result.returncode

        except subprocess.TimeoutExpired:
            log_to_file(f"curl命令超时（60秒）", resource_type, target)
            retry_count += 1
            if retry_count <= max_retries:
                retry_delay = random.randint(5, 10)
                print(f"⚠️ 请求超时，{max_retries - retry_count + 1}次重试中（等待{retry_delay}秒）...")
                time.sleep(retry_delay)
            continue
        except Exception as e:
            log_to_file(f"请求异常：{str(e)}", resource_type, target)
            retry_count += 1
            if retry_count <= max_retries:
                retry_delay = random.randint(5, 10)
                print(f"⚠️ 请求异常，{max_retries - retry_count + 1}次重试中（等待{retry_delay}秒）...")
                time.sleep(retry_delay)
            continue

    log_to_file(f"超过最大重试次数（{max_retries}次），请求失败", resource_type, target)
    print(f"❌ 【{target}】-【{resource_type}】请求失败（已重试{max_retries}次）")
    return -1


def main():
    resource_config = [("web", "web_results.txt"), ("app", "app_results.txt"), ("mapp", "mapp_results.txt")]
    # 修改：延迟改为“基础值+随机值”（避免固定间隔被识别）
    base_target_delay = 60  # 目标间基础延迟（秒）
    target_delay_range = 50  # 随机波动范围（秒）：总延迟 = 100~150秒
    base_resource_delay = 20  # 资源间基础延迟（秒）
    resource_delay_range = 10  # 随机波动范围（秒）：总延迟 = 20~30秒

    try:
        file_path, targets = get_target_file_input()
        total_targets = len(targets)
        print(f"\n即将开始批量处理（目标数：{total_targets}，资源类型数：{len(resource_config)}）")
        print(f"目标间延迟：{base_target_delay}~{base_target_delay + target_delay_range}秒（随机）")
        print(f"资源间延迟：{base_resource_delay}~{base_resource_delay + resource_delay_range}秒（随机）\n")

        for target_idx, target in enumerate(targets, 1):
            print(f"📌 开始处理第 {target_idx}/{total_targets} 个目标：{target}")

            for res_idx, (resource_type, output_file) in enumerate(resource_config):
                run_curl_and_save(resource_type, target, output_file)

                # 资源间随机延迟（最后一个类型不间隔）
                if res_idx < len(resource_config) - 1:
                    resource_delay = random.randint(base_resource_delay, base_resource_delay + resource_delay_range)
                    print(f"\n⌛ 等待{resource_delay}秒后处理下一个资源类型...")
                    time.sleep(resource_delay)

            # 目标间随机延迟（最后一个目标不间隔）
            if target_idx < total_targets:
                target_delay = random.randint(base_target_delay, base_target_delay + target_delay_range)
                print(f"\n⌛ 等待{target_delay}秒后处理下一个目标...\n" + "-" * 80)
                time.sleep(target_delay)

        # 处理完成，自动调用Shell脚本（逻辑不变）
        print(f"\n🎉 所有目标处理完成！")
        print(f"📁 结果文件列表：")
        for _, output_file in resource_config:
            print(f"   - {os.path.abspath(output_file)}")
        print(f"📊 详细日志目录：{os.path.abspath('request_logs')}")

        # 自动调用Shell脚本（与之前一致，确保Shell脚本已同步修改）
        print(f"\n==================================================")
        print(f"开始自动执行子域名收集（调用Shell脚本）...")
        print(f"==================================================")
        shell_script_name = "oneforall.sh"  # 对应修改后的Shell脚本名
        current_dir = os.path.dirname(os.path.abspath(__file__))
        shell_script_path = os.path.join(current_dir, shell_script_name)

        if not os.path.exists(shell_script_path):
            print(f"❌ 错误：未找到Shell脚本！路径：{shell_script_path}")
            exit(1)

        if not os.access(shell_script_path, os.X_OK):
            print(f"⚠️ Shell脚本缺少执行权限，正在自动添加...")
            subprocess.run(["chmod", "+x", shell_script_path], check=True)
            print(f"✅ 已为Shell脚本添加执行权限")

        print(f"📌 正在运行Shell脚本：{shell_script_path}")
        shell_result = subprocess.run(
            [shell_script_path],
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8"
        )

        print(f"\n--- Shell脚本执行输出 ---")
        print(shell_result.stdout)
        if shell_result.stderr:
            print(f"--- Shell脚本错误输出 ---")
            print(shell_result.stderr)

        if shell_result.returncode == 0:
            print(f"\n✅ 子域名收集脚本执行完成！结果保存在：~/xinxi/OneForAll-master/results")
        else:
            print(f"\n❌ 子域名收集脚本执行失败（状态码：{shell_result.returncode}）")

    except Exception as e:
        print(f"\n❌ 程序异常终止：{str(e)}")
        exit(1)


if __name__ == "__main__":
    main()
