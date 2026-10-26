#!/usr/bin/env python3
"""把一个新版本写进 Sparkle 的 appcast.xml（新版本放在最前面）。

用法：
  scripts/update_appcast.py --appcast appcast.xml --version 0.2.0 --build 202610261200 \\
      --url https://github.com/<owner>/<repo>/releases/download/v0.2.0/AICronHelper-0.2.0.dmg \\
      --sign-output 'sparkle:edSignature="..." length="..."' --notes docs/release-notes/0.2.0.md

--sign-output 直接传 sign_update 的输出；--notes 是 Markdown，会显示在 App 的更新窗口里。
"""
import argparse
import email.utils
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

HEADER = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AI 定时任务</title>
"""
FOOTER = """  </channel>
</rss>
"""


def build_item(args, signature, length, notes):
    # CDATA 里不能出现 "]]>"，拆成两段
    notes = notes.replace("]]>", "]]]]><![CDATA[>")
    pub_date = email.utils.format_datetime(datetime.now(timezone.utc))
    return f"""    <item>
      <title>{escape(args.version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(args.min_os)}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
{notes.strip()}
]]></description>
      <enclosure url={quoteattr(args.url)} type="application/octet-stream" sparkle:edSignature={quoteattr(signature)} length={quoteattr(length)}/>
    </item>
"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--appcast", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--sign-output", required=True)
    p.add_argument("--notes", required=True)
    p.add_argument("--min-os", default="14.0")
    args = p.parse_args()

    if not re.fullmatch(r"\d+(\.\d+)*", args.version) or not re.fullmatch(r"\d+", args.build):
        sys.exit(f"版本号或构建号格式不对：{args.version} / {args.build}")
    sig = re.search(r'sparkle:edSignature="([^"]+)"', args.sign_output)
    length = re.search(r'length="(\d+)"', args.sign_output)
    if not sig or not length:
        sys.exit(f"sign_update 输出里没有签名或长度：{args.sign_output!r}")
    notes = Path(args.notes).read_text(encoding="utf-8")
    if not notes.strip():
        sys.exit("更新说明为空")

    path = Path(args.appcast)
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    if not text.strip():
        text = HEADER + FOOTER
    if f"<sparkle:shortVersionString>{args.version}<" in text or f"<sparkle:version>{args.build}<" in text:
        sys.exit(f"appcast 里已经有 {args.version}（{args.build}）")
    builds = [int(b) for b in re.findall(r"<sparkle:version>(\d+)</sparkle:version>", text)]
    if builds and int(args.build) <= max(builds):
        sys.exit(f"构建号 {args.build} 不大于已有的 {max(builds)}，Sparkle 不会认为它是新版本")

    item = build_item(args, sig.group(1), length.group(1), notes)
    anchor = "    <item>" if "    <item>" in text else "  </channel>"
    if anchor not in text:
        sys.exit(f"{path} 格式不对：找不到插入位置")
    text = text.replace(anchor, item + anchor, 1)
    path.write_text(text, encoding="utf-8")
    print(f"已写入 {args.version}（{args.build}）→ {path}")


if __name__ == "__main__":
    main()
