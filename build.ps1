<#
  Compiles the two tiny launchers with the .NET Framework C# compiler:
    launcher.cs -> md_view.exe   (Open-with handler; embeds icon.ico)
    md_edit.cs  -> md_edit.exe   (mdedit: protocol handler -> external editor)
  csc.exe ships with Windows; no SDK needed. Re-run after editing the .cs
  files (NOT needed after editing md_view.py).
#>

$ErrorActionPreference = 'Stop'

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe (.NET Framework) 를 찾을 수 없습니다." }

$ico = Join-Path $PSScriptRoot 'icon.ico'

function Build([string]$src, [string]$out, [bool]$withIcon) {
    $args = @('/nologo', '/target:winexe', "/out:$out")
    if ($withIcon -and (Test-Path $ico)) { $args += "/win32icon:$ico" }
    $args += $src
    & $csc @args
    if ($LASTEXITCODE -ne 0) { throw "컴파일 실패: $src (exit $LASTEXITCODE)" }
    $kb = [math]::Round((Get-Item $out).Length / 1KB, 1)
    Write-Host ("[OK] {0} ({1} KB)" -f (Split-Path $out -Leaf), $kb) -ForegroundColor Green
}

Build (Join-Path $PSScriptRoot 'launcher.cs') (Join-Path $PSScriptRoot 'md_view.exe') $true
Build (Join-Path $PSScriptRoot 'md_edit.cs')  (Join-Path $PSScriptRoot 'md_edit.exe')  $false
