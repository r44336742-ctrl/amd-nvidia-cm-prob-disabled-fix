Get-PnpDevice -Class Display -PresentOnly | Format-List FriendlyName, Status, ConfigManagerErrorCode
Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Device Configuration" -MaxEvents 50 | Where-Object Id -eq 411 | Format-List
pnputil /enum-drivers
