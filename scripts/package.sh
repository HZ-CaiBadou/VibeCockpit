#!/bin/bash

# VibeCockpit 本地一键打包脚本。
# 用法：./scripts/package.sh（按提示输入版本号）
# 可选：PACKAGE_VERSION=3.2.10 ./scripts/package.sh
# 可选：CODE_SIGN_IDENTITY="Developer ID Application: Your Name" ./scripts/package.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="VibeCockpit"
SCHEME_NAME="VibeCockpit"
PROJECT_FILE="${PROJECT_ROOT}/${PROJECT_NAME}.xcodeproj"
BUILD_DIR="${PROJECT_ROOT}/build"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"

# 优先使用完整 Xcode，避免系统仍指向 Command Line Tools 时构建失败。
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$PROJECT_FILE" ]]; then
    echo "错误：找不到 Xcode 项目：$PROJECT_FILE" >&2
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "错误：未找到可用的 Xcode。请安装完整 Xcode，或设置 DEVELOPER_DIR。" >&2
    exit 1
fi

CURRENT_VERSION="$(xcodebuild -showBuildSettings \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME_NAME" \
    -configuration Release 2>/dev/null | awk -F ' = ' '/ MARKETING_VERSION = / { print $2; exit }')"

if [[ -z "$CURRENT_VERSION" ]]; then
    echo "错误：无法读取 MARKETING_VERSION。" >&2
    exit 1
fi

VERSION="${PACKAGE_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    echo "当前版本：$CURRENT_VERSION"
    read -r -p "请输入本次版本号（例如 3.2.10）：" VERSION
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "错误：版本号必须为数字点分格式，例如 3.2.10。" >&2
    exit 1
fi

MARKETING_VERSION_COUNT="$(/usr/bin/grep -c 'MARKETING_VERSION = ' "$PROJECT_FILE/project.pbxproj")"
if [[ "$MARKETING_VERSION_COUNT" -ne 2 ]]; then
    echo "错误：项目中预期有 2 个 MARKETING_VERSION，实际找到 $MARKETING_VERSION_COUNT 个。" >&2
    exit 1
fi

if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
    /usr/bin/sed -i '' -E "s/(MARKETING_VERSION = )[0-9]+(\.[0-9]+){1,2};/\\1${VERSION};/g" "$PROJECT_FILE/project.pbxproj"
    echo "==> 版本已更新：$CURRENT_VERSION → $VERSION"
else
    echo "==> 版本保持为：$VERSION"
fi

OUTPUT_DIR="${BUILD_DIR}/${PROJECT_NAME}-Release-${VERSION}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${PROJECT_NAME}.app"
OUTPUT_APP_PATH="${OUTPUT_DIR}/${PROJECT_NAME}.app"
DMG_NAME="${PROJECT_NAME}-v${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
LOG_FILE="${OUTPUT_DIR}/package.log"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
: > "$LOG_FILE"
STAGING_DIR="$(mktemp -d "${BUILD_DIR}/.${PROJECT_NAME}-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

run_logged() {
    local step="$1"
    shift

    if ! "$@" >> "$LOG_FILE" 2>&1; then
        echo "错误：${step}失败。日志末尾如下：" >&2
        tail -n 40 "$LOG_FILE" >&2
        echo "完整日志：$LOG_FILE" >&2
        exit 1
    fi
}

echo "==> Release 构建（Universal）"
run_logged "Release 构建" xcodebuild clean build \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS,name=Any Mac" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "CODE_SIGN_IDENTITY=${SIGNING_IDENTITY}" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=
echo "    完成"

if [[ ! -d "$APP_PATH" ]]; then
    echo "错误：构建未生成 App：$APP_PATH" >&2
    exit 1
fi

echo "==> 验证 App 签名和版本"
rm -rf "$OUTPUT_APP_PATH"
rm -f "$DMG_PATH"
run_logged "复制 App" ditto "$APP_PATH" "$OUTPUT_APP_PATH"
run_logged "App 签名校验" codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP_PATH"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${OUTPUT_APP_PATH}/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$VERSION" ]]; then
    echo "错误：App 版本 $APP_VERSION 与项目版本 $VERSION 不一致。" >&2
    exit 1
fi
echo "    完成"

run_logged "准备 DMG 内容" ditto "$OUTPUT_APP_PATH" "${STAGING_DIR}/${PROJECT_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> 创建并校验 DMG"
run_logged "创建 DMG" hdiutil create \
    -volname "$PROJECT_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
run_logged "DMG 校验" hdiutil verify "$DMG_PATH"
echo "    完成"

echo
echo "打包完成：$DMG_PATH"
echo "SHA-256：$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
echo "详细日志：$LOG_FILE"
echo "说明：未设置 CODE_SIGN_IDENTITY 时，产物使用本地 ad-hoc 签名。"
