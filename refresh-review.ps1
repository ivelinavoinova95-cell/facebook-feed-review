# Preparation only: produces REVIEW data, never calls Meta or a store mutation.
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/cloudcart_variant_candidate.ps1" -SelfTest | Out-Null
$allowlistJson = Get-Content -LiteralPath "$PSScriptRoot/review-product-ids.json" -Raw | ConvertFrom-Json
# PS 5.1 can emit the JSON array as a single pipeline object; enumerate explicitly.
$allowlist = @($allowlistJson | ForEach-Object { [string]$_ })
if (!$allowlist.Count -or @($allowlist | Where-Object { [string]$_ -notmatch '^\d+$' }).Count) {
    throw 'A nonempty explicit numeric product allowlist is required'
}
$http = New-Object System.Net.WebClient
$http.Encoding = [Text.Encoding]::UTF8
try {
    $products = $http.DownloadString('https://drehizavseki.com/app/feed/blabla')
    $catalog = $http.DownloadString('https://www.drehizavseki.com/xml_feed/NDM0NzktZmFjZWJvb2s/1')
} finally { $http.Dispose() }
$allRows = @(Convert-Candidate $products $catalog)
$rows = @($allRows | Where-Object { $_.source_product_id -in $allowlist })
foreach ($id in $allowlist) {
    if (@($rows | Where-Object { $_.source_product_id -eq [string]$id }).Count -eq 0) {
        throw "Explicit review product $id missing; leaving previous output untouched"
    }
}
if (@($rows | Where-Object { !$_.review_required }).Count) { throw 'Review marker is required' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$manifest = [ordered]@{
    mode='REVIEW_ONLY'; ready_for_meta_import=$false
    checked_at_utc=[DateTime]::UtcNow.ToString('o')
    source_generation_age_known=$false
    tracking_uses_parent_product_ids=$true
    candidate_ids_match_current_tracking=$false
    allowlist=$allowlist; candidate_rows=$rows.Count
    schedule_note='Proposed 6-hour refresh; GitHub may delay or skip scheduled runs'
}
$tempCsv = Join-Path $OutputDirectory 'candidate.csv.tmp'
$tempManifest = Join-Path $OutputDirectory 'status.json.tmp'
$rows | Export-Csv -LiteralPath $tempCsv -NoTypeInformation -Encoding UTF8
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tempManifest -Encoding UTF8
# Publish local output only after all parsing and completeness checks pass.
Move-Item -LiteralPath $tempCsv -Destination (Join-Path $OutputDirectory 'candidate.csv') -Force
Move-Item -LiteralPath $tempManifest -Destination (Join-Path $OutputDirectory 'status.json') -Force
[pscustomobject]@{mode='REVIEW_ONLY';rows=$rows.Count;ready_for_meta_import=$false}
