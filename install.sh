#!/bin/bash
# 安装截图监控服务

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.user.screenshotmonitor.plist"
PLIST_SRC="${SCRIPT_DIR}/${PLIST_NAME}"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"

echo "=========================================="
echo "  Mac 截图路径自动复制服务 - 安装程序"
echo "=========================================="
echo ""

# 1. 创建并配置虚拟环境
echo "[1/4] 检查并安装 Python 依赖..."
VENV_DIR="${SCRIPT_DIR}/venv"
VENV_PYTHON="${VENV_DIR}/bin/python3"

# 创建虚拟环境（如果不存在）
if [ ! -d "${VENV_DIR}" ]; then
    echo "  → 创建虚拟环境..."
    python3 -m venv "${VENV_DIR}"
    if [ $? -ne 0 ]; then
        echo "  ✗ 虚拟环境创建失败"
        exit 1
    fi
    echo "  ✓ 虚拟环境创建成功"
fi

# 激活虚拟环境并安装依赖
if "${VENV_PYTHON}" -c "from AppKit import NSPasteboard" 2>/dev/null; then
    echo "  ✓ pyobjc 已安装"
else
    echo "  → 正在安装 pyobjc-framework-Cocoa..."
    "${VENV_DIR}/bin/pip" install pyobjc-framework-Cocoa --quiet
    if "${VENV_PYTHON}" -c "from AppKit import NSPasteboard" 2>/dev/null; then
        echo "  ✓ pyobjc 安装成功"
    else
        echo "  ✗ pyobjc 安装失败，请手动运行: ${VENV_DIR}/bin/pip install pyobjc-framework-Cocoa"
        exit 1
    fi
fi
echo ""

# 2. 确保 LaunchAgents 目录存在
echo "[2/4] 配置 LaunchAgent 服务..."
mkdir -p "${HOME}/Library/LaunchAgents"

# 如果服务已在运行，先停止
if launchctl list 2>/dev/null | grep -q "com.user.screenshotmonitor"; then
    echo "  → 停止现有服务..."
    launchctl unload "${PLIST_DEST}" 2>/dev/null || true
fi

# 复制 plist 文件并更新路径
cp "${PLIST_SRC}" "${PLIST_DEST}"
sed -i '' "s|/Users/company/编程代码库/剪切板|${SCRIPT_DIR}|g" "${PLIST_DEST}"
# 更新 Python 路径为虚拟环境中的 Python
sed -i '' "s|/usr/bin/python3|${VENV_PYTHON}|g" "${PLIST_DEST}"
echo "  ✓ 服务配置完成"
echo ""

# 3. 检查权限
echo "[3/4] 检查系统权限..."
NEED_PERMISSION=false

# 测试是否能读取脚本（完全磁盘访问权限）
if ! "${VENV_PYTHON}" -c "open('${SCRIPT_DIR}/screenshot_monitor.py', 'r').close()" 2>/dev/null; then
    echo "  ⚠ 需要「完全磁盘访问权限」"
    NEED_PERMISSION=true
fi

# 测试辅助功能权限（检测前台应用需要）
if ! osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' &>/dev/null; then
    echo "  ⚠ 需要「辅助功能」权限"
    NEED_PERMISSION=true
fi

if [ "$NEED_PERMISSION" = true ]; then
    echo ""
    echo "=========================================="
    echo "  需要授予系统权限才能正常运行"
    echo "=========================================="
    echo ""
    echo "请按以下步骤操作："
    echo ""
    echo "1. 打开「系统设置」→「隐私与安全性」"
    echo ""
    echo "2. 添加「完全磁盘访问权限」:"
    echo "   - 点击「完全磁盘访问权限」"
    echo "   - 点击 + 号，添加: ${VENV_PYTHON}"
    echo "   - 或添加「终端」应用"
    echo ""
    echo "3. 添加「辅助功能」权限:"
    echo "   - 点击「辅助功能」"
    echo "   - 点击 + 号，添加: ${VENV_PYTHON}"
    echo "   - 或添加「终端」应用"
    echo ""

    read -p "是否现在打开系统设置? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        # 打开隐私设置
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        echo ""
        echo "请在系统设置中完成授权，然后按回车键继续..."
        read -r
    fi
else
    echo "  ✓ 权限检查通过"
fi
echo ""

# 4. 加载服务
echo "[4/4] 启动服务..."
launchctl load "${PLIST_DEST}"

# 等待服务启动
sleep 1

# 检查服务状态
if launchctl list 2>/dev/null | grep -q "com.user.screenshotmonitor"; then
    STATUS=$(launchctl list | grep "com.user.screenshotmonitor" | awk '{print $2}')
    if [ "$STATUS" = "0" ] || [ "$STATUS" = "-" ]; then
        echo "  ✓ 服务启动成功"
    else
        echo "  ⚠ 服务已加载但可能有错误 (退出码: $STATUS)"
        echo "    查看错误日志: cat /tmp/screenshot_monitor.err"
    fi
else
    echo "  ✗ 服务启动失败"
    exit 1
fi

echo ""
echo "=========================================="
echo "  安装完成!"
echo "=========================================="
echo ""
echo "功能说明:"
echo "  • Cmd+Shift+3/4 截图后，切换到 Cursor 自动复制路径"
echo "  • Cmd+Ctrl+Shift+3/4 截图到剪贴板，自动保存并复制路径"
echo ""
echo "常用命令:"
echo "  查看日志: tail -f /tmp/screenshot_monitor.log"
echo "  查看错误: cat /tmp/screenshot_monitor.err"
echo "  停止服务: launchctl unload ${PLIST_DEST}"
echo "  启动服务: launchctl load ${PLIST_DEST}"
echo "  卸载服务: ${SCRIPT_DIR}/uninstall.sh"
echo ""
