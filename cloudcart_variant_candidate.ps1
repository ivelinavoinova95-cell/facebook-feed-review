<# Offline candidate only. No Meta upload, schedule, store mutation or credentials.
   AuditLive reads the TWO existing public feeds and outputs summary + code 762.
   IDs ccv_/ccp_ are PROPOSALS, not approved production identifiers.
#>
param([switch]$SelfTest, [switch]$AuditLive,
      [string]$ProductsPath, [string]$CatalogPath, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
function Read-SafeXml([string]$Text) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($Text)), $settings)
    try { $doc = New-Object System.Xml.XmlDocument; $doc.XmlResolver = $null; $doc.Load($reader); return ,$doc }
    finally { $reader.Dispose() }
}
function Child-Text($Node, [string]$Name) {
    $child = $Node.SelectSingleNode('*[local-name()="' + $Name + '"]')
    if ($null -eq $child) { return '' }; return $child.InnerText.Trim()
}
function Number-Value([string]$Text, [string]$Label) {
    $number = [decimal]0
    if ($Text -notmatch '^\d+(\.\d+)?$' -or
        -not [decimal]::TryParse($Text, [Globalization.NumberStyles]::AllowDecimalPoint,
          [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { throw "Invalid or missing $Label" }
    return $number
}
function Convert-Candidate([string]$ProductsText, [string]$CatalogText) {
    $products = Read-SafeXml $ProductsText; $catalog = Read-SafeXml $CatalogText
    $parents = @{}; $seen = @{}; $catalogSeen = @{}
    foreach ($p in $products.SelectNodes('//product')) {
        $parentId = Child-Text $p 'id'
        if (!$parentId -or $parents.ContainsKey($parentId)) { throw 'Missing or duplicate parent id' }
        $parents[$parentId] = $p
    }
    foreach ($item in $catalog.SelectNodes('//item')) {
        $parentId = Child-Text $item 'id'
        if (!$parentId -or $catalogSeen.ContainsKey($parentId)) { throw 'Missing or duplicate catalog id' }
        $catalogSeen[$parentId] = $true
        if (!$parents.ContainsKey($parentId)) { throw "Missing source parent $parentId" }
        $link = Child-Text $item 'link'; $uri = [uri]$link
        if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('drehizavseki.com','www.drehizavseki.com') -or
            !$uri.AbsolutePath.StartsWith('/product/')) { throw "Unexpected product URL for $parentId" }
        $catalogPrice = Child-Text $item 'price'
        if ($catalogPrice -notmatch '^\d+(\.\d+)?\s+EUR$') { throw "Unexpected currency for $parentId" }
        $variants = @($parents[$parentId].SelectNodes('variants/variant'))
        if (!$variants.Count) { throw "No variants for $parentId" }
        foreach ($v in $variants) {
            $vid = Child-Text $v 'id'
            if ($vid -notmatch '^\d+$' -or $seen.ContainsKey($vid)) { throw 'Missing or duplicate variant id' }
            $seen[$vid] = $true
            # CHILD quantity only: do not add a same-named XML attribute.
            $quantity = Number-Value (Child-Text $v 'quantity') "quantity for $vid"
            $price = Number-Value (Child-Text $v 'price') "price for $vid"
            if ($price -le 0) { throw "Nonpositive price for $vid" }
            $discountText = Child-Text $v 'discounted_price'; $sale = ''
            if ($discountText) {
                $discount = Number-Value $discountText "discounted price for $vid"
                if ($discount -le 0 -or $discount -gt $price) { throw "Invalid discounted price for $vid" }
                if ($discount -lt $price) { $sale = $discount.ToString('0.00',[cultureinfo]::InvariantCulture) + ' EUR' }
            }
            $size = ''; $sizeSource = ''; $color = ''; $unmapped = @()
            foreach ($p in $v.SelectNodes('parameters/parameter')) {
                $name = (Child-Text $p 'name').ToLowerInvariant(); $value = Child-Text $p 'value'
                if ($name -in @('размер','size','деца години')) {
                    if ($size) { throw "Multiple size parameters for $vid" }
                    # Preserve age-labelled clothing sizes verbatim, never infer height or age_group.
                    $size = $value; $sizeSource = $name
                } elseif ($name -in @('цвят','color','colour')) {
                    if ($color) { throw "Multiple color parameters for $vid" }; $color = $value
                } else { $unmapped += $name }
            }
            # Keep existing tracking parameters, remove stale cv, append the actual variant id.
            $builder = New-Object System.UriBuilder($uri)
            $parts = @($builder.Query.TrimStart('?').Split('&') | Where-Object {
                $_ -and [uri]::UnescapeDataString(($_ -split '=',2)[0]) -ne 'cv'
            })
            $builder.Query = (@($parts) + ('cv=' + [uri]::EscapeDataString($vid))) -join '&'
            [pscustomobject][ordered]@{
                id=('ccv_' + $vid); item_group_id=('ccp_' + $parentId)
                title=(Child-Text $item 'title'); description=(Child-Text $item 'description')
                availability=$(if ($quantity -gt 0) {'in stock'} else {'out of stock'})
                price=($price.ToString('0.00',[cultureinfo]::InvariantCulture) + ' EUR')
                sale_price=$sale; link=$builder.Uri.AbsoluteUri
                image_link=(Child-Text $item 'image_link'); condition=(Child-Text $item 'condition')
                size=$size; color=$color; size_source_parameter=$sizeSource
                source_product_id=$parentId; source_variant_id=$vid; source_sku=(Child-Text $v 'sku')
                source_quantity=$quantity; unmapped_parameters=($unmapped -join '|')
                review_required='DRAFT: ID/event matching, freshness, image, eligibility and Meta validation pending'
            }
        }
    }
}
function Test-Candidate {
    $products = '<products><product><id>762</id><variants><variant quantity="99"><id>7179</id><sku></sku><quantity>0</quantity><price>32.00</price><parameters><parameter><name>size</name><value>L</value></parameter></parameters></variant></variants></product></products>'
    $catalog = '<rss xmlns:g="http://base.google.com/ns/1.0"><channel><item><g:id>762</g:id><title>Test</title><g:link>https://www.drehizavseki.com/product/test?cv=old&amp;utm_source=facebook</g:link><g:price>32.00 EUR</g:price></item></channel></rss>'
    $rows = @(Convert-Candidate $products $catalog)
    if ($rows.Count -ne 1 -or $rows[0].availability -ne 'out of stock') { throw 'Child quantity test failed' }
    if ($rows[0].id -ne 'ccv_7179' -or $rows[0].source_sku -ne '') { throw 'Missing SKU test failed' }
    if ($rows[0].link -notmatch 'utm_source=facebook' -or $rows[0].link -notmatch 'cv=7179' -or $rows[0].link -match 'cv=old') { throw 'Variant URL test failed' }
    $caught = $false
    try { @(Convert-Candidate ($products.Replace('<quantity>0</quantity>','')) $catalog) | Out-Null } catch { $caught = $true }
    if (!$caught) { throw 'Missing quantity must fail' }
    $caught = $false
    try { @(Convert-Candidate ($products.Replace('</variants>',$products.Substring($products.IndexOf('<variant quantity='),$products.IndexOf('</variants>')-$products.IndexOf('<variant quantity=')) + '</variants>')) $catalog) | Out-Null } catch { $caught = $true }
    if (!$caught) { throw 'Duplicate variant id must fail' }
    $caught = $false
    try { @(Convert-Candidate $products ($catalog.Replace('<g:id>762</g:id>','<g:id>999</g:id>'))) | Out-Null } catch { $caught = $true }
    if (!$caught) { throw 'Missing eligible product must fail' }
    $caught = $false
    try { Read-SafeXml '<!DOCTYPE a [<!ENTITY x "test">]><a>&x;</a>' | Out-Null } catch { $caught = $true }
    if (!$caught) { throw 'DTD must be rejected' }
    $ageProducts = $products.Replace('<name>size</name><value>L</value>', '<name>деца години</name><value>4-5  години</value>')
    $ageRows = @(Convert-Candidate $ageProducts $catalog)
    if ($ageRows[0].size -cne '4-5  години' -or $ageRows[0].size_source_parameter -ne 'деца години') { throw 'Literal age label test failed' }
    $infantRows = @(Convert-Candidate ($ageProducts.Replace('4-5  години','6м.')) $catalog)
    if ($infantRows[0].size -cne '6м.') { throw 'Infant label must not be converted to years or height' }
    $unknownRows = @(Convert-Candidate ($products.Replace('<name>size</name>','<name>custom_unknown</name>')) $catalog)
    if ($unknownRows[0].size -ne '' -or $unknownRows[0].unmapped_parameters -ne 'custom_unknown') { throw 'Unknown parameter must remain unmapped' }
    [pscustomobject]@{SelfTest='PASS';Checks=10}
}
if ($SelfTest) { Test-Candidate; return }
if ($AuditLive) {
    $http = New-Object System.Net.WebClient; $http.Encoding = [Text.Encoding]::UTF8
    try {
        $source = $http.DownloadString('https://drehizavseki.com/app/feed/blabla')
        $eligible = $http.DownloadString('https://www.drehizavseki.com/xml_feed/NDM0NzktZmFjZWJvb2s/1')
    } finally { $http.Dispose() }
    $rows = @(Convert-Candidate $source $eligible)
    [pscustomobject]@{Mode='READ_ONLY_DRAFT_AUDIT';Products=@($rows.source_product_id|Select-Object -Unique).Count;
      Rows=$rows.Count;UniqueIds=@($rows.id|Select-Object -Unique).Count;
      MissingSize=@($rows|Where-Object{!$_.size}).Count;UnmappedParameters=@($rows|Where-Object{$_.unmapped_parameters}).Count;
      AgeLabelRows=@($rows|Where-Object{$_.size_source_parameter -eq 'деца години'}).Count;
      UnmappedNames=@($rows|Where-Object{$_.unmapped_parameters}|Group-Object unmapped_parameters|Select-Object Name,Count);
      Example762=@($rows|Where-Object{$_.source_product_id -eq '762'}|Select-Object id,item_group_id,size,availability,price,link)} | ConvertTo-Json -Depth 6 -Compress
    return
}
if (!$ProductsPath -or !$CatalogPath -or !$OutputPath) { throw 'Supply ProductsPath, CatalogPath and a NEW OutputPath, or use SelfTest/AuditLive.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Refusing to overwrite an existing file' }
$rows = @(Convert-Candidate ([IO.File]::ReadAllText($ProductsPath)) ([IO.File]::ReadAllText($CatalogPath)))
$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
