#!/bin/bash
#
# build.sh — 编译出可直接双击运行的 macOS .app
#
#   ./Scripts/build.sh              # Release（默认），产物 build/apps/NBA.app
#   ./Scripts/build.sh --debug      # Debug 配置
#   ./Scripts/build.sh --with-ios   # 额外产出 iOS 模拟器包（默认不需要）
#
# 产物：build/apps/NBA.app  —— 双击即可运行
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
OUT="$ROOT/build/apps"
PROJECT="$ROOT/NBA.xcodeproj"
SCHEME="NBA"

CONFIG="Release"
WITH_IOS=0
for arg in "$@"; do
    case "$arg" in
        --debug)    CONFIG="Debug" ;;
        --release)  CONFIG="Release" ;;
        --with-ios) WITH_IOS=1 ;;
        -h|--help)  sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

mkdir -p "$OUT"
rm -f "$OUT/.DS_Store"
FAILED=0
declare -a SUMMARY

log()  { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m  ✗\033[0m %s\n' "$1"; FAILED=1; }

# publish <src.app> <dst.app>
# 复制后清理扩展属性：macOS 会给新文件打 com.apple.provenance，
# 模拟器安装 .app 时遇到该属性会报「did not contain any installable apps」。
publish() {
    rm -rf "$2"
    cp -R "$1" "$2"
    xattr -cr "$2" 2>/dev/null || true
}

# compile <destination> <产物名> <products 子目录>
# macOS 产物落在 Build/Products/<CONFIG>/，而 iOS 模拟器落在 Build/Products/<CONFIG>-iphonesimulator/，
# 必须按平台指定子目录，否则会把已存在的 macOS 包当成 iOS 产物发布出去。
compile() {
    local dest="$1" name="$2" products="$3"
    log "$name ($CONFIG)"
    local log_file; log_file="$(mktemp)"
    if xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
            -configuration "$CONFIG" -destination "$dest" \
            -derivedDataPath "$DERIVED" \
            CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
            build >"$log_file" 2>&1; then
        local app="$DERIVED/Build/Products/$products/NBA.app"
        if [ -d "$app" ]; then
            publish "$app" "$OUT/$name.app"
            local size; size=$(du -sh "$OUT/$name.app" | cut -f1)
            ok "$name.app  $size"
            SUMMARY+=("✅  $OUT/$name.app  ($size)")
        else
            fail "$name 编译成功但未找到 $products/NBA.app"
            SUMMARY+=("❌  $name: 未找到产物")
        fi
    else
        fail "$name 编译失败："
        grep -E "error:" "$log_file" | sed 's/^ *//' | sort -u | head -15 | sed 's/^/      /'
        SUMMARY+=("❌  $name: 编译失败")
    fi
    rm -f "$log_file"
}

if command -v xcodegen >/dev/null 2>&1; then
    log "xcodegen generate"
    (cd "$ROOT" && xcodegen generate --quiet)
fi
[ -d "$PROJECT" ] || { fail "找不到 $PROJECT，请先安装 xcodegen: brew install xcodegen"; exit 1; }

compile 'platform=macOS' 'NBA' "$CONFIG"
[ "$WITH_IOS" -eq 1 ] && compile 'generic/platform=iOS Simulator' 'NBA-iOS-Simulator' "$CONFIG-iphonesimulator"

echo
echo "────────────────────────────────────────────────"
printf '%s\n' "${SUMMARY[@]}"
echo "────────────────────────────────────────────────"
if [ "$FAILED" -eq 0 ]; then
    printf '\033[1;32m全部通过\033[0m（%s）\n' "$CONFIG"
    echo "双击运行:  open '$OUT/NBA.app'"
else
    printf '\033[1;31m存在失败项\033[0m\n'
fi
exit "$FAILED"
