## Symptoms
- AMD Software (Adrenalin) shows: "The version of AMD Software that you have launched is not compatible with your currently installed AMD graphics driver" (AMD KB pa-300)
- Installing/repairing AMD Software returns Error 207: "AMD Software installation completed successfully but Windows detected a potential issue with your graphics device"
- Windows Settings > Display > Project shows: "Your PC can't project to another screen. Try reinstalling the driver or using a different video card."
- Task Manager > Performance no longer lists any GPU entry at all
- Both the integrated AMD GPU and the discrete NVIDIA GPU show Status: Error / ConfigManagerErrorCode: CM_PROB_DISABLED in `Get-PnpDevice -Class Display -PresentOnly`
- Typically triggered after a long uptime session followed by a sudden GPU-decode-heavy workload (e.g. video streaming in a browser) causing a display driver crash, especially common on MUX-less laptops where the discrete GPU's output is routed through the integrated GPU.

## Root cause
Use Event Viewer or this command to confirm:
```powershell
Get-WinEvent -LogName "Microsoft-Windows-Kernel-PnP/Device Configuration" -MaxEvents 50 | Where-Object Id -eq 411 | Format-List
```
Event ID 411 ("Device PCI\VEN_xxxx... had a problem starting", with a Driver Name like oemXX.inf) means Windows attempted to load a corrupted leftover driver package from the Driver Store at every boot, failed, and defensively disabled the device (CM_PROB_DISABLED) to prevent a boot loop. `Enable-PnpDevice` will appear to work but the device reverts to disabled on the next reboot, because the same broken driver gets reloaded.

## Fix
1. Identify the broken driver package name from the Event 411 message (e.g. oem68.inf).
2. Remove it from the Driver Store:
```powershell
pnputil /enum-drivers
pnputil /delete-driver oemXX.inf /uninstall /force
```
3. If removal fails or the device still won't re-enable, do a full clean in Safe Mode with Display Driver Uninstaller (DDU, https://www.wagnardsoft.com/), running it once per vendor (AMD, then NVIDIA on reboot).
4. Reinstall the official driver from the GPU vendor's site, enabling the "Factory Reset" option in the installer if offered.
5. Reboot and confirm with:
```powershell
Get-PnpDevice -Class Display -PresentOnly | Format-List FriendlyName, Status, ConfigManagerErrorCode
```
Both adapters should show Status: OK / ConfigManagerErrorCode: CM_PROB_NONE.

## Prevention
Windows Update can silently replace a correctly installed AMD/NVIDIA driver with a generic mismatched one, which is what frequently triggers this failure in the first place. To exclude driver updates from Windows Update quality updates:
```powershell
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord
```
Update GPU drivers manually via AMD Software / NVIDIA App instead.
