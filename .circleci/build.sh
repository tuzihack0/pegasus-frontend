#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail   # ← 额外保险：管道中任何一步错了就退出
set -o xtrace

# 1) 确保在仓库根目录
echo "PWD =" && pwd
test -f .qmake.stash || true

# 2) 打印 Git 状态，用于定位“为什么 CI 看不到 dislikes 目录”
echo "HEAD =" && git rev-parse HEAD
echo "HEAD commit =" && git log -1 --oneline
echo "List providers dir:" && ls -la src/backend/providers || true
echo "List dislikes dir:" && ls -la src/backend/providers/pegasus_dislikes || true
echo "Git index (tracked files about dislikes):" && git ls-files | grep -i pegasus_dislikes || true

# 3) 选好 Qt 目录（和你之前日志里一致）
QT_DIR=/opt/${QT_VERSION}_${QT_TARGET}_hosttools
if [[ ! -d "$QT_DIR" ]]; then
  QT_DIR=/opt/${QT_VERSION}_${QT_TARGET}
fi

${QT_DIR}/bin/qmake --version

# 4) 跟你之前成功构建时的 qmake 选项保持一致（特别是 ANDROID_ABIS / FORCE_QT_PNG）
#    注意 QMAKE_CXXFLAGS 的引号：用单引号整体包住更稳
eval ${QT_DIR}/bin/qmake . \
  ENABLE_APNG=1 \
  ANDROID_ABIS=arm64-v8a \
  FORCE_QT_PNG=1 \
  ${BUILDOPTS:-} \
  "QMAKE_CXXFLAGS+=-Wall -Wextra -pedantic"

# 5) 构建与安装
make -j"$(nproc)"
make install INSTALL_ROOT="${PWD}/installdir"
