
$ErrorActionPreference='Stop'
. "$PSScriptRoot/meta-test-export.ps1"
$w=New-Object Net.WebClient;$w.Encoding=[Text.Encoding]::UTF8
try{$rows=@($w.DownloadString('https://raw.githubusercontent.com/ivelinavoinova95-cell/facebook-feed-review/main/review/candidate.csv') | ConvertFrom-Csv)}finally{$w.Dispose()}
$clean=@(Convert-MetaTest762 -Rows $rows)
if($clean.Count -ne 3 -or @($clean[0].PSObject.Properties).Count -ne 10){throw 'Clean CSV schema failed'}
$passed=@('valid-three-rows-ten-columns')
function Reject-Case($name,$mutation) {
  $copy=@(($rows | ConvertTo-Json -Depth 5 | ConvertFrom-Json) | ForEach-Object { $_ })
  $bad=& $mutation $copy
  $rejected=$false
  try{$null=@(Convert-MetaTest762 -Rows @($bad))}catch{$rejected=$true}
  if(!$rejected){throw "Failed rejection: $name"}
  $name
}
$passed += Reject-Case 'missing-row' {param($r) $r[0..1]}
$passed += Reject-Case 'duplicate-id' {param($r) $r[1].id=$r[0].id;$r}
$passed += Reject-Case 'wrong-size' {param($r) $r[0].size='XL';$r}
$passed += Reject-Case 'negative-stock' {param($r) $r[0].source_quantity='-1';$r}
$passed += Reject-Case 'stock-status-mismatch' {param($r) $r[0].availability=if($r[0].availability -eq 'in stock'){'out of stock'}else{'in stock'};$r}
$passed += Reject-Case 'wrong-currency' {param($r) $r[0].price='32.00 USD';$r}
$passed += Reject-Case 'bad-variant-link' {param($r) $r[0].link=$r[0].link.Replace('cv=7173','cv=999');$r}
$passed += Reject-Case 'wrong-image-host' {param($r) $r[0].image_link='https://example.com/x.jpg';$r}
$passed += Reject-Case 'empty-title' {param($r) $r[0].title='';$r}
[pscustomobject]@{tests_passed=$passed.Count;tests=$passed;rows=@($clean | Select-Object id,size,availability,price);network_mutations=0} | ConvertTo-Json -Depth 5
