<#
Adds a Windows Firewall rule allowing inbound TCP on the configured port (default 9000).
Run as Administrator.
#>
param(
    [int]$Port = 9000,
    [string]$RuleName = 'AttendanceDashboard_TCP'
)

Write-Output "Adding firewall rule for TCP port $Port (rule: $RuleName)"
# if rule exists, update it
$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Output "Firewall rule $RuleName already exists. Updating..."
    Set-NetFirewallRule -DisplayName $RuleName -Action Allow
    Set-NetFirewallPortFilter -AssociatedNetFirewallRule (Get-NetFirewallRule -DisplayName $RuleName) -Protocol TCP -LocalPort $Port
} else {
    New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Any
}
Write-Output "Firewall rule applied."

# To remove the rule:
# Remove-NetFirewallRule -DisplayName $RuleName