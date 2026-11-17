# ccs-query.ps1 — read-only SQLite query for the CCSwitch database on Windows,
# using the built-in C:\Windows\System32\winsqlite3.dll (no sqlite3.exe or Python needed).
# Opens the DB with SQLITE_OPEN_READONLY and masks secret-looking values before printing.
#
# Usage (Windows PowerShell 5.1):
#   .\ccs-query.ps1 -Sql "SELECT id, name, is_current FROM providers WHERE app_type='claude'"
#   .\ccs-query.ps1 -Sql "PRAGMA journal_mode" -DbPath C:\path\to\other.db
#
# Notes:
#   - Exactly one SQL statement per call.
#   - JSON1 functions (json_extract, ...) are available in winsqlite3 (tested: SQLite 3.43.2).
#   - proxy_request_logs.created_at is Unix seconds; compare integers directly.
#   - Masking is best-effort (by key/column name, plus sk-... patterns). Base URLs are NOT masked.
#     Review the output before pasting it anywhere public.
param(
  [Parameter(Mandatory = $true)][string]$Sql,
  [string]$DbPath = "$env:USERPROFILE\.cc-switch\cc-switch.db"
)

if (-not ([System.Management.Automation.PSTypeName]'WinSqliteR').Type) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinSqliteR {
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_busy_timeout(IntPtr db, int ms);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_prepare16_v2(IntPtr db, IntPtr sql, int nBytes, out IntPtr stmt, out IntPtr tail);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_column_count(IntPtr stmt);
  [DllImport("winsqlite3.dll")] public static extern IntPtr sqlite3_column_name16(IntPtr stmt, int i);
  [DllImport("winsqlite3.dll")] public static extern IntPtr sqlite3_column_text16(IntPtr stmt, int i);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll")] public static extern IntPtr sqlite3_errmsg16(IntPtr db);
}
'@
}

$secretName = '(?i)(token|api_?key|secret|password|auth)'
$SQLITE_OK = 0; $SQLITE_ROW = 100; $SQLITE_DONE = 101
$SQLITE_OPEN_READONLY = 1

function ErrMsg($db) { [Runtime.InteropServices.Marshal]::PtrToStringUni([WinSqliteR]::sqlite3_errmsg16($db)) }

$db = [IntPtr]::Zero
$rc = [WinSqliteR]::sqlite3_open_v2([Text.Encoding]::UTF8.GetBytes($DbPath + [char]0), [ref]$db, $SQLITE_OPEN_READONLY, [IntPtr]::Zero)
if ($rc -ne $SQLITE_OK) { throw "open failed rc=$rc ($DbPath)" }
try {
  [void][WinSqliteR]::sqlite3_busy_timeout($db, 10000)   # CCSwitch may be writing (journal_mode=delete)

  # Marshal the SQL ourselves so the returned "tail" pointer can be read: anything left after the first
  # statement (other than whitespace/semicolons) means the caller passed more than one statement.
  $sqlPtr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Sql)
  try {
    $stmt = [IntPtr]::Zero; $tail = [IntPtr]::Zero
    $rc = [WinSqliteR]::sqlite3_prepare16_v2($db, $sqlPtr, -1, [ref]$stmt, [ref]$tail)
    if ($rc -ne $SQLITE_OK) { throw "prepare failed: $(ErrMsg $db)" }
    $rest = if ($tail -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::PtrToStringUni($tail) } else { '' }
  } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($sqlPtr) }
  if ($stmt -eq [IntPtr]::Zero) { throw "empty SQL" }
  if ($rest -match '[^\s;]') { [void][WinSqliteR]::sqlite3_finalize($stmt); throw "only one SQL statement per call; not run: $rest" }

  $n = [WinSqliteR]::sqlite3_column_count($stmt)
  $row = 0
  $sb = New-Object Text.StringBuilder
  try {
    while ($true) {
      $rc = [WinSqliteR]::sqlite3_step($stmt)
      if ($rc -eq $SQLITE_DONE) { break }
      if ($rc -ne $SQLITE_ROW) { throw "step failed rc=$rc : $(ErrMsg $db)" }
      $row++
      [void]$sb.AppendLine("===== row $row =====")
      for ($i = 0; $i -lt $n; $i++) {
        $name = [Runtime.InteropServices.Marshal]::PtrToStringUni([WinSqliteR]::sqlite3_column_name16($stmt, $i))
        $p = [WinSqliteR]::sqlite3_column_text16($stmt, $i)
        $val = if ($p -eq [IntPtr]::Zero) { '<NULL>' } else { [Runtime.InteropServices.Marshal]::PtrToStringUni($p) }
        # A column whose own name looks secret (e.g. "... AS auth_token") is masked as a whole.
        if ($name -match $secretName -and $val -ne '<NULL>' -and $val -ne 'PROXY_MANAGED' -and $val -ne '') { $val = '***MASKED***' }
        [void]$sb.AppendLine("$name = $val")
      }
    }
  } finally { [void][WinSqliteR]::sqlite3_finalize($stmt) }

  $out = $sb.ToString()
  # Mask JSON string values whose key looks secret, e.g. "ANTHROPIC_AUTH_TOKEN":"..."
  $out = [regex]::Replace($out, '(?i)("[^"]*(token|api_?key|secret|password|auth)[^"]*"\s*:\s*")((?:[^"\\]|\\.)*)(")', {
    param($m) if ($m.Groups[3].Value -eq 'PROXY_MANAGED' -or $m.Groups[3].Value -eq '') { $m.Value } else { $m.Groups[1].Value + '***MASKED***' + $m.Groups[4].Value } })
  # Mask long sk-... style keys anywhere, just in case
  $out = [regex]::Replace($out, '(?i)\b(sk-[A-Za-z0-9_\-]{6})[A-Za-z0-9_\-]{10,}', '$1***MASKED***')
  $out
  "($row rows)"
} finally { [void][WinSqliteR]::sqlite3_close($db) }
