<!-- Version 1.0.2 -->

# LansweeperPlatform
A PowerShell module for interacting with the Lansweeper Platform through the Data API.

## Getting Started
1. Obtain a personal access token as described in the Lansweeper Data API [Quickstart Guide](https://developer.lansweeper.com/docs/data-api/get-started/quickstart#personal-access-token-pat)
2. Use either:
   ```PowerShell
   Get-lspSite -Token "..."
   Connect-lspSite -Name "<your site name>"
   ```
   or
   ```PowerShell
   Connect-lspSite -Name "<your site name>" -Token "..."
   ```
   You only need to enter the token once per session.
3. Verify that the count matches the number of assets on your Lansweeper site:
   ```PowerShell
   (Get-lspAsset).Count
   ```
4. Most cmdlets are documented through examples. Use either:
   ```PowerShell
   Get-Help -Name "<cmdlet name>" -Full
   ```
   or
   ```PowerShell
   Get-Help -Name "<cmdlet name>" -Examples
   ```
5. Start exploring the module:
   ```PowerShell
   Get-lspAsset
   Get-Command -Module "LansweeperPlatform"
   Get-Help -Name "Set-lspAsset" -Full
   ```
