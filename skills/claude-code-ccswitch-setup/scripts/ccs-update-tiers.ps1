# ccs-update-tiers.ps1 — set the three hidden tier-mapping env keys of ONE CCSwitch provider (Windows).
# Only run this after the user has agreed to the exact change (table, row, keys, old -> new).
#
# What it does:
#   1. Backs up the DB with VACUUM INTO to <db dir>\backups\db_backup_before_tier_mapping_<timestamp>.db
#   2. In one IMMEDIATE transaction, json_set()s ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL in
#      providers.settings_config for the given provider id. The UPDATE is guarded by the CURRENT value of the
#      SONNET key (and optionally the provider name). All values are bound as parameters, never spliced into SQL.
#   3. Commits only if exactly 1 row changed; otherwise rolls back and changes nothing.
# Everything else in settings_config (token, base URL, ANTHROPIC_MODEL, ...) is left untouched.
#
# Usage (Windows PowerShell 5.1):
#   .\ccs-update-tiers.ps1 -ProviderId <provider id from ccs-query.ps1> -Haiku claude-haiku-5-5 -Sonnet claude-sonnet-5 `
#       -Opus claude-opus-5-5 -ExpectedCurrentSonnet "<current SONNET value>" [-ExpectedName "<provider name>"]
#   If the SONNET key does not exist yet, pass -ExpectedCurrentSonnet "" (matches a missing key).
# Then verify with ccs-query.ps1.
param(
  [Parameter(Mandatory = $true)][string]$ProviderId,
  [Parameter(Mandatory = $true)][string]$Haiku,
  [Parameter(Mandatory = $true)][string]$Sonnet,
  [Parameter(Mandatory = $true)][string]$Opus,
  [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExpectedCurrentSonnet,
  [string]$ExpectedName,
  [string]$DbPath = "$env:USERPROFILE\.cc-switch\cc-switch.db"
)

if (-not ([System.Management.Automation.PSTypeName]'WinSqliteU').Type) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinSqliteU {
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_busy_timeout(IntPtr db, int ms);
  [DllImport("winsqlite3.dll", CharSet=CharSet.Unicode)] public static extern int sqlite3_prepare16_v2(IntPtr db, string sql, int nBytes, out IntPtr stmt, IntPtr tail);
  [DllImport("winsqlite3.dll", CharSet=CharSet.Unicode)] public static extern int sqlite3_bind_text16(IntPtr stmt, int idx, string val, int nBytes, IntPtr destructor);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_changes(IntPtr db);
  [DllImport("winsqlite3.dll")] public static extern IntPtr sqlite3_errmsg16(IntPtr db);
  [DllImport("winsqlite3.dll")] public static extern int sqlite3_close(IntPtr db);
}
'@
}

$SQLITE_OK = 0; $SQLITE_DONE = 101
$SQLITE_TRANSIENT = [IntPtr](-1)   # make SQLite copy bound strings

function ErrMsg($db) { [Runtime.InteropServices.Marshal]::PtrToStringUni([WinSqliteU]::sqlite3_errmsg16($db)) }

# Run one statement with optional ?1..?N text parameters. Returns sqlite3_changes() afterwards.
function Run($db, [string]$sql, [string[]]$params = @()) {
  $stmt = [IntPtr]::Zero
  $rc = [WinSqliteU]::sqlite3_prepare16_v2($db, $sql, -1, [ref]$stmt, [IntPtr]::Zero)
  if ($rc -ne $SQLITE_OK) { throw "prepare failed rc=$rc : $(ErrMsg $db)" }
  try {
    for ($i = 0; $i -lt $params.Count; $i++) {
      $rc = [WinSqliteU]::sqlite3_bind_text16($stmt, $i + 1, $params[$i], -1, $SQLITE_TRANSIENT)
      if ($rc -ne $SQLITE_OK) { throw "bind failed rc=$rc : $(ErrMsg $db)" }
    }
    $rc = [WinSqliteU]::sqlite3_step($stmt)
    if ($rc -ne $SQLITE_DONE) { throw "step failed rc=$rc : $(ErrMsg $db)" }
  } finally { [void][WinSqliteU]::sqlite3_finalize($stmt) }
  [WinSqliteU]::sqlite3_changes($db)
}

$backupDir = Join-Path (Split-Path $DbPath -Parent) 'backups'
New-Item -ItemType Directory -Force $backupDir | Out-Null
$stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$bak = Join-Path $backupDir ("db_backup_before_tier_mapping_{0}.db" -f $stamp)
$k = 1
while (Test-Path -LiteralPath $bak) { $bak = Join-Path $backupDir ("db_backup_before_tier_mapping_{0}_{1}.db" -f $stamp, $k); $k++ }

$SQLITE_OPEN_READWRITE = 2
$db = [IntPtr]::Zero
$rc = [WinSqliteU]::sqlite3_open_v2([Text.Encoding]::UTF8.GetBytes($DbPath + [char]0), [ref]$db, $SQLITE_OPEN_READWRITE, [IntPtr]::Zero)
if ($rc -ne $SQLITE_OK) { throw "open failed rc=$rc ($DbPath)" }
try {
  [void][WinSqliteU]::sqlite3_busy_timeout($db, 10000)
  [void](Run $db 'VACUUM INTO ?1' @($bak))
  "backup: $bak ($((Get-Item -LiteralPath $bak).Length) bytes)"

  $sql = @'
UPDATE providers
SET settings_config = json_set(settings_config,
      '$.env.ANTHROPIC_DEFAULT_HAIKU_MODEL',  ?1,
      '$.env.ANTHROPIC_DEFAULT_SONNET_MODEL', ?2,
      '$.env.ANTHROPIC_DEFAULT_OPUS_MODEL',   ?3)
WHERE id = ?4 AND app_type = 'claude'
  AND COALESCE(json_extract(settings_config, '$.env.ANTHROPIC_DEFAULT_SONNET_MODEL'), '') = ?5
  AND (?6 = '' OR name = ?6)
'@
  $nameGuard = if ($PSBoundParameters.ContainsKey('ExpectedName')) { $ExpectedName } else { '' }

  [void](Run $db 'BEGIN IMMEDIATE')
  try {
    $n = Run $db $sql @($Haiku, $Sonnet, $Opus, $ProviderId, $ExpectedCurrentSonnet, $nameGuard)
  } catch { [void](Run $db 'ROLLBACK'); throw }
  if ($n -eq 1) { [void](Run $db 'COMMIT'); "updated rows: 1 (committed)" }
  else { [void](Run $db 'ROLLBACK'); "ABORT: expected 1 row, matched $n. Rolled back, nothing changed." }
} finally { [void][WinSqliteU]::sqlite3_close($db) }
