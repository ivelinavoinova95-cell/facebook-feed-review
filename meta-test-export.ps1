# Isolated Meta validation export: only product 762; never modifies Meta or tracking.
function Convert-MetaTest762 {
    param([Parameter(Mandatory=$true)][object[]]$Rows)
    $expected = @{ ccv_7173='S'; ccv_7176='M'; ccv_7179='L' }
    if ($Rows.Count -ne 3) { throw 'Meta test requires all three variants of 762' }
    $seen = @{}
    foreach ($row in $Rows) {
        $id=[string]$row.id
        if (!$expected.ContainsKey($id) -or $seen.ContainsKey($id)) { throw 'Unexpected or duplicate variant ID' }
        $seen[$id]=$true
        if ($row.item_group_id -ne 'ccp_762' -or $row.source_product_id -ne '762' -or $row.size -cne $expected[$id]) { throw 'Variant grouping or size mismatch' }
        $qty=0
        if (![int]::TryParse([string]$row.source_quantity,[ref]$qty) -or $qty -lt 0) { throw 'Invalid quantity' }
        $availability=if($qty -gt 0){'in stock'}else{'out of stock'}
        if($row.availability -cne $availability){throw 'Availability does not match quantity'}
        if($row.price -notmatch '^\d+\.\d{2} EUR$' -or [decimal]::Parse(($row.price -split ' ')[0],[Globalization.CultureInfo]::InvariantCulture) -le 0){throw 'Invalid EUR price'}
        foreach($field in @('title','description','image_link','link')){
            if([string]::IsNullOrWhiteSpace([string]$row.$field)){throw "Missing required field: $field"}
        }
        if($row.condition -cne 'new'){throw 'Unexpected condition'}
        $link=$null; $image=$null
        if(![uri]::TryCreate([string]$row.link,[UriKind]::Absolute,[ref]$link) -or $link.Scheme -ne 'https' -or $link.Host -notin @('drehizavseki.com','www.drehizavseki.com') -or !$link.AbsolutePath.StartsWith('/product/')){throw 'Invalid product URL'}
        $variant=[string]$row.source_variant_id
        if($id -cne "ccv_$variant" -or $link.Query -notmatch ("(?:^|[?&])cv="+[regex]::Escape($variant)+"(?:&|$)")){throw 'Product URL variant mismatch'}
        if(![uri]::TryCreate([string]$row.image_link,[UriKind]::Absolute,[ref]$image) -or $image.Scheme -ne 'https' -or $image.Host -ne 'cdn.cloudcart.com'){throw 'Invalid image URL'}
    }
    # Emit only after every input row passed; never leak internal review/source fields.
    $Rows | Sort-Object id | Select-Object id,item_group_id,title,description,availability,condition,price,link,image_link,size
}
