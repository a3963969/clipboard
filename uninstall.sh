#!/bin/bash
# 卸载截图监控服务

PLIST_NAME="com.user.screenshotmonitor.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"

echo "卸载截图监控服务..."

# 停止服务
if launchctl list | grep -q "com.user.screenshotmonitor"; then
    echo "停止服务..."
    launchctl unload "${PLIST_DEST}" 2>/dev/null
fi

# 删除 plist 文件
if [ -f "${PLIST_DEST}" ]; then
    rm "${PLIST_DEST}"
    echo "已删除服务配置文件"
fi

# 清理日志
rm -f /tmp/screenshot_monitor.log /tmp/screenshot_monitor.err 2>/dev/null

echo "服务已卸载！"
