# Checks whether the Claude desktop app on Windows still opens a separate,
# isolated copy per --user-data-dir. Run on a clean Windows machine.
$ErrorActionPreference = 'Continue'

function Show-Claude($label) {
  Write-Host "---- $label ----"
  Get-CimInstance Win32_Process -Filter "Name='claude.exe' OR Name='Claude.exe'" |
    Where-Object { $_.CommandLine -notmatch '--type=' } |
    ForEach-Object { Write-Host ("PID {0}: {1}" -f $_.ProcessId, $_.CommandLine) }
  $all = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe' OR Name='Claude.exe'")
  Write-Host "claude.exe processes in total: $($all.Count)"
  Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object MainWindowTitle |
    ForEach-Object { Write-Host ("window PID {0}: '{1}'" -f $_.Id, $_.MainWindowTitle) }
}

function Show-Dir($path) {
  if (Test-Path $path) {
    $n = @(Get-ChildItem -Recurse -Force $path -ErrorAction SilentlyContinue).Count
    Write-Host "DIR $path : $n entries"
    Get-ChildItem -Force $path -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object { Write-Host "   $($_.Name)" }
  } else { Write-Host "DIR $path : missing" }
}

function Show-Dirs($names) {
  $pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1
  foreach ($n in $names) {
    Show-Dir "$env:APPDATA\$n"
    if ($pkg) { Show-Dir "$($pkg.FullName)\LocalCache\Roaming\$n" }
  }
}

function Stop-Claude {
  Get-Process -Name claude -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 5
}

# 1. Install
Write-Host "==== install ===="
$pkg = Get-AppxPackage -Name '*Claude*'
if (-not $pkg) {
  winget install --id Anthropic.Claude -e --accept-source-agreements --accept-package-agreements --silent 2>&1 | Select-Object -Last 15
  $pkg = Get-AppxPackage -Name '*Claude*'
}
if (-not $pkg -and -not (Test-Path "$env:LOCALAPPDATA\AnthropicClaude")) {
  $setup = "$env:RUNNER_TEMP\ClaudeSetup.exe"
  Invoke-WebRequest 'https://claude.ai/api/desktop/win32/x64/exe/latest/redirect' -OutFile $setup -UseBasicParsing
  Write-Host "downloaded $((Get-Item $setup).Length) bytes"
  Start-Process $setup -ArgumentList '--silent' -Wait
  Start-Sleep 20
  Stop-Claude
  $pkg = Get-AppxPackage -Name '*Claude*'
}
$pkg | Format-List Name, PackageFullName, Version, InstallLocation, PackageFamilyName | Out-String | Write-Host

$exe = $null
if ($pkg) { $exe = Join-Path $pkg.InstallLocation 'app\claude.exe' }
if (-not $exe -or -not (Test-Path $exe)) {
  $exe = Get-ChildItem "$env:LOCALAPPDATA\AnthropicClaude" -Recurse -Filter claude.exe -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
Write-Host "EXE: $exe"
if (-not $exe) { Write-Host "Claude not installed"; exit 1 }
(Get-Item $exe).VersionInfo | Format-List FileVersion, ProductVersion | Out-String | Write-Host
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Filter '*claude*' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "alias: $($_.FullName)" }
if ($pkg) {
  $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
  if (Test-Path $manifest) {
    Write-Host "==== manifest (Applications/Extensions) ===="
    Select-String -Path $manifest -Pattern 'Application |Executable|SupportsMultipleInstances|AppExecutionAlias|Protocol|desktop:|uap10|rescap|runFullTrust|TrustLevel' | ForEach-Object { Write-Host $_.Line.Trim() }
  }
}

Stop-Claude
$names = @('Claude', 'LanesProbeA', 'LanesProbeB', 'LanesProbeC')

# 2. Only a separate copy, nothing else running
Write-Host "==== test A: --user-data-dir copy alone ===="
Start-Process $exe -ArgumentList "--user-data-dir=`"$env:APPDATA\LanesProbeA`""
Start-Sleep 30
Show-Claude 'after A'
Show-Dirs $names

# 3. Default copy next to it
Write-Host "==== test B: default copy started next to A ===="
Start-Process $exe
Start-Sleep 30
Show-Claude 'after default'

# 4. A second separate copy while two are running
Write-Host "==== test C: --user-data-dir copy while default runs ===="
Start-Process $exe -ArgumentList "--user-data-dir=`"$env:APPDATA\LanesProbeB`""
Start-Sleep 30
Show-Claude 'after B'
Show-Dirs $names

# 5. A copy outside AppData (Lanes keeps profiles in its own folder)
Write-Host "==== test D: --user-data-dir outside AppData ===="
$outside = "$env:LOCALAPPDATA\LanesProbe\Profiles\p1\Claude"
New-Item -ItemType Directory -Force $outside | Out-Null
Start-Process $exe -ArgumentList "--user-data-dir=`"$outside`""
Start-Sleep 30
Show-Claude 'after D'
Show-Dir $outside

# 6. Window and taskbar identity of each window
Write-Host "==== AppUserModelID per window ===="
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class Aumid {
  [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore ps);
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore { int GetCount(out uint c); int GetAt(uint i, out PropertyKey k); int GetValue(ref PropertyKey k, out PropVariant v); int SetValue(ref PropertyKey k, ref PropVariant v); int Commit(); }
  [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PropertyKey { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Explicit)] struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
  public static string Get(IntPtr hwnd) {
    var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    IPropertyStore ps; if (SHGetPropertyStoreForWindow(hwnd, ref iid, out ps) != 0) return "(no store)";
    var key = new PropertyKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    PropVariant v; ps.GetValue(ref key, out v);
    return v.vt == 31 ? Marshal.PtrToStringUni(v.p) : "(unset, vt=" + v.vt + ")";
  }
}
'@
Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } |
  ForEach-Object { Write-Host ("PID {0} '{1}' AUMID={2}" -f $_.Id, $_.MainWindowTitle, [Aumid]::Get($_.MainWindowHandle)) }

Stop-Claude
Write-Host "==== done ===="
