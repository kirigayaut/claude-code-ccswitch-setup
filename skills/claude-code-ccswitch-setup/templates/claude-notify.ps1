# Claude Code Stop hook for Windows: show a notification when Claude finishes a turn.
# Windows counterpart of a macOS osascript notification
# (display notification "Claude 已完成，等你回复" with title "Claude Code" sound name "Glass").
# Uses only Windows PowerShell 5.1 built-ins, no extra modules.
# Keep this file saved as UTF-8 WITH BOM, otherwise Windows PowerShell 5.1 garbles the Chinese text.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.Text = 'Claude Code'
$icon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
$icon.BalloonTipTitle = 'Claude Code'
$icon.BalloonTipText = 'Claude 已完成，等你回复'
$icon.Visible = $true
$icon.ShowBalloonTip(5000)

# Keep the process alive long enough for Windows to show the notification, then remove the tray icon.
Start-Sleep -Seconds 6
$icon.Dispose()
