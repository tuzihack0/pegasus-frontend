#!/usr/bin/env bash
set -Eeuo pipefail
set -x

# ---------- 0) 基本信息 & 诊断输出 ----------
echo "PWD =" && pwd
echo "HEAD =" && git rev-parse HEAD
echo "HEAD commit =" && git log -1 --oneline || true

echo "List providers dir:" && ls -la src/backend/providers || true
echo "List dislikes dir:" && ls -la "src/backend/providers/pegasus_dislikes" || true
echo "Git index (tracked files about dislikes):" && git ls-files | grep -i "src/backend/providers/pegasus_dislikes" || true

# 可选：如有子模块，确保拉全
git submodule update --init --recursive || true

# ---------- 1) 选择 Qt 目录 ----------
QT_DIR="/opt/${QT_VERSION}_${QT_TARGET}_hosttools"
if [[ ! -d "$QT_DIR" ]]; then
  QT_DIR="/opt/${QT_VERSION}_${QT_TARGET}"
fi
# 兜底（防止上面两个环境变量没传）
if [[ ! -d "$QT_DIR" ]]; then
  QT_DIR="/opt/qt51510_android"
fi

"${QT_DIR}/bin/qmake" --version

# ---------- 2) 生成 Makefile ----------
# 注意：不要再用 eval；把 CXXFLAGS 当作一个整体参数传入，避免 -Wextra 被 qmake 当做自身参数解析
# ANDROID_ABIS 默认 arm64-v8a；保持与历史构建一致
ANDROID_ABIS_VALUE="${ANDROID_ABIS:-arm64-v8a}"

"${QT_DIR}/bin/qmake" . \
  ENABLE_APNG=1 \
  ANDROID_ABIS="${ANDROID_ABIS_VALUE}" \
  FORCE_QT_PNG=1 \
  ${BUILDOPTS:-} \
  "QMAKE_CXXFLAGS+=-Wall -Wextra -pedantic"

# ---------- 3) 编译 & 安装 ----------
make -j"$(nproc)"
make install INSTALL_ROOT="${PWD}/installdir"
