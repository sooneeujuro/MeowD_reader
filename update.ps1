<#
  MeowD reader 업데이트 — GitHub 공개 repo에서 최신 파일을 받아 적용합니다.
  - 엔진(md_view.py) 등 변경분만 받아 덮어씀 (바이트 비교, 변경 없으면 건드리지 않음).
  - 런처(.cs)나 아이콘이 바뀐 경우에만 자동 재빌드 + 아이콘 캐시 새로고침.
  - 파일 연결(register)은 건드리지 않음 → 사용자가 지정한 기본 연결 유지.
#>

$ErrorActionPreference = 'Stop'
$base  = 'https://raw.githubusercontent.com/sooneeujuro/MeowD_reader/main'
$here  = $PSScriptRoot
$files = @('md_view.py','launcher.cs','md_edit.cs','build.ps1','register.ps1','unregister.ps1','editor.txt','icon.ico')

$tmp = Join-Path $env:TEMP ('meowd_upd_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force $tmp | Out-Null

$changed = @(); $rebuild = $false
foreach ($f in $files) {
    $dst = Join-Path $tmp $f
    try { Invoke-WebRequest "$base/$f" -OutFile $dst -UseBasicParsing }
    catch { Write-Host "  (건너뜀 $f — 다운로드 실패)" -ForegroundColor DarkGray; continue }
    $local = Join-Path $here $f
    $same = (Test-Path $local) -and ((Get-FileHash $dst).Hash -eq (Get-FileHash $local).Hash)
    if (-not $same) {
        Copy-Item $dst $local -Force
        $changed += $f
        if ($f -like '*.cs' -or $f -eq 'icon.ico') { $rebuild = $true }
    }
}
try { [System.IO.Directory]::Delete($tmp, $true) } catch {}

if ($changed.Count -eq 0) {
    Write-Host "✔ 이미 최신입니다." -ForegroundColor Green
    return
}
Write-Host ("↻ 갱신됨: " + ($changed -join ', ')) -ForegroundColor Cyan

if ($rebuild) {
    Write-Host "런처/아이콘 변경 감지 → 재빌드"
    & (Join-Path $here 'build.ps1')
    Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, int flags, System.IntPtr item1, System.IntPtr item2);
'@
    [Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Process ie4uinit.exe -ArgumentList '-show' -WindowStyle Hidden
}

Write-Host "✔ 업데이트 완료. .md 를 다시 열면 반영됩니다." -ForegroundColor Green
