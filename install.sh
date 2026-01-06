#!/bin/bash
# 安装截图监控服务

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.user.screenshotmonitor.plist"
PLIST_SRC="${SCRIPT_DIR}/${PLIST_NAME}"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"

echo "安装截图监控服务..."

# 确保 LaunchAgents 目录存在
mkdir -p "${HOME}/Library/LaunchAgents"

# 如果服务已在运行，先停止
if launchctl list | grep -q "com.user.screenshotmonitor"; then
    echo "停止现有服务..."
    launchctl unload "${PLIST_DEST}" 2>/dev/null
fi

# 复制 plist 文件
cp "${PLIST_SRC}" "${PLIST_DEST}"

# 更新 plist 中的路径（使用实际路径）
sed -i '' "s|/Users/company/编程代码库/剪切板|${SCRIPT_DIR}|g" "${PLIST_DEST}"

# 加载服务
launchctl load "${PLIST_DEST}"

echo "服务安装完成！"
echo ""
echo "服务状态:"
launchctl list | grep screenshotmonitor

echo ""
echo "日志位置: /tmp/screenshot_monitor.log"
echo "使用 'tail -f /tmp/screenshot_monitor.log' 查看实时日志"
