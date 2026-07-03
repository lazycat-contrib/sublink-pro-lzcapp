#!/usr/bin/env bash
set -euo pipefail

# 一键升级版本号 + 构建 LPK + git 提交推送（不提交应用商店）
#
# 用法:
#   scripts/release.sh 1.2.14        # 指定新版本
#   scripts/release.sh               # 不指定则 patch 位自动 +1
#   scripts/release.sh 1.2.14 --no-push   # 只提交不推送

cd "$(dirname "$0")/.."

PACKAGE_FILE=package.yml
MANIFEST_FILE=lzc-manifest.yml
BUILD_FILE=lzc-build.yml

die() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

PUSH=1
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    -h|--help) sed -n '4,10p' "$0"; exit 0 ;;
    -*) die "unknown option: $arg" ;;
    *) VERSION=$arg ;;
  esac
done

command -v lzc-cli >/dev/null || die "lzc-cli not found"
[[ -f "$PACKAGE_FILE" && -f "$MANIFEST_FILE" && -f "$BUILD_FILE" ]] || die "config files missing"

# 工作区必须干净（未跟踪的 lpk 除外），避免把无关改动混进 bump 提交
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree has uncommitted changes; commit or stash them first"
fi

CURRENT=$(awk '/^version:/ { print $2; exit }' "$PACKAGE_FILE")
[[ -n "$CURRENT" ]] || die "cannot read version from $PACKAGE_FILE"

if [[ -z "$VERSION" ]]; then
  [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "current version '$CURRENT' is not x.y.z, pass new version explicitly"
  VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$(( BASH_REMATCH[3] + 1 ))"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be x.y.z, got: $VERSION"
[[ "$VERSION" != "$CURRENT" ]] || die "new version equals current version ($CURRENT)"

note "version: $CURRENT -> $VERSION"

# 更新 package.yml 顶层 version
sed -i "0,/^version: .*/s//version: $VERSION/" "$PACKAGE_FILE"

# 更新 manifest 镜像 tag（保留镜像名，只替换 :vX.Y.Z）
grep -q ":v$CURRENT" "$MANIFEST_FILE" || die "image tag :v$CURRENT not found in $MANIFEST_FILE"
sed -i "s|:v$CURRENT|:v$VERSION|" "$MANIFEST_FILE"
note "image: $(awk '/image:/ { print $2 }' "$MANIFEST_FILE")"

# 构建 LPK
PACKAGE_ID=$(awk '/^package:/ { print $2; exit }' "$PACKAGE_FILE")
LPK_FILE="${PACKAGE_ID}-v${VERSION}.lpk"
note "building $LPK_FILE"
lzc-cli project build -f "$BUILD_FILE"
[[ -f "$LPK_FILE" ]] || die "build output not found: $LPK_FILE"

# 提交并推送
git add "$PACKAGE_FILE" "$MANIFEST_FILE" "$LPK_FILE"
git commit -m "bump $VERSION"
if [[ "$PUSH" == "1" ]]; then
  git push
  note "pushed to $(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
else
  note "skipped push (--no-push)"
fi

echo
echo "Done: $LPK_FILE"
