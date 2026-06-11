<#
  Removes everything register.ps1 added. Per-user (HKCU), no admin needed.
  Does NOT touch UserChoice (that is whatever you last picked in Explorer).
#>

$ErrorActionPreference = 'SilentlyContinue'

$ProgId = 'MarkdownViewer.md'

Remove-Item -Path "HKCU:\Software\Classes\$ProgId" -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Classes\Applications\md_view.exe' -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Classes\mdedit' -Recurse -Force
Remove-ItemProperty -Path 'HKCU:\Software\Classes\.md\OpenWithProgids' -Name $ProgId -Force

Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, int flags, System.IntPtr item1, System.IntPtr item2);
'@
[Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host "[OK] 'Markdown 뷰어' 등록 해제 완료." -ForegroundColor Yellow
