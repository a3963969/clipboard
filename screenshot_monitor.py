#!/usr/bin/env python3
"""
Mac 截图监控服务
1. 检测桌面新截图文件，复制路径到剪切板
2. 检测剪贴板新图片，保存为文件后复制路径到剪切板
"""

import os
import re
import subprocess
import time
import hashlib
from pathlib import Path
from datetime import datetime

# 尝试导入 AppKit（PyObjC）
try:
    from AppKit import NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeTIFF, NSWorkspace
    HAS_APPKIT = True
except ImportError:
    HAS_APPKIT = False

# Cursor 应用名称
CURSOR_APP_NAME = "Cursor"


def get_frontmost_app():
    """获取当前焦点应用名称（使用 AppleScript）"""
    try:
        result = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to get name of first application process whose frontmost is true'],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def is_cursor_frontmost():
    """检测 Cursor IDE 是否在前台"""
    app_name = get_frontmost_app()
    return app_name == CURSOR_APP_NAME


def get_screenshot_location():
    """获取 Mac 截图保存位置"""
    try:
        result = subprocess.run(
            ["defaults", "read", "com.apple.screencapture", "location"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return os.path.expanduser("~/Desktop")


def copy_to_clipboard(text):
    """将文本复制到剪切板"""
    process = subprocess.Popen(
        ["pbcopy"],
        stdin=subprocess.PIPE,
        text=True
    )
    process.communicate(text)


def is_screenshot_file(filename):
    """判断是否为截图文件"""
    patterns = [
        r"^屏幕快照\s+\d{4}-\d{2}-\d{2}\s+的\s+.+\.(png|jpg|jpeg)$",
        r"^截屏\s+\d{4}-\d{2}-\d{2}\s+.+\.(png|jpg|jpeg)$",
        r"^Screenshot\s+\d{4}-\d{2}-\d{2}\s+at\s+.+\.(png|jpg|jpeg)$",
        r"^CleanShot\s+.+\.(png|jpg|jpeg)$",
    ]
    for pattern in patterns:
        if re.match(pattern, filename, re.IGNORECASE):
            return True
    return False


def send_notification(title, message):
    """发送系统通知"""
    # 转义特殊字符
    message = message.replace('"', '\\"').replace("'", "\\'")
    script = f'display notification "{message}" with title "{title}"'
    subprocess.run(["osascript", "-e", script], capture_output=True)


class ClipboardMonitor:
    """剪贴板图片监控"""

    def __init__(self, save_dir):
        self.save_dir = Path(save_dir)
        self.save_dir.mkdir(parents=True, exist_ok=True)
        self.last_change_count = 0
        self.last_image_hash = None

    def get_clipboard_image(self):
        """获取剪贴板中的图片数据"""
        if not HAS_APPKIT:
            return None

        pasteboard = NSPasteboard.generalPasteboard()

        # 检查剪贴板变化计数
        current_count = pasteboard.changeCount()
        if current_count == self.last_change_count:
            return None
        self.last_change_count = current_count

        # 尝试获取 PNG 或 TIFF 图片
        image_data = pasteboard.dataForType_(NSPasteboardTypePNG)
        if not image_data:
            image_data = pasteboard.dataForType_(NSPasteboardTypeTIFF)

        if image_data:
            return bytes(image_data)
        return None

    def save_image(self, image_data):
        """保存图片到文件"""
        # 计算图片哈希，避免重复保存
        image_hash = hashlib.md5(image_data).hexdigest()[:8]
        if image_hash == self.last_image_hash:
            return None
        self.last_image_hash = image_hash

        # 生成文件名
        timestamp = datetime.now().strftime("%Y-%m-%d_%H.%M.%S")
        filename = f"剪贴板截图_{timestamp}_{image_hash}.png"
        filepath = self.save_dir / filename

        # 保存文件
        with open(filepath, "wb") as f:
            f.write(image_data)

        return str(filepath)


class ScreenshotMonitor:
    """截图文件监控"""

    def __init__(self):
        self.watch_dir = get_screenshot_location()
        self.known_files = set()
        self.poll_interval = 0.5  # 检查间隔（秒）

        # 剪贴板监控（保存到同一目录）
        self.clipboard_monitor = ClipboardMonitor(self.watch_dir) if HAS_APPKIT else None

        # 待复制的截图路径（等待切换到 Cursor 时复制）
        self.pending_screenshot = None
        self.last_frontmost_app = None

    def initialize_known_files(self):
        """初始化已知文件列表"""
        watch_path = Path(self.watch_dir)
        if watch_path.exists():
            for f in watch_path.iterdir():
                if f.is_file():
                    self.known_files.add(str(f))

    def check_new_screenshots(self):
        """检查新截图文件"""
        watch_path = Path(self.watch_dir)
        if not watch_path.exists():
            return None

        for f in watch_path.iterdir():
            if not f.is_file():
                continue

            file_path = str(f)
            if file_path in self.known_files:
                continue

            if is_screenshot_file(f.name):
                # 检查文件是否刚刚创建（5秒内）
                try:
                    mtime = f.stat().st_mtime
                    if time.time() - mtime < 5:
                        self.known_files.add(file_path)
                        return file_path
                except OSError:
                    pass

            # 添加到已知文件
            self.known_files.add(file_path)

        return None

    def check_clipboard_image(self):
        """检查剪贴板新图片"""
        if not self.clipboard_monitor:
            return None

        image_data = self.clipboard_monitor.get_clipboard_image()
        if image_data:
            saved_path = self.clipboard_monitor.save_image(image_data)
            if saved_path:
                # 添加到已知文件，避免重复检测
                self.known_files.add(saved_path)
                return saved_path
        return None

    def run(self):
        """运行监控服务"""
        print("截图监控服务已启动")
        print(f"监控目录: {self.watch_dir}")
        print(f"剪贴板监控: {'已启用' if HAS_APPKIT else '未启用 (需要 pyobjc)'}")
        print("-" * 50)
        print("功能说明:")
        print("  • 截图后，切换到 Cursor 时自动复制路径")
        print("  • Cmd+Shift+3/4 截图 → 文件路径")
        print("  • Cmd+Ctrl+Shift+3/4 截图到剪贴板 → 自动保存后复制路径")
        print("-" * 50)

        self.initialize_known_files()
        self.last_frontmost_app = get_frontmost_app()

        try:
            while True:
                timestamp = datetime.now().strftime("%H:%M:%S")

                # 检查桌面新截图
                new_screenshot = self.check_new_screenshots()
                if new_screenshot:
                    self.pending_screenshot = new_screenshot
                    print(f"[{timestamp}] 检测到截图: {os.path.basename(new_screenshot)}")

                # 检查剪贴板新图片
                clipboard_image = self.check_clipboard_image()
                if clipboard_image:
                    self.pending_screenshot = clipboard_image
                    print(f"[{timestamp}] 检测到剪贴板图片: {os.path.basename(clipboard_image)}")

                # 检测焦点切换到 Cursor
                current_app = get_frontmost_app()
                if (self.pending_screenshot and
                    current_app == CURSOR_APP_NAME and
                    self.last_frontmost_app != CURSOR_APP_NAME):
                    # 从其他应用切换到 Cursor，复制路径
                    copy_to_clipboard(self.pending_screenshot)
                    print(f"[{timestamp}] 切换到 Cursor，已复制: {self.pending_screenshot}")
                    send_notification("截图路径已复制", os.path.basename(self.pending_screenshot))
                    self.pending_screenshot = None

                self.last_frontmost_app = current_app
                time.sleep(self.poll_interval)
        except KeyboardInterrupt:
            print("\n服务已停止")


if __name__ == "__main__":
    if not HAS_APPKIT:
        print("提示: 安装 pyobjc 以启用剪贴板监控功能")
        print("运行: pip3 install pyobjc-framework-Cocoa")
        print()

    monitor = ScreenshotMonitor()
    monitor.run()
