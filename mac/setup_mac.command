#!/bin/bash
# =============================================================================
#  MeowD reader — macOS 설치 (네이티브: .md 더블클릭 연결 + ✎ 편집)
# =============================================================================
#  ⚠ 이 스크립트는 Windows에서 작성되어 macOS에서 직접 테스트되지 못했습니다.
#     에러가 나면 universal/md-viewer.html 을 그냥 열어 쓰면 설치 없이 동작합니다.
#     (또는 에러 메시지와 함께 이슈를 남겨주세요.)
# =============================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MDVIEW="$REPO/md_view.py"

echo "▶ MeowD reader — macOS 설치 시작"
[ -f "$MDVIEW" ] || { echo "✗ md_view.py 를 찾을 수 없음: $MDVIEW"; exit 1; }

# 1) python3 확인
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "✗ python3 가 필요합니다. 설치 후 다시 실행:"
  echo "    https://www.python.org/downloads/   또는   brew install python"
  exit 1
fi
echo "✓ python3: $PY"

# 2) 렌더 라이브러리
echo "▶ 라이브러리 설치 (markdown, pygments)…"
"$PY" -m pip install --user --quiet markdown pygments || \
  echo "  (pip 실패 — 수동: pip3 install --user markdown pygments)"

# 3) AppleScript 앱 생성 (.md 열기 + mdedit: 프로토콜)
APP="$HOME/Applications/MeowD reader.app"
mkdir -p "$HOME/Applications"
TMP="$(mktemp -t meowd).applescript"
cat > "$TMP" <<APPLESCRIPT
on run
    display notification "MeowD reader 준비됨 — .md 더블클릭으로 여세요." with title "MeowD reader"
end run
on open theFiles
    repeat with f in theFiles
        set p to POSIX path of f
        do shell script quoted form of "$PY" & " " & quoted form of "$MDVIEW" & " " & quoted form of p
    end repeat
end open
on open location this_URL
    set thePath to do shell script quoted form of "$PY" & " -c " & quoted form of "import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1].split(':',1)[1]))" & " " & quoted form of this_URL
    do shell script "open -t " & quoted form of thePath
end open location
APPLESCRIPT
rm -rf "$APP"
osacompile -o "$APP" "$TMP"
rm -f "$TMP"

# 4) Info.plist: .md 문서 타입 + mdedit URL 스킴 + 번들 ID
PLIST="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
$PB -c "Add :CFBundleIdentifier string com.meowd.reader" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleDocumentTypes array" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string md" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes array" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.meowd.edit" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST" 2>/dev/null || true
$PB -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string mdedit" "$PLIST" 2>/dev/null || true

# Launch Services 등록 갱신
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP" 2>/dev/null || true
echo "✓ 앱 생성: $APP"

# 5) .md 기본 연결 (duti 있으면 자동, 없으면 수동 안내)
if command -v duti >/dev/null 2>&1; then
  duti -s com.meowd.reader md all 2>/dev/null && echo "✓ .md 기본 연결 완료" || echo "  (duti 연결 실패 — 아래 수동 방법 참고)"
else
  echo "ℹ .md 자동 연결하려면:  brew install duti  후 이 스크립트 재실행,"
  echo "  또는 수동: .md 우클릭 → '정보 가져오기' → '다음으로 열기'에서 'MeowD reader'"
  echo "           선택 → '모두 변경'."
fi

echo ""
echo "✔ 완료! .md 파일을 더블클릭해보세요."
echo "   (편집 버튼은 macOS 기본 텍스트편집기로 엽니다 = open -t)"
