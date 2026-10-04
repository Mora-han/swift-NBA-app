#!/bin/bash
#
# revert.sh — 版本管理快捷入口
#
#   ./Scripts/revert.sh snapshot "说明文字"     存一个可回退的版本点
#   ./Scripts/revert.sh list                    列出所有版本点
#   ./Scripts/revert.sh show                    查看当前状态与最近提交
#   ./Scripts/revert.sh undo                    撤销未提交的改动
#   ./Scripts/revert.sh back <n>                回退到第 n 个版本点
#   ./Scripts/revert.sh diff <n>                看当前与第 n 个版本点的差异
#   ./Scripts/revert.sh build [n]               回退后重新编译出 .app
#
# 回退默认「保留一个恢复分支」，随时能切回来：
#   git branch recover-最新切换时间点
#
set -euo pipefail
cd "$(dirname "$0")/.."

TAG_PREFIX="v"
log()  { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$1"; exit 1; }

# 当前代码状态是否干净
dirty_check() {
    if [ -n "$(git status --porcelain)" ]; then
        warn "当前有未提交的改动："
        git status --short | sed 's/^/    /'
        return 1
    fi
    return 0
}

case "${1:-show}" in

snapshot)
    MSG="${2:-}"
    [ -n "$MSG" ] || die "请提供说明文字：./Scripts/revert.sh snapshot \"说明\""
    dirty_check || die "请先处理未提交的改动（或先跑一次 snapshot 提交它们）"

    git add -A
    git commit -q -m "$MSG"
    N=$(git rev-list --count HEAD)
    TAG="${TAG_PREFIX}${N}-$(echo "$MSG" | tr ' ' '-' | cut -c1-30)"
    git tag -a "$TAG" -m "$MSG"
    ok "版本点 $TAG 已保存"
    ok "回退命令：./Scripts/revert.sh back ${TAG_PREFIX}${N}"
    ;;

list)
    log "版本点列表（新 → 旧）"
    git tag --sort=-creatordate --format='  %(refname:short)  %(creatordate:short)  %(contents:subject)' | head -30
    echo
    log "提交历史"
    git log --oneline --decorate | head -15 | sed 's/^/  /'
    ;;

show)
    log "仓库状态"
    if dirty_check; then ok "工作区干净（无未提交改动）"; fi
    log "最近提交"
    git log --oneline --decorate | head -10 | sed 's/^/  /'
    echo
    log "版本点数量: $(git tag | wc -l | tr -d ' ')"
    ;;

undo)
    if [ -z "$(git status --porcelain)" ]; then
        die "没有未提交的改动，无需撤销"
    fi
    log "将丢弃以下未提交改动："
    git status --short | sed 's/^/    /'
    printf '确认丢弃？(y/N) '
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { warn "已取消"; exit 0; }
    git reset --hard HEAD
    ok "已恢复到最近一次提交"
    ;;

back)
    TARGET="${2:-}"
    [ -n "$TARGET" ] || die "用法：./Scripts/revert.sh back v1 或 ./Scripts/revert.sh back HEAD~1"
    git rev-parse --verify "$TARGET" >/dev/null 2>&1 || die "找不到版本点 $TARGET，用 ./Scripts/revert.sh list 查看"

    RECOVER="recover-$(date +%m%d-%H%M)"
    git branch "$RECOVER"
    ok "当前状态已存为分支 $RECOVER（随时 git checkout $RECOVER 切回来）"

    log "切到 $TARGET"
    if git checkout -q "$TARGET" 2>/dev/null; then
        ok "已切换到 $TARGET"
    else
        # detached HEAD 场景
        git checkout -q --detach "$TARGET"
        ok "已切换到 $TARGET（detached HEAD）"
    fi
    log "当前代码："
    git log --oneline -1 | sed 's/^/    /'
    echo
    warn "重新编译出 .app：./Scripts/build.sh"
    warn "切回刚才的状态：git checkout $RECOVER"
    ;;

diff)
    TARGET="${2:-}"
    [ -n "$TARGET" ] || die "用法：./Scripts/revert.sh diff v1"
    git rev-parse --verify "$TARGET" >/dev/null 2>&1 || die "找不到版本点 $TARGET"
    git diff --stat "$TARGET" | sed 's/^/  /'
    ;;

build)
    git checkout -q HEAD 2>/dev/null || true
    log "编译"
    exec ./Scripts/build.sh "${@:2}"
    ;;

*)
    sed -n '2,18p' "$0"
    exit 1
    ;;
esac