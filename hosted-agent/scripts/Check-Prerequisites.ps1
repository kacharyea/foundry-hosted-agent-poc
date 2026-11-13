$ErrorActionPreference = 'Stop'

$checks = [ordered]@{}
$checks['dotnet'] = try { (dotnet --version) -match '^10\.' } catch { $false }
$checks['az'] = try { [version]((az version | ConvertFrom-Json).'azure-cli') -ge [version]'2.80.0' } catch { $false }
$checks['azd'] = try { [version]((azd version) -replace '^azd version ', '').Split(' ')[0] -ge [version]'1.27.1' } catch { $false }
$checks['Azure context'] = try { [bool](az account show --query id -o tsv) } catch { $false }

$checks.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{ Prerequisite = $_.Key; Ready = [bool]$_.Value }
} | Format-Table -AutoSize

if ($checks.Values -contains $false) {
    throw 'One or more prerequisites are missing. Docker is optional because azd uses an ACR remote build.'
}
