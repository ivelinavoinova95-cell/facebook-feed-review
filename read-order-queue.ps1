param([string]$Since='2026-10-09 00:00:00')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Text.UTF8Encoding]::new($false)
$work=Join-Path $env:TEMP ('dzv-order-queue-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
function Read-CloudCart([string]$Query) {
 if($Query -match '(?i)\bmutation\b'){throw 'Read-only queries only'}
 $file=Join-Path $work 'query.graphql'
 [IO.File]::WriteAllText($file,$Query,[Text.UTF8Encoding]::new($false))
 $result=(cloudcart.cmd app execute --store 'drehizavseki.com' --file $file --json --compact-output | Out-String | ConvertFrom-Json)
 if($result.errors -or !$result.data){throw 'CloudCart query failed'}
 return $result.data
}
$sinceLiteral=ConvertTo-Json $Since -Compress
$orders=@();$cursor=$null;$seen=@{};$pages=0
do {
 $after=if($cursor){',after:'+(ConvertTo-Json $cursor -Compress)}else{''}
 $query='{ orders(status:{operator:is,value:"pending"},archived:false,draft:false,date_added:{operator:gte,value:'+$sinceLiteral+'},first:10'+$after+') { pageInfo { hasNextPage endCursor } edges { node { id timestamps { added } statuses { status fulfillment } payments { provider status } } } } }'
 $data=Read-CloudCart $query
 foreach($edge in $data.orders.edges){$o=$edge.node;if($seen.ContainsKey($o.id)){throw 'Duplicate order during pagination'};$seen[$o.id]=$true;$orders+=$o}
 $pages++
 if($data.orders.pageInfo.hasNextPage){$next=$data.orders.pageInfo.endCursor;if(!$next -or $next -eq $cursor){throw 'Incomplete pagination'};$cursor=$next}
} while($data.orders.pageInfo.hasNextPage)
$rows=@();$trackingFailures=0
foreach($o in ($orders | Sort-Object {$_.timestamps.added})) {
 $category='manual_review';$tracking=@();$trackingAvailable=$null
 $failed=@($o.payments | Where-Object {$_.status -eq 'failed'}).Count -gt 0
 if($failed){$category='payment_review'}
 elseif($o.statuses.fulfillment -eq 'not_fulfilled'){$category='packing_review'}
 elseif($o.statuses.fulfillment -eq 'fulfilled') {
  $category='shipping_payment_review'
  try {
   $t=Read-CloudCart ('{ orderShipmentsTracking(orderId:"'+$o.id+'") { supported actualStatus { name date } } }')
   $tracking=@($t.orderShipmentsTracking | ForEach-Object {[pscustomobject]@{supported=$_.supported;status=$_.actualStatus.name;eventDate=$_.actualStatus.date}})
   $trackingAvailable=($tracking.Count -gt 0 -and @($tracking | Where-Object { !$_.supported -or [string]::IsNullOrWhiteSpace($_.status) }).Count -eq 0)
  } catch {$trackingFailures++;$trackingAvailable=$false}
 }
 $rows += [pscustomobject]@{orderId=$o.id;createdAt=$o.timestamps.added;category=$category;fulfillment=$o.statuses.fulfillment;payments=@($o.payments | Select-Object provider,status);trackingAvailable=$trackingAvailable;trackingNeedsReview=($category -eq 'shipping_payment_review' -and (!$trackingAvailable -or @($tracking | Where-Object {[string]::IsNullOrWhiteSpace($_.eventDate)}).Count -gt 0));tracking=$tracking}
 Write-Host ('Checked order '+$o.id)
}
$report=[pscustomobject]@{
 store='drehizavseki.com';mode='READ_ONLY';checkedAtUtc=[DateTime]::UtcNow.ToString('o');since=$Since
 pendingOrders=$rows.Count;pages=$pages;trackingFailures=$trackingFailures
 trackingReviewCount=@($rows | Where-Object {$_.trackingNeedsReview}).Count
 completeOrderPagination=$true;trackingQueriesSucceeded=($trackingFailures -eq 0)
 counts=@($rows | Group-Object category | ForEach-Object {[pscustomobject]@{category=$_.Name;count=$_.Count}})
 limitations=@('Carrier labels do not prove payment settlement.','Missing event dates do not prove fresh tracking.','No messages, orders, payments or shipping labels are changed.')
 orders=$rows
}
$output=Join-Path $work 'report.json'
[IO.File]::WriteAllText($output,($report | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
$report | Select-Object store,mode,checkedAtUtc,pendingOrders,pages,trackingFailures,trackingReviewCount,counts | ConvertTo-Json -Depth 6
Write-Host ('Report: '+$output)
