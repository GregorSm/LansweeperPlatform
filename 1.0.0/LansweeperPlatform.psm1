function Add-lspRelation
{
<#
    .SYNOPSIS
        New Lansweeper Platform Relation

    .EXAMPLE
        PS>Get-lspAsset | Where-Object {$_.Domain -eq "MYVMWAREVM"} | Add-lspRelation -Name "Depends On" -Child (Get-lspAsset -Name "esx1", "esx2", "esx3")

        This example adds a set of relationships describing virtual machine dependencies on virtualization hosts.
        First, the virtual machines are selected by a relevant criterion. The custom "Depends On" relationship is then added to all selected virtual machines in bulk.
        Because three hosts are specified, each virtual machine receives three "Depends On" relationship links.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)]  [PSTypeName("LansweeperPlatform.Asset")] $Parent,
           [Parameter(Mandatory = $True, ValueFromPipeline = $False)] [string] $Name,
           [Parameter(Mandatory = $True, ValueFromPipeline = $False)] [PSTypeName("LansweeperPlatform.Asset")] $Child)

    begin
    {
        $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        createRelation
        (
            relation:
            {
                parentKey: "PARENTKEY"
                childKey: "CHILDKEY"
                relationTypeKey: "RELATIONTYPEKEY"
            }
            kind: ASSET_ASSET
        )
        {
            id
        }
    }
}
"@

        if (-not $Script:SiteId)
        {
            throw "Run Connect-lspSite first."
        }
        $TypeKey = (Get-lspRelation | Where-Object {$_.Name -eq $Name}).TypeKey
        $Id = @()
    }
    process
    {
        foreach ($C in $Child)
        {
            if (-not ($Parent.Relations | Where-Object {$_.isParent -and $_.typeKey -eq $TypeKey -and $_.childAssetKey -eq $C.Key}))
            {
                $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("PARENTKEY", $Parent.Key).Replace("CHILDKEY", $C.Key).Replace("RELATIONTYPEKEY", $TypeKey)
                $Id += $Result.data.site.createRelation.id
            }
        }
    }
    end
    {
        Get-lspAsset | Get-lspRelation | Where-Object {$_.Id -in $Id}
    }
}

function Connect-lspSite
{
<#
    .SYNOPSIS
        Connect Lansweeper Platform Site

    .DESCRIPTION
        This cmdlet establishes a connection to a Lansweeper Platform site and is typically the first cmdlet called in a session.
        To retrieve a site name, use Get-lspSite first.
        The Token parameter only needs to be specified once per session.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True,  ValueFromPipeline = $False)] [string] $Name,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string] $Token)

    if (-not $Script:Token)
    {
        if ($Token)
        {
            $Script:Token = $Token
        }
        else
        {
            throw "Parameter 'Token' is required."
        }
    }
    $Site = Get-lspSite | Where-Object {$_.Name -eq $Name} | Select-Object -First 1
    if (-not $Site)
    {
        throw "Site '$Name' was not found."
    }
    $Script:SiteId = $Site.Id
}

function ConvertTo-Hashtable
{
    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)] [string[]] $Fields)

    begin
    {
        $CustomFieldHT = Get-lspCustomField | Group-Object -Property "Name" -AsHashTable -AsString
        $Result = @{}
    }
    process
    {
        foreach ($Field in $Fields)
        {
            $Key, $Value = $Field.Split("=")
            $Part = $Key.Split(".").Trim()
            $Current = $Result
            for ($I = 0; $I -lt $Part.Count - 1; $I ++)
            {
                if ($Part[$I] -eq "fields")
                {
                    if (-not $Current.ContainsKey("fields"))
                    {
                        $Current.fields = @()
                    }
                    $Current.fields += @{fieldKey = $CustomFieldHT[$Part[$I + 1]].Key; value = $Value.Trim()}
                    $Current = $Null
                    break
                }
                if (-not $Current.ContainsKey($Part[$I]))
                {
                    $Current[$Part[$I]] = @{}
                }
                $Current = $Current[$Part[$I]]
            }
            if ($Current)
            {
                if ($Part[-1] -in "ipAddress", "barCode", "branchOffice", "building", "comment", "department", "dnsName", "lastFullBackup", "lastFullImage", "lastPatched", "orderNumber")
                {
                    $Current[$Part[-1]] = $Value.Trim()
                }
                else
                {
                    $Current[$Part[-1]] = @{value = $Value.Trim()}
                }
            }
        }
    }
    end
    {
        $Result
    }
}

function Get-lspAsset
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Asset

    .EXAMPLE
        PS>Get-lspAsset -Fields "recognitionInfo.osMetadata.fullName" | Sort-Object -Property "Name" | Format-Table -Property "Key", "Name", "Type", "Domain", "IPAddress", "MAC", "Manufacturer", "Model", "SerialNumber", "StateName", "LastSeen", "OsMetadataFullName" -AutoSize

        This cmdlet retrieves a default set of asset fields corresponding to the columns shown in the default All Assets site view.
        To retrieve additional fields, use the Fields parameter. The Lansweeper Data API documentation refers to each full field name as a path.

        For more information about determining paths for asset objects, see the Path-building section:
        https://developer.lansweeper.com/docs/data-api/guides/getting-data#path-building

    .EXAMPLE
        PS>$Confidentiality = @{Name = "C-Confidentiality"; Expression = {($_.CustomFields | Where-Object {$_.Name -eq "C-Confidentiality"}).Value}}
        PS>$Integrity = @{Name = "I-Integrity"; Expression = {($_.CustomFields | Where-Object {$_.Name -eq "I-Integrity"}).Value}}
        PS>$Availability = @{Name = "A-Availability"; Expression = {($_.CustomFields | Where-Object {$_.Name -eq "A-Availability"}).Value}}
        PS>Get-lspAsset -Name "dc1", "dc2" -Fields "assetCustom.building", "assetCustom.department" | Format-Table -Property "Name", "Building", "Department", $Confidentiality, $Integrity, $Availability -AutoSize

        This example assumes that custom fields named C-Confidentiality, I-Integrity, and A-Availability have been added to your Lansweeper site to support the CIA triad.
        This example retrieves the Building and Department asset fields, along with the C-Confidentiality, I-Integrity, and A-Availability custom fields, for two domain controllers.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Name = "*",
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Fields)

    $CoreFields = "assetBasicInfo.name", "assetBasicInfo.type", "assetBasicInfo.domain", "assetBasicInfo.ipAddress", "assetBasicInfo.mac", "assetCustom.manufacturer", "assetCustom.model", "assetCustom.serialNumber", "assetCustom.stateName", "assetBasicInfo.lastSeen",
                  "assetCustom.fields.fieldKey", "assetCustom.fields.name", "assetCustom.fields.value", "relations.id", "relations.typeKey", "relations.name", "relations.parentAssetKey", "relations.childAssetKey", "relations.isParent", "relations.startDate", "relations.endDate", "relations.lastChanged", "relations.comment"
    $GraphQL =
@"
query
{
    site(id: "$Script:SiteId")
    {
        assetResources
        (
            assetPagination: {cursor: "CURSOR", limit: 500, page: PAGE}
            fields:
            [
                $($Fields + $CoreFields | ForEach-Object {"""$_"" "})
            ]
        )
        {
            total
            pagination
            {
                limit
                current
                next
                page
            }
            items
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    $CoreFields = $CoreFields | Where-Object {-not ($_ -eq "assetBasicInfo.lastSeen" -or $_ -like "assetCustom.fields.*" -or $_ -like "relations.*")}
    $Page = "FIRST"
    $Cursor = ""
    do
    {
        $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("CURSOR", $Cursor).Replace("PAGE", $Page)
        $Items = @()
        foreach ($N in $Name)
        {
            $Items += $Result.data.site.assetResources.items | Where-Object {$_.assetBasicInfo.name -like $N}
        }
        foreach ($Item in $Items)
        {
            $FieldsHashTable = @{PSTypeName = "LansweeperPlatform.Asset"; Key = $Item.key; LastSeen = $Item.assetBasicInfo.lastSeen.ToLocalTime(); CustomFields = $Item.assetCustom.fields; Relations = $Item.relations}
            $Fields + $CoreFields | ForEach-Object {$FieldsHashTable += @{(-join ($_.Split(".") | ForEach-Object {$_.Substring(0, 1).ToUpper() + $_.Substring(1)})).Replace("AssetBasicInfo", "").Replace("AssetCustom", "").Replace("RecognitionInfo", "") = Invoke-Expression -Command "`$Item.$_"}}
            [pscustomobject] $FieldsHashTable
        }
        $Page = "NEXT"
        $Cursor = $Result.data.site.assetResources.pagination.next
    }
    until ($Result.data.site.assetResources.items.Count -eq 0)
}

function Get-lspAssetState
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Asset State

    .EXAMPLE
        PS>Get-lspAssetState

        Retrieves all asset categorization states defined on a Lansweeper site.

    .EXAMPLE
        PS>Get-lspAssetState -Name "Active", "S*"

        You can specify one or more state names to retrieve. Wildcards are supported.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Name = "*")

    $GraphQL =
@"
query
{
    site(id: "$Script:SiteId")
    {
        assetStates
        {
            assetStateKey
            name
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL
    $AssetState = @()
    foreach ($N in $Name)
    {
        $AssetState += $Result.data.site.assetStates | Where-Object {$_.name -like $N}
    }
    $AssetState | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.AssetState"; AssetStateKey = $_.assetStateKey; Name = $_.name}} | Sort-Object -Property "Name" -Unique
}

function Get-lspAssetType
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Asset Type

    .EXAMPLE
        PS>Get-lspAssetType

        Retrieves all asset categorization types defined on a Lansweeper site.

    .EXAMPLE
        PS>Get-lspAssetType -Name "Router", "Switch", "Azure *"

        You can specify one or more type names to retrieve. Wildcards are supported.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Name = "*")

    $GraphQL =
@"
query
{
    site(id: "$Script:SiteId")
    {
        assetTypeList
        {
            assetTypeKey
            name
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL
    $AssetType = @()
    foreach ($N in $Name)
    {
        $AssetType += $Result.data.site.assetTypeList | Where-Object {$_.name -like $N}
    }
    $AssetType | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.AssetType"; AssetTypeKey = $_.assetTypeKey; Name = $_.name}} | Sort-Object -Property "Name" -Unique
}

function Get-lspCustomField
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Custom Field

    .EXAMPLE
        PS>Get-lspCustomField

        Retrieves all asset custom fields defined on a Lansweeper site.

    .EXAMPLE
        PS>Get-lspCustomField -Name "C-Confidentiality", "*-*"

        You can specify one or more custom field names to retrieve. Wildcards are supported.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Name = "*")

    $GraphQL =
@"
query
{
    site(id: "$Script:SiteId")
    {
        customFields
        {
            key
            name
            type
            props
            {
                minNumericValue
                maxNumericValue
                currencyType
                options
            }
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL
    $CustomField = @()
    foreach ($N in $Name)
    {
        $CustomField += $Result.data.site.customFields | Where-Object {$_.name -like $N}
    }
    $CustomField = $CustomField | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.CustomField";
                                                                     Key = $_.key;
                                                                     Name = $_.name;
                                                                     Type = (Get-Culture).TextInfo.ToTitleCase($_.type.ToLower());
                                                                     MinNumericValue = $_.props.minNumericValue;
                                                                     MaxNumericValue = $_.props.maxNumericValue;
                                                                     CurrencyType = $_.props.currencyType;
                                                                     Options = $_.props.options -join ", "}}
    $CustomField | Sort-Object -Property "Name" -Unique
}

function Get-lspRelation
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Relation

    .EXAMPLE
        PS>Get-lspRelation

        Retrieves all asset relationship types defined on a Lansweeper site.

    .EXAMPLE
        PS>Get-lspAsset | Get-lspRelation

        Retrieves all forward relationship links created between assets.
        Assets without relationships do not appear in the output.

    .EXAMPLE
        PS>Get-lspAsset | Get-lspRelation -Reverse

        Retrieves all reverse relationship links created between assets.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $True)]  [PSTypeName("LansweeperPlatform.Asset")] $Asset,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [switch] $Reverse)

    begin
    {
        $GraphQL =
@"
query
{
    site(id: "$Script:SiteId")
    {
        relations
        {
            typeKey
            name
            reverseName
        }
    }
}
"@

        if (-not $Script:SiteId)
        {
            throw "Run Connect-lspSite first."
        }
        if ($PSBoundParameters.Count -or $MyInvocation.ExpectingInput)
        {
            $R = [bool] $Reverse
            $AssetHT = Get-lspAsset | Group-Object -Property "Key" -AsHashTable -AsString
            $RelationHT = Get-lspRelation | Group-Object -Property "TypeKey" -AsHashTable -AsString
            $ArrowHT = @{$False = "-> {0} ->"; $True = "<- {0} <-"}
            $NameOrReverseNameHT = @{$False = "name"; $True = "reverseName"}
        }
    }
    process
    {
        $Asset.Relations | Where-Object {$_ -and ($R -xor $_.isParent)} | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.Relation"; Id = $_.id; Parent = $AssetHT.($_.parentAssetKey).Name; Relation = $ArrowHT[$R] -f $RelationHT.($_.typeKey).($NameOrReverseNameHT[$R]); Child = $AssetHT.($_.childAssetKey).Name}}
    }
    end
    {
        if (-not $Asset)
        {
            $Result = Invoke-lspRestMethod -GraphQL $GraphQL
            $Result.data.site.relations | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.RelationType"; TypeKey = $_.typeKey; Name = $_.name; ReverseName = $_.reverseName}} | Sort-Object -Property "Name"
        }
    }
}

function Get-lspSite
{
<#
    .SYNOPSIS
        Get Lansweeper Platform Site

    .DESCRIPTION
        This cmdlet retrieves all site names that your access token has access to.
        Use the site name when calling the Connect-lspSite cmdlet.
        The Token parameter only needs to be specified once per session.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string] $Token)

    $GraphQL =
@"
query
{
    me
    {
        profiles
        {
            site
            {
                id
                brandingName
            }
        }
    }
}
"@

    if (-not $Script:Token)
    {
        if ($Token)
        {
            $Script:Token = $Token
        }
        else
        {
            throw "Parameter 'Token' is required."
        }
    }
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL
    $Result.data.me.profiles.site | ForEach-Object {[pscustomobject] @{PSTypeName = "LansweeperPlatform.Site"; Id = $_.id; Name = $_.brandingName}} | Sort-Object -Property "Name"
}

function Invoke-lspRestMethod
{
    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $False)] [string] $GraphQL)

    Invoke-RestMethod -Uri "https://api.lansweeper.com/api/v2/graphql" -Method "Post" -Headers @{Authorization = "Token $Script:Token"; "Content-Type" = "application/json"} -Body (@{query = $GraphQL} | ConvertTo-Json -Compress)
}

function New-lspAsset
{
<#
    .SYNOPSIS
        New Lansweeper Platform Asset

    .EXAMPLE
        PS>New-lspAsset -Name "As Simple As Possible"

        This example creates an asset using only the Name parameter.
        It may take up to 30 minutes for the newly created asset to appear on a Lansweeper site.

    .EXAMPLE
        PS>$iPhone = (Get-lspAssetType -Name "iPhone").AssetTypeKey
        PS>$Broken = (Get-lspAssetState -Name "Broken").AssetStateKey
        PS>New-lspAsset -Name "A Broken iPhone" -Fields "assetBasicInfo.typeKey = $iPhone", "assetCustom.stateKey = $Broken"

        This example demonstrates how to set field values during asset creation using the Fields parameter. In the Lansweeper Data API documentation, a full field name is referred to as a path.
        Use the syntax "path=value", as shown in the example.

        For more information about determining paths for asset objects, see the Path-building section:
        https://developer.lansweeper.com/docs/data-api/guides/getting-data#path-building

    .EXAMPLE
        PS>New-lspAsset -Name "Payroll Business Process" -Fields "assetBasicInfo.typeKey = $((Get-lspAssetType -Name "Business Process").AssetTypeKey)", "assetCustom.fields.C-Confidentiality = 1", "assetCustom.fields.I-Integrity = 2", "assetCustom.fields.A-Availability = 3"

        This example assumes that an asset type named Business Process and custom fields named C-Confidentiality, I-Integrity, and A-Availability have already been added to your Lansweeper site to support the CIA triad.
        This example adds an asset representing a business process and assigns CIA ratings to the custom fields. It demonstrates how to set custom field values during asset creation.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True,  ValueFromPipeline = $False)] [string] $Name,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Fields)

    $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        addAsset
        (
            input: INPUT
        )
        {
            assetBasicInfo
            {
                name
                typeKey
            }
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    $Fields += "assetBasicInfo.name = $Name"
    if (-not ($Fields | Where-Object {$_ -like "assetBasicInfo.typeKey*"}))
    {
        $Fields += "assetBasicInfo.typeKey = " + (Get-lspAssetType -Name "Computer").AssetTypeKey
    }
    if (-not ($Fields | Where-Object {$_ -like "assetCustom.stateKey*"}))
    {
        $Fields += "assetCustom.stateKey = " + (Get-lspAssetState -Name "Active").AssetStateKey
    }
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("INPUT", ($Fields | ConvertTo-Hashtable | ConvertTo-Json -Depth 3 -Compress).Replace('{"', '{').Replace('":', ':').Replace(',"', ','))
}

function New-lspCustomField
{
<#
    .SYNOPSIS
        New Lansweeper Platform Custom Field

    .DESCRIPTION
        This cmdlet creates a custom field definition on a Lansweeper site.
        The examples demonstrate how to create custom fields of all supported types.

    .EXAMPLE
        PS>New-lspCustomField -Name "My text" -Type "Text"

    .EXAMPLE
        PS>New-lspCustomField -Name "My text field" -Type "Text field"

    .EXAMPLE
        PS>New-lspCustomField -Name "My date" -Type "Date"

    .EXAMPLE
        PS>New-lspCustomField -Name "My time" -Type "Time"

    .EXAMPLE
        PS>New-lspCustomField -Name "My hyperlink" -Type "Hyperlink"

    .EXAMPLE
        PS>New-lspCustomField -Name "My dropdown" -Type "Dropdown" -Options "Selectable option 1", "Selectable option 2", "Selectable option 3"

    .EXAMPLE
        PS>New-lspCustomField -Name "My Currency" -Type "Currency" -Currency "EUR"

    .EXAMPLE
        PS>New-lspCustomField -Name "My Number" -Type "Number"
        PS>New-lspCustomField -Name "My Percentage" -Type "Number" -MinNumericValue 0 -MaxNumericValue 100
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True,  ValueFromPipeline = $False)] [string] $Name,
           [Parameter(Mandatory = $True,  ValueFromPipeline = $False)] [ValidateSet("Text", "Text field", "Dropdown", "Date", "Time", "Currency", "Hyperlink", "Number")] [string] $Type,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [string[]] $Options,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [ValidateSet("USD", "EUR", "JPY", "CHF", "GPB", "CAD", "ZAR", "AUD", "CNY", "HKD", "ZND", "SEK", "KRW", "SGD", "NOK", "MXN", "INR", "RUB", "TRY", "BRL")] [string] $Currency,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [int] $MinimumValue,
           [Parameter(Mandatory = $False, ValueFromPipeline = $False)] [int] $MaximumValue)

    $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        createCustomField
        (
            field:
            {
                name: "$Name"
                type: TYPE
                props:
                {
                    options:
                    [
                        $($Options | ForEach-Object {"""$_"" "})
                    ]
                    $(if ($Currency)     {"currencyType: $Currency"})
                    $(if ($MinimumValue) {"minNumericValue: $MinimumValue"})
                    $(if ($MaximumValue) {"maxNumericValue: $MaximumValue"})
                }
            }
        )
        {
            key
        }
    }
}
"@

    if (-not $Script:SiteId)
    {
        throw "Run Connect-lspSite first."
    }
    if ($Type -eq "Dropdown" -and -not $Options)
    {
        throw "Parameter 'Options' is required when 'Type' is set to 'Dropdown'."
    }
    if ($Type -eq "Currency" -and -not $Currency)
    {
        throw "Parameter 'Currency' is required when 'Type' is set to 'Currency'."
    }
    $T = $Type.ToUpper()
    if ($T -eq "TEXT")       {$T = "INPUT"}
    if ($T -eq "TEXT FIELD") {$T = "TEXTAREA"}
    if ($T -eq "DROPDOWN")   {$T = "SELECT"}
    if ($T -eq "NUMBER")     {$T = "NUMERIC"}
    $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("TYPE", $T)
    Get-lspCustomField | Where-Object {$_.Key -eq $Result.data.site.createCustomField.key}
}

function Remove-lspAsset
{
<#
    .SYNOPSIS
        Remove Lansweeper Platform Asset

    .EXAMPLE
        PS>Get-lspAsset -Name "172.30.11.201", "172.30.192.55" | Remove-lspAsset
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)] [PSTypeName("LansweeperPlatform.Asset")] $Asset)

    begin
    {
        $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        deleteAssets
        (
            keys:
            [
                KEYS
            ]
        )
    }
}
"@

        $Key = ""
    }
    process
    {
        $Key += """$($Asset.Key)"" "
    }
    end
    {
        $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("KEYS", $Key)
    }
}

function Remove-lspCustomField
{
<#
    .SYNOPSIS
        Remove Lansweeper Platform Custom Field

    .EXAMPLE
        PS>Get-lspCustomField -Name "aa*" | Remove-lspCustomField
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)] [PSTypeName("LansweeperPlatform.CustomField")] $CustomField)

    begin
    {
        $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        deleteCustomField(key: "KEY")
    }
}
"@
    }
    process
    {
        $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("KEY", $CustomField.Key)
    }
}

function Remove-lspRelation
{
<#
    .SYNOPSIS
        Remove Lansweeper Platform Relation

    .EXAMPLE
        PS>Get-lspAsset -Name "dc1" | Get-lspRelation | Remove-lspRelation

    .EXAMPLE
        PS>Get-lspAsset -Name "esx1" | Get-lspRelation -Reverse | Remove-lspRelation
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)] [PSTypeName("LansweeperPlatform.Relation")] $Relation)

    begin
    {
        $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        deleteRelation(relationId: "RELATIONID")
    }
}
"@
    }
    process
    {
        $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("RELATIONID", $Relation.Id)
    }
}

function Set-lspAsset
{
<#
    .SYNOPSIS
        Set Lansweeper Platform Asset

    .EXAMPLE
        PS>Get-lspAsset -Name "dc1", "dc2" | Set-lspAsset -Fields "assetCustom.building = D", "assetCustom.department = IT", "assetCustom.fields.C-Confidentiality = 1", "assetCustom.fields.I-Integrity = 2", "assetCustom.fields.A-Availability = 3"

        This example assumes that custom fields named C-Confidentiality, I-Integrity, and A-Availability have already been added to your Lansweeper site to support the CIA triad.
        This example demonstrates how to update predefined fields and custom fields using the Fields parameter. In the Lansweeper Data API documentation, a full field name is referred to as a path.
        Use the syntax "path=value", as shown in the example.

        For more information about determining paths for asset objects, see the Path-building section:
        https://developer.lansweeper.com/docs/data-api/guides/getting-data#path-building

    .EXAMPLE
        PS>Get-lspAsset -Name "esx1" | Set-lspAsset -Fields "assetCustom.department = ", "assetCustom.fields.A-Availability = "

        This example demonstrates how to clear predefined and custom field values.
#>

    [CmdletBinding()]
    param ([Parameter(Mandatory = $True, ValueFromPipeline = $True)]  [PSTypeName("LansweeperPlatform.Asset")] $Asset,
           [Parameter(Mandatory = $True, ValueFromPipeline = $False)] [string[]] $Fields)

    begin
    {
        $GraphQL =
@"
mutation
{
    site(id: "$Script:SiteId")
    {
        editAsset
        (
            key: "KEY"
            fields: $(($Fields | ConvertTo-Hashtable | ConvertTo-Json -Depth 3 -Compress).Replace('{"', '{').Replace('":', ':').Replace(',"', ','))
        )
        {
            assetBasicInfo
            {
                name
            }
        }
    }
}
"@

        if (-not $Script:SiteId)
        {
            throw "Run Connect-lspSite first."
        }
    }
    process
    {
        $Result = Invoke-lspRestMethod -GraphQL $GraphQL.Replace("KEY", $Asset.Key)
    }
}

Update-FormatData -PrependPath "$PSScriptRoot\LansweeperPlatform.Format.ps1xml"
