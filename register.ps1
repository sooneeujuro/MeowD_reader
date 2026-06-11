<#
  Registers md_view.exe as an Explorer "Open with" handler for .md files.

  - Per-user only (HKCU); NO admin rights needed; fully reversible (unregister.ps1).
  - Registers the EXE both as a ProgID and as an Applications\ entry with a
    friendly name + SupportedTypes, so it shows up in the right-click
    "연결 프로그램 → 다른 앱 선택" list as "Markdown 뷰어".
  - Clears the broken default that pointed .md at a bare .py (which Windows
    cannot launch), so the stale association stops swallowing double-clicks.
#>

$ErrorActionPreference = 'Stop'

$ProgId      = 'MarkdownViewer.md'
$DisplayName = 'Markdown 뷰어'
$Exe         = Join-Path $PSScriptRoot 'md_view.exe'
$EditExe     = Join-Path $PSScriptRoot 'md_edit.exe'

if (-not (Test-Path $Exe)) {
    throw "md_view.exe 가 없습니다. 먼저 build.ps1 로 컴파일하세요: $Exe"
}

$Command = '"{0}" "%1"' -f $Exe

# 1) ProgID: friendly menu label + open command pointing straight at the exe.
$progKey = "HKCU:\Software\Classes\$ProgId"
New-Item -Path "$progKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $progKey                      -Name '(default)' -Value $DisplayName
Set-ItemProperty -Path "$progKey\shell\open\command" -Name '(default)' -Value $Command
New-Item -Path "$progKey\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$progKey\DefaultIcon" -Name '(default)' -Value "$Exe,0"

# 2) Applications\md_view.exe — what makes "다른 앱 선택" list it by a nice name.
$appKey = 'HKCU:\Software\Classes\Applications\md_view.exe'
New-Item -Path "$appKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $appKey -Name 'FriendlyAppName' -Value $DisplayName
Set-ItemProperty -Path "$appKey\shell\open\command" -Name '(default)' -Value $Command
New-Item -Path "$appKey\SupportedTypes" -Force | Out-Null
New-ItemProperty -Path "$appKey\SupportedTypes" -Name '.md' -PropertyType String -Value '' -Force | Out-Null

# 3) Offer the ProgID under .md's Open-with list (without forcing default).
$owp = 'HKCU:\Software\Classes\.md\OpenWithProgids'
New-Item -Path $owp -Force | Out-Null
New-ItemProperty -Path $owp -Name $ProgId -PropertyType String -Value '' -Force | Out-Null

# 3b) Register the "mdedit:" custom protocol so the viewer's ✎ 편집 button
#     can hand the file off to an external editor (handled by md_edit.exe).
if (Test-Path $EditExe) {
    $proto = 'HKCU:\Software\Classes\mdedit'
    New-Item -Path "$proto\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $proto -Name '(default)' -Value 'URL:MD Edit Protocol'
    New-ItemProperty -Path $proto -Name 'URL Protocol' -PropertyType String -Value '' -Force | Out-Null
    Set-ItemProperty -Path "$proto\shell\open\command" -Name '(default)' -Value ('"{0}" "%1"' -f $EditExe)
} else {
    Write-Host "[i] md_edit.exe 없음 — '편집' 버튼은 build.ps1 재실행 후 동작합니다." -ForegroundColor DarkGray
}

# 4) Clean up the broken state from the earlier .py attempt.
#    a) the stale ProgID that pointed at a bare script
Remove-Item -Path 'HKCU:\Software\Classes\Applications\md_view.py' -Recurse -Force -ErrorAction SilentlyContinue
#    b) the protected UserChoice default (may be ACL-locked; ignore if so)
try {
    Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\UserChoice' -Force -ErrorAction Stop
    Write-Host "[i] 깨진 .md 기본값(UserChoice) 제거됨." -ForegroundColor DarkGray
} catch {
    Write-Host "[i] UserChoice는 보호되어 자동 삭제 불가 — 아래 안내대로 한 번만 직접 지정하면 됩니다." -ForegroundColor DarkGray
}

# 5) Nudge Explorer to reload associations.
Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, int flags, System.IntPtr item1, System.IntPtr item2);
'@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)  # SHCNE_ASSOCCHANGED

Write-Host ""
Write-Host "[OK] '$DisplayName' (exe) 등록 완료." -ForegroundColor Green
Write-Host "      실행파일: $Exe"
Write-Host ""
Write-Host "다음 한 번만:" -ForegroundColor Cyan
Write-Host "  .md 우클릭 → 연결 프로그램 → 다른 앱 선택 → 'Markdown 뷰어'"
Write-Host "  (목록에 없으면 '이 PC에서 다른 앱 찾기' → $Exe 선택)"
Write-Host "  '항상 이 앱으로 열기' 체크하면 이후 더블클릭으로 바로 열립니다."
Write-Host ""
Write-Host "✎ 편집 버튼: 누르면 외부 편집기로 열림 (기본 메모장; editor.txt 로 변경)." -ForegroundColor Cyan
