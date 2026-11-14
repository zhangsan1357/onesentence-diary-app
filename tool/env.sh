#!/usr/bin/env bash
# 会话环境准备（Git Bash）：source tool/env.sh
# 1) Flutter 入 PATH
# 2) sqlite3 user_define=system：Windows 宿主跑 flutter test 需要 sqlite3.dll 在 PATH
export PATH="/e/flutter/bin:$PWD/tool/bin:$PATH"
