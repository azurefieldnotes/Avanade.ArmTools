#requires -Modules 'Microsoft.PowerShell.Utility' -Version 3.0

<#
    Avanade.ArmTools
#>

$Script:SubscriptionProviderApiVersionCache=@{}
#region Constants
$Script:Iso3166Codes=@(
    'AF','AX','AL','DZ','AS','AD','AO','AI','AQ','AG','AR','AM','AW','AU','AT','AZ','BS','BH',
    'BD','BB','BY','BE','BZ','BJ','BM','BT','BO','BQ','BA','BW','BV','BR','IO','BN','BG','BF',
    'BI','KH','CM','CA','CV','KY','CF','TD','CL','CN','CX','CC','CO','KM','CG','CD','CK','CR',
    'CI','HR','CU','CW','CY','CZ','DK','DJ','DM','DO','EC','EG','SV','GQ','ER','EE','ET','FK',
    'FO','FJ','FI','FR','GF','PF','TF','GA','GM','GE','DE','GH','GI','GR','GL','GD','GP','GU',
    'GT','GG','GN','GW','GY','HT','HM','VA','HN','HK','HU','IS','IN','ID','IR','IQ','IE','IM',
    'IL','IT','JM','JP','JE','JO','KZ','KE','KI','KP','KR','KW','KG','LA','LV','LB','LS','LR',
    'LY','LI','LT','LU','MO','MK','MG','MW','MY','MV','ML','MT','MH','MQ','MR','MU','YT','MX',
    'FM','MD','MC','MN','ME','MS','MA','MZ','MM','NA','NR','NP','NL','NC','NZ','NI','NE','NG',
    'NU','NF','MP','NO','OM','PK','PW','PS','PA','PG','PY','PE','PH','PN','PL','PT','PR','QA',
    'RE','RO','RU','RW','BL','SH','KN','LC','MF','PM','VC','WS','SM','ST','SA','SN','RS','SC',
    'SL','SG','SX','SK','SI','SB','SO','ZA','GS','SS','ES','LK','SD','SR','SJ','SZ','SE','CH',
    'SY','TW','TJ','TZ','TH','TL','TG','TK','TO','TT','TN','TR','TM','TC','TV','UG','UA','AE',
    'GB','US','UM','UY','UZ','VU','VE','VN','VG','VI','WF','EH','YE','ZM','ZW'
)
$Script:DefaultArmApiVersion="2016-09-01"
$Script:DefaultResourceLockApiVersion="2015-01-01"
$Script:DefaultFeatureApiVersion="2015-12-01"
$Script:DefaultBillingApiVerion='2015-06-01-preview'
$Script:DefaultWebsiteApiVersion='2016-08-01'
$Script:DefaultMonitorApiVersion='2016-03-01'
$Script:ClassicMonitorApiVersion='2014-06-01'
$Script:DefaultEventLogApiVersion="2014-04-01"
$Script:DefaultArmFrontDoor='https://management.azure.com'
#endregion

#region Helper Methods

function CreateDynamicValidateSetParameter
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param
    (
        # Parameter Name
        [Parameter(Mandatory=$true)]
        [string]
        $ParameterName,
        [Parameter(Mandatory=$false)]
        [string[]]
        $ParameterSetNames= "__AllParameterSets",
        # String ValidateSet Array
        [Parameter(Mandatory=$true)]
        [System.Object[]]
        $ParameterValues,
        [Parameter(Mandatory=$false)]
        [System.Type]
        $ParameterType=[String],
        [Parameter(Mandatory=$false)]
        [object]
        $DefaultValue,
        [Parameter(Mandatory=$false)]
        [bool]
        $Mandatory=$false,
        [Parameter(Mandatory=$false)]
        [bool]
        $ValueFromPipeline=$false,
        [Parameter(Mandatory=$false)]
        [bool]
        $ValueFromPipelineByName=$false
    )

    # Create the collection of attributes
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

    # Create and set the parameters' attributes
    foreach ($ParameterSetName in $ParameterSetNames) {
        $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
        $ParameterAttribute.ValueFromPipeline = $ValueFromPipeline
        $ParameterAttribute.ValueFromPipelineByPropertyName = $ValueFromPipelineByName
        $ParameterAttribute.Mandatory = $Mandatory
        $ParameterAttribute.ParameterSetName=$ParameterSetName
        $AttributeCollection.Add($ParameterAttribute)
    }

    # Generate and set the ValidateSet
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($ParameterValues)
    # Add the ValidateSet to the attributes collection
    $AttributeCollection.Add($ValidateSetAttribute)

    # Create and return the dynamic parameter
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, $ParameterType, $AttributeCollection)
    if ($DefaultValue -ne $null) {
        $RuntimeParameter.Value=$DefaultValue
    }
    return $RuntimeParameter
}

<#
    .SYNOPSIS
        Caching helper method for speeding up api version retrieval for resources
#>
function GetResourceTypeApiVersion
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [String]
        $SubscriptionId,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$true)]
        [String]
        $ResourceType,
        [Parameter(Mandatory=$false)]
        [String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    #Is the provider type cached??
    if ($Script:SubscriptionProviderApiVersionCache.ContainsKey($SubscriptionId))
    {
        $SubscriptionCache=$Script:SubscriptionProviderApiVersionCache[$SubscriptionId]
        #Is the type there?
        if ($SubscriptionCache.ContainsKey($ResourceType))
        {
            $ApiVersions=$SubscriptionCache[$ResourceType]
        }
        else
        {
            $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $SubscriptionId -ResourceType $ResourceType `
                -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint
            $SubscriptionCache.Add($ResourceType,$ApiVersions)
            $Script:SubscriptionProviderApiVersionCache[$SubscriptionId]=$SubscriptionCache
        }
    }
    else
    {
        $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $SubscriptionId -ResourceType $ResourceType `
            -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
        $Script:SubscriptionProviderApiVersionCache.Add($SubscriptionId,@{$ResourceType=$ApiVersions})
    }
    Write-Output $ApiVersions
}

<#
    .SYNOPSIS
        Returns OData result sets from ARM
    .REMARKS
        Traps all exceptions so previous results are returned through output stream
#>
function GetArmODataResult
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.Uri]
        $Uri,
        [Parameter(Mandatory=$true)]
        [hashtable]
        $Headers,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ContentType='application/json',
        [Parameter(Mandatory=$false)]
        [System.Int32]
        $LimitResultPages,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ValueProperty='value',
        [Parameter(Mandatory=$false)]
        [System.String]
        $NextLinkProperty='nextLink',
        [Parameter(Mandatory=$false)]
        [System.String]
        $ErrorProperty='error'
    )
    $ResultPages=0
    $TotalItems=0
    do
    {
        $ResultPages++
        try
        {
            $ArmResult=Invoke-RestMethod -Uri $Uri -Headers $Headers -ContentType $ContentType
            if ($ArmResult -ne $null)
            {
                #Can we match the error?
                if($ArmResult.PSobject.Properties.name -match $ErrorProperty)
                {
                    throw ($ArmResult|Select-Object -ExpandProperty $ErrorProperty)|ConvertTo-Json
                }
                #Is there an OData value set?
                elseif($ArmResult.PSobject.Properties.name -match $ValueProperty)
                {
                    Write-Verbose "[GetArmODataResult] OData.$ValueProperty set retrieved"
                    $RequestValue=$ArmResult|Select-Object -ExpandProperty $ValueProperty
                }
                #Single Value
                else
                {
                    Write-Verbose "[GetArmODataResult] Single Value Retrieved"
                    $RequestValue=$ArmResult
                }
                if($RequestValue -ne $null)
                {
                    if($RequestValue -is [array])
                    {
                        $TotalItems+=$RequestValue.Count
                    }
                    else
                    {
                        $TotalItems++
                    }
                    if ($LimitResultPages -gt 0)
                    {
                        if ($ResultPages -lt $LimitResultPages)
                        {
                            if($ArmResult.PSobject.Properties.name -match $NextLinkProperty)
                            {
                                $Uri=$ArmResult|Select-Object -ExpandProperty $NextLinkProperty
                                Write-Verbose "[GetArmODataResult] Total Items:$TotalItems. More items available @ $Uri"
                            }
                            else
                            {
                                Write-Verbose "[GetArmODataResult] No next link $NextLinkProperty in result set."
                                $Uri=$null
                            }
                        }
                        else
                        {
                            $Uri=$null
                            Write-Verbose "[GetArmODataResult] Stopped iterating at $ResultPages pages. Iterated Items:$TotalItems More data available?:$([string]::IsNullOrEmpty($ArmResult.value))"
                        }
                    }
                    else
                    {
                        if($ArmResult.PSobject.Properties.name -match $NextLinkProperty)
                        {
                            $Uri=$ArmResult|Select-Object -ExpandProperty $NextLinkProperty
                            Write-Verbose "[GetArmODataResult] Total Items:$TotalItems. More items available @ $Uri"
                        }
                        else
                        {
                            $Uri=$null
                        }
                    }
                    Write-Output $RequestValue
                }
                else
                {
                    $Uri=$null
                }
            }
            else
            {
                $Uri=$null
            }
        }
        catch
        {
            Write-Warning "[GetArmODataResult]Error $Uri $_"
            $Uri=$null
        }
    } while ($Uri -ne $null)
}

<#
    .SYNOPSIS
        Resolves resource segments from an ARM resource id
    .PARAMETER Id
        The resource id(s) to resolve
#>
Function ConvertFrom-ArmResourceId
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String[]]
        $Id
    )
    BEGIN{}
    PROCESS
    {
        foreach ($ResourceId in $Id) {

            $IdPieces=$ResourceId.TrimStart('/').Split('/')
            $LastIndex=$IdPieces.Length-1
            #Resolve the subscription and provider
            $SubscriptionId=$IdPieces[1]
            $Namespace=$IdPieces[5]
            $ResourceGroup=$IdPieces[3]
            $Remainder=$IdPieces[6..$LastIndex]
            $LastIndex=$Remainder.Length-1
            if($LastIndex -gt 1) {
                $TypeParts=@()
                $ResourceName=$Remainder[$LastIndex]
                for ($i = 0; $i -lt $Remainder.Count; $i+=2) {
                    $TypeParts+=$Remainder[$i]
                }
                $ResourceType=[String]::Join('/',$TypeParts)
            }
            else {
                $ResourceType=$Remainder[0]
                $ResourceName=$Remainder[1]
            }
            $ResourceData=New-Object PSObject -Property @{
                Id=$ResourceId;
                SubscriptionId=$SubscriptionId;
                ResourceGroup=$ResourceGroup;
                Namespace=$Namespace;
                ResourceType=$ResourceType;
                Name=$ResourceName;
                FullResourceType="$Namespace/$ResourceType";
            }
            Write-Output $ResourceData
        }
    }
    END{}
}

#endregion

<#
    .SYNOPSIS
        Removes an ARM item (Resource/Resource Group)
#>
Function Remove-ArmItem
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object')]
        [System.Object[]]
        $Resource,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id')]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $AuthHeaders=@{Authorization="Bearer $AccessToken"}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $ResourceId=$Resource|Select-Object -ExpandProperty id
        }
        foreach ($item in $ResourceId)
        {
            Write-Verbose "[Remove-ArmItem] Deleting resource $item"
            $UriBuilder=New-Object System.UriBuilder($ApiEndpoint)
            $UriBuilder.Path=$item
            $UriBuilder.Query="api-version=$ApiVersion"
            try
            {
                $Result=Invoke-RestMethod -Uri $UriBuilder.Uri -Method Delete -Headers $AuthHeaders
            }
            catch
            {
                Write-Warning "[Remove-ArmItem] Failed deleting $item $_"
            }
        }
    }
    END{}
}

<#
    .SYNOPSIS
        Retrieves azure websites from the given subscription(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER ResourceGroupName
        The website resource group
    .PARAMETER WebsiteName
        The website name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmWebSite
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idWithName',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='idWithName')]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='idWithName')]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='idWithName')]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='idWithName')]
        [Parameter(Mandatory=$false,ParameterSetName='objectWithName')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='idWithName')]
        [Parameter(Mandatory=$false,ParameterSetName='objectWithName')]
        [System.String]
        $ApiVersion=$Script:DefaultWebsiteApiVersion
    )

    BEGIN
    {
        $Headers=@{'Authorization'="Bearer $AccessToken";'Accept'='application/json';}
        $UriBuilder=New-Object System.UriBuilder($ApiEndpoint)
        $UriBuilder.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in 'object','objectWithName')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($id in $SubscriptionId)
        {
            try
            {
                if ($PSCmdlet.ParameterSetName -in 'objectWithName','idWithName')
                {
                    $UriBuilder.Path="/subscriptions/$Id/resourcegroups/$ResourceGroupName/providers/Microsoft.Web/sites/$WebsiteName"
                    $ArmResult=Invoke-RestMethod -Uri $UriBuilder.Uri -Headers $Headers -ContentType 'application/json'
                    Write-Output $ArmResult
                }
                else
                {
                    $UriBuilder.Path="/subscriptions/$Id/providers/Microsoft.Web/sites"
                    $ArmResult=GetArmODataResult -Uri $UriBuilder.Uri -Headers $Headers -ContentType 'application/json'
                    Write-Output $ArmResult
                }
            }
            catch
            {
                Write-Warning "[Get-ArmWebSite] Subscription $id $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves publishing credential(s) for given website(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER ResourceGroupName
        The website resource group
    .PARAMETER WebsiteName
        The website name
    .PARAMETER Website
        The website instance
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmWebSitePublishingCredential
{
    [CmdletBinding(DefaultParameterSetName='id')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [System.Object]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='bySiteObject',ValueFromPipeline=$true)]
        [System.Object[]]
        $Website,
        [Parameter(Mandatory=$true,ParameterSetName='bySiteObject')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='bySiteObject')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='bySiteObject')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.String]
        $ApiVersion=$Script:DefaultWebsiteApiVersion
    )

    BEGIN
    {
        $Headers=@{'Authorization'="Bearer $AccessToken";'Accept'='application/json';}
    }
    PROCESS
    {

        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription.subscriptionId
            $ArmSite=Get-ArmWebSite -SubscriptionId $SubscriptionId -WebsiteName $WebsiteName `
                -ResourceGroupName $ResourceGroupName -AccessToken $AccessToken `
                -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
            $Website+=$ArmSite
        }

        foreach ($item in $Website)
        {
            $UriBuilder=New-Object System.UriBuilder($ApiEndpoint)
            $UriBuilder.Path="$($item.id)/config/publishingCredentials/list"
            $UriBuilder.Query="api-version=$ApiVersion"
            $CredResult=Invoke-RestMethod -Uri $UriBuilder.Uri -Method Post -ContentType 'application/json' -Headers $Headers
            Write-Output $CredResult
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the list of tenants associated with the authorization token
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmTenant
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.String[]]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{'Authorization'="Bearer $AccessToken";'Accept'='application/json';}
    }
    PROCESS
    {
        foreach ($token in $AccessToken)
        {
            $ArmUriBld=New-Object System.UriBuilder($Script:DefaultArmFrontDoor)
            $ArmUriBld.Path='tenants'
            $ArmUriBld.Query="api-version=$ApiVersion"
            try
            {
                $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $Headers
                Write-Output $ArmResult
            }
            catch
            {
                Write-Warning "[Get-ArmTenant] Error retrieving tenant for current token $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves Azure subscriptions
    .PARAMETER SubscriptionId
        The azure subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmSubscription
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$false)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion,
        [Parameter(Mandatory=$false)]
        [Switch]
        $IncludeDetails
    )

    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Query="api-version=$ApiVersion&includeDetails=$($IncludeDetails.IsPresent)"
    $ArmUriBld.Path='subscriptions'
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        $ArmUriBld.Path+="/$SubscriptionId"
    }
    $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false)
    {
        Write-Output $ArmResult
    }
    else
    {
        Write-Output $ArmResult.value
    }
}

<#
    .SYNOPSIS
        Registers the specified provider with the subscription(s)
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Namespace
        The provider namespace to be registered
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Register-ArmProvider
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-09-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/$Namespace/register"
            try
            {
                $Result=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -Method Post -ErrorAction Stop
                Write-Output $Result
            }
            catch
            {
                Write-Warning "$item $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Unregisters the specified provider with the subscription(s)
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Namespace
        The provider namespace to be unregistered
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Unregister-ArmProvider
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-09-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/$Namespace/unregister"
            try
            {
                $Result=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -Method Post -ErrorAction Stop
                Write-Output $Result
            }
            catch
            {
                Write-Warning "$item $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Azure resource providers
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Namespace
        The resource provider namespace
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmProvider
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [String]
        $ExpandFilter
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            if ($PSCmdlet.ParameterSetName -eq "object")
            {
                $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
            }
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers"
            try
            {
                if([String]::IsNullOrEmpty($Namespace) -eq $false)
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                    $NamespaceResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Stop
                    if($NamespaceResult -ne $null)
                    {
                        Write-Output $NamespaceResult
                    }
                }
                else
                {
                    if ([String]::IsNullOrEmpty($ExpandFilter) -eq $false)
                    {
                        $ArmUriBld.Query="api-version=$ApiVersion&`$expand=$ExpandFilter"
                    }
                    $NamespaceResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
                    if($NamespaceResult -ne $null)
                    {
                        Write-Output $NamespaceResult
                    }
                }
            }
            catch
            {
                Write-Warning "[Get-ArmProvider] Subscription $item $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Azure resource provider types
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Namespace
        The resource group name
    .PARAMETER ResourceType
        The fully qualified type name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceType
{
    [CmdletBinding(DefaultParameterSetName='objectNamespace')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='idType',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectType',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace')]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace')]
        [ValidatePattern('^[A-Za-z]+[\.]+[A-Za-z]+([\.]+[A-Za-z]+)*')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='objectType')]
        [Parameter(Mandatory=$true,ParameterSetName='idType')]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$true,ParameterSetName='objectType')]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace')]
        [Parameter(Mandatory=$true,ParameterSetName='idType')]
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectType')]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='idType')]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='objectType')]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='idType')]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        if($PSCmdlet.ParameterSetName -in 'objectType','idType')
        {
            $Namespace=$ResourceType.Split('/')|Select-Object -First 1
            $TypeName=$ResourceType.Replace("$Namespace/",[String]::Empty)
        }
    }
    PROCESS
    {
        if ($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId))
        {
            if($PSCmdlet.ParameterSetName -in 'objectType','idType')
            {
                $ArmUriBld.Path="providers/$Namespace"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                $ResProvType=$ArmResult.resourceTypes|Where-Object{$_.resourceType -eq $TypeName }|Select-Object -First 1
                if ($ResProvType -ne $null)
                {
                    Write-Output $ResProvType
                }
                else
                {
                    Write-Warning "[Get-ArmResourceType] $ResourceType was not found in subscription:$item"
                }
            }
            else
            {
                $ArmUriBld.Path="providers/$Namespace"
                $Providers=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                foreach ($Provider in $Providers)
                {
                    Write-Output $Provider.resourceTypes
                }
            }
        }
        else
        {
            if($PSCmdlet.ParameterSetName -eq 'object')
            {
                foreach ($sub in $Subscription)
                {
                    $SubscriptionId+=$sub.subscriptionId
                }
            }
            foreach ($item in $SubscriptionId)
            {
                try
                {
                    if($PSCmdlet.ParameterSetName -in 'objectType','idType')
                    {
                        $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                        $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                        $ResProvType=$ArmResult.resourceTypes|Where-Object{$_.resourceType -eq $TypeName }|Select-Object -First 1
                        if ($ResProvType -ne $null)
                        {
                            Write-Output $ResProvType
                        }
                        else
                        {
                            Write-Warning "[Get-ArmResourceType] $ResourceType was not found in subscription:$item"
                        }
                    }
                    else
                    {
                        $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                        $Providers=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                        foreach ($Provider in $Providers)
                        {
                            Write-Output $Provider.resourceTypes
                        }
                    }
                }
                catch
                {
                    Write-Warning "[Get-ArmResourceType] $item $ResourceType $_"
                }
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Azure resource provider api versions
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER ResourceType
        The fully qualified type name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceTypeApiVersion
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {

    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmResourceType=Get-ArmResourceType -SubscriptionId $SubscriptionId -AccessToken $AccessToken `
                -ResourceType $ResourceType -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
            Write-Output $ArmResourceType.apiVersions
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Azure resource provider locations
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER ResourceType
        The fully qualified type name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceTypeLocation
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {

    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmResourceType=Get-ArmResourceType -SubscriptionId $SubscriptionId -AccessToken $AccessToken `
                -ResourceType $ResourceType -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
            Write-Output $ArmResourceType.locations
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Azure resource groups
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Name
        The resource group name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceGroup
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $Name,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/resourcegroups"
            if([String]::IsNullOrEmpty($Name) -eq $false)
            {
                $ArmUriBld.Path+="/$Name"
            }
            try
            {
                $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                if($ArmResult -ne $null)
                {
                    Write-Output $ArmResult
                }
            }
            catch [System.Exception]
            {
                Write-Warning "[Get-ArmResourceGroup] Subscription $item $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves a list of Azure locations
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Location
        The desired location name or displayName
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version

#>
Function Get-ArmLocation
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId))
        {
            $ArmUriBld.Path='locations'
            $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if ($ArmResult -ne $null)
            {
                if([String]::IsNullOrEmpty($Location) -eq $false)
                {
                    $ArmLocation=$ArmResult|Where-Object{$_.name -eq $Location -or $_.displayName -eq $Location}|Select-Object -First 1
                    if($ArmLocation -ne $null)
                    {
                        Write-Output $ArmLocation
                    }
                    else
                    {
                        Write-Warning "[Get-ArmLocation] There is no location $Location available"
                    }
                }
                else
                {
                    Write-Output $ArmResult
                }                
            }
        }
        else
        {
            if ($PSCmdlet.ParameterSetName -eq "object")
            {
                $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
            }
            foreach ($item in $SubscriptionId)
            {
                    $ArmUriBld.Path="subscriptions/$item/locations"
                    $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
                    if ($ArmResult -ne $null)
                    {
                    if([String]::IsNullOrEmpty($Location) -eq $false)
                    {
                        $ArmLocation=$ArmResult|Where-Object{$_.name -eq $Location -or $_.displayName -eq $Location}|Select-Object -First 1
                        if($ArmLocation -ne $null)
                        {
                            Write-Output $ArmLocation
                        }
                        else
                        {
                            Write-Warning "[Get-ArmLocation] There is no location $Location available"
                        }
                    }
                    else
                    {
                        Write-Output $ArmResult
                    }                    
                }
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the resource locks
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER ResourceGroup
        The resource group to scope the query
    .PARAMETER ResourceType
        The resource type to scope the query
    .PARAMETER ResourceName
        The resource name to scope the query
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceLock
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ResourceName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-01-01'
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item"
            if([String]::IsNullOrEmpty($ResourceGroup) -eq $false)
            {
                $ArmUriBld.Path+="/resourceGroups/$ResourceGroup"
            }
            if([String]::IsNullOrEmpty($ResourceType) -eq $false -and [String]::IsNullOrEmpty($ResourceName) -eq $false)
            {
                $ArmUriBld.Path+="/providers/$ResourceType/$ResourceName"
            }
            $ArmUriBld.Path+="/providers/microsoft.authorization/locks"
            $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if($ArmResult)
            {
                Write-Output $ArmResult
            }            
        }

    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves abstract resource instance(s)
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER ResourceGroup
        The resource group to scope the query
    .PARAMETER Top
        Return only the top N results
    .PARAMETER Filter
        The additional ARM OData Filter (resourceType eq 'Microsoft.Compute/virtualMachines')
    .PARAMETER ResourceType
        A resource type to scope the retrieval
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResource
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace',ValueFromPipeline=$true)]        
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,      
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace')]
        [System.String]
        $ResourceType,           
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $Filter,      
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace')]        
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectByNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitByNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ParameterSetName='objectByNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitByNamespace')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $QueryStr="api-version=$ApiVersion"
        if ([String]::IsNullOrEmpty($Filter) -eq $false)
        {
            $QueryStr+="&`$filter=$Filter"
        }
        if ($Top -gt 0)
        {
            $QueryStr+="&`$top=$Top"
        }
        $ArmUriBld.Query=$QueryStr
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in "object",'objectByNamespace')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            if ($PSCmdlet.ParameterSetName -in 'explicitByNamespace','objectByNamespace')
            {
                $TypeApiVersion=Get-ArmResourceTypeApiVersion -SubscriptionId $item `
                    -ResourceType $ResourceType -AccessToken $AccessToken `
                    -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion|Select-Object -First 1
                if([String]::IsNullOrEmpty($TypeApiVersion))
                {
                    throw "Unable to resolve the api version for $ResourceType"
                }
                $ArmUriBld.Path="subscriptions/$item/providers/$ResourceType"
                $ArmUriBld.Query="api-version=$TypeApiVersion"
            }
            else
            {
                $ArmUriBld.Path="subscriptions/$item/resources"
                if ([String]::IsNullOrEmpty($ResourceGroup) -eq $false)
                {
                    $ArmUriBld.Path+="/resourceGroups/$ResourceGroup"
                }                   
            }
            $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if($ArmResult -ne $null)
            {
                Write-Output $ArmResult
            } 
        }
    }
    END
    {

    }

}

<#
    .SYNOPSIS
        Retrieves detailed resource instance(s)
    .PARAMETER Resource
        The azure subscription(s)
    .PARAMETER Id
        The resource id to retrieve
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
#>
Function Get-ArmResourceInstance
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id')]
        [String[]]
        $Id,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object')]
        [PSObject[]]
        $Resource,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.String[]]
        $ExpandProperties,        
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            $Id=$Resource|Select-Object -ExpandProperty id
        }
        foreach ($ResourceId in $Id)
        {
            $ArmResult=$null
            $ResourceData=$ResourceId|ConvertFrom-ArmResourceId
            #Resolve the api version
            $ResourceType="$($ResourceData.Namespace)/$($ResourceData.ResourceType)"
            $ApiVersions=GetResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId -AccessToken $AccessToken -ResourceType $ResourceType -ApiVersion $ApiVersion
            foreach ($Version in $ApiVersions)
            {
                try
                {
                    Write-Verbose "Requesting instance $ResourceId with API version $Version"
                    $ArmUriBld.Path=$ResourceId
                    $ArmUriBld.Query="api-version=$Version"
                    if ($ExpandProperties -ne $null) {
                        $ArmUriBld.Query="api-version=$Version&`$expand=$([String]::Join(',',$ExpandProperties))"
                    }                    
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Stop
                    break
                }
                catch [System.Exception]
                {
                    Write-Warning "[Get-ArmResourceInstance] $ResourceId using api version $Version - $_"
                }
            }
            if ($ArmResult -ne $null)
            {
                Write-Output $ArmResult
            }
        }
    }
    END
    {

    }
}

#region Commerce

<#
    .SYNOPSIS
        Retrieves the resource usage aggregates
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Granularity
        The granularity of the aggregates desired
    .PARAMETER StartTime
        The start time for the usage aggregates
    .PARAMETER EndTime
        The end time for the usage aggregates
    .PARAMETER StartTimeOffset
        The start time offset for the usage aggregates
    .PARAMETER EndTimeOffset
        The end time offset for the usage aggregates
    .PARAMETER ShowDetails
        Whether to show resource instance details
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmUsageAggregate
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.DateTime]
        $StartTime,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.DateTime]
        $EndTime=[System.DateTime]::UtcNow,
        [Parameter(Mandatory=$true,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitOffset')]
        [System.DateTimeOffset]
        $StartTimeOffset,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [System.DateTimeOffset]
        $EndTimeOffset,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Int32]
        $LimitResultPages,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [ValidateSet('Daily','Hourly')]
        [System.String]
        $Granularity='Daily',
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [Switch]
        $ShowDetails,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultBillingApiVerion
    )

    BEGIN
    {
        if ($PSCmdlet.ParameterSetName -in 'object','explicit')
        {
            if ($Granularity -eq "Hourly")
            {
                $StartTimeOffset=New-Object System.DateTimeOffset($StartTime.Year,$StartTime.Month,$StartTime.Day,$StartTime.Hour,0,0,0)
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,$StartTime.Hour,0,0,0)
            }
            else
            {
                $StartTimeOffset=New-Object System.DateTimeOffset($StartTime.Year,$StartTime.Month,$StartTime.Day,0,0,0,0)
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,0,0,0,0)
            }
        }
        else
        {
            if ($Granularity -eq "Hourly")
            {
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,$StartTime.Hour,0,0,0)
            }
            else
            {
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,0,0,0,0)
            }
        }
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $StartTimeString=[Uri]::EscapeDataString($StartTimeOffset.ToString('o'))
        $EndTimeString=[Uri]::EscapeDataString($EndTimeOffset.ToString('o'))
        $ArmUriBld.Query="api-version=$ApiVersion&reportedStartTime=$($StartTimeString)&reportedEndTime=$($EndTimeString)" +
            "&aggregationGranularity=$Granularity&showDetails=$($ShowDetails.IsPresent)"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/UsageAggregates"
            $AggregateResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -LimitResultPages $LimitResultPages
            if($AggregateResult -ne $null)
            {
                Write-Output $AggregateResult
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the Rate Card for the given locale
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER OfferPrefix
        The offer prefix (e.g. MS-AZR-)
    .PARAMETER OfferCode (e.g. 0003P)
        The offer code
    .PARAMETER Locale (e.g. en-US)
        The locale for the desired results
    .PARAMETER Locale (e.g. US)
        The ISO-3166 two letter region code
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmRateCard
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $OfferPrefix="MS-AZR-",
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $OfferCode='0003P',
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultBillingApiVerion
    )

    DynamicParam
    {

        $SpecificCultures=[System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::AllCultures -band [System.Globalization.CultureTypes]::SpecificCultures)
        $CultureCodes = ($SpecificCultures|Select-Object -ExpandProperty Name)

        $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $RegionInfoParam=CreateDynamicValidateSetParameter -ParameterName 'RegionInfo' -ParameterSetNames "explicit","object" `
             -ParameterValues $Script:Iso3166Codes -ParameterType "String" -Mandatory $false -DefaultValue 'US'
        $LocaleParam=CreateDynamicValidateSetParameter -ParameterName 'Locale' -ParameterSetNames "explicit","object" `
            -ParameterValues $CultureCodes -ParameterType "String" -Mandatory $false -DefaultValue 'en-US'
        $RuntimeParameterDictionary.Add('RegionInfo',$RegionInfoParam)
        $RuntimeParameterDictionary.Add('Locale',$LocaleParam)
        return $RuntimeParameterDictionary
    }

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";'Accept'='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        if ($PSBoundParameters.Locale)
        {
            $Locale=$PSBoundParameters.Locale
        }
        else
        {
            $Locale='en-US'
        }
        if ($PSBoundParameters.RegionInfo)
        {
            $RegionInfo=$PSBoundParameters.RegionInfo
        }
        else
        {
            $RegionInfo='US'
        }

        $OfferDurableId="$($OfferPrefix)$($OfferCode)"
        $DesiredCulture=$SpecificCultures|Where-Object{$_.Name -eq $Locale}|Select-Object -First 1
        $DesiredRegion=New-Object System.Globalization.RegionInfo($RegionInfo)

        $ArmUriBld.Query="api-version=$ApiVersion&`$filter=OfferDurableId eq '$OfferDurableId' " +
            "and Currency eq '$($DesiredRegion.ISOCurrencySymbol)'" +
            "and Locale eq '$Locale' and RegionInfo eq '$RegionInfo'"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            Write-Verbose "[Get-ArmRateCard] Subscription:$item OfferDurableId:$OfferDurableId Locale:$Locale Currency:$($DesiredRegion.ISOCurrencySymbol)"
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/RateCard"
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -ErrorAction Stop
            if ($Result -ne $null) {
                Write-Output $Result    
            }
        }
    }
    END
    {

    }
}

#endregion

#region Monitor

<#
    .SYNOPSIS
        Retrieves the metric definition for the resource
    .PARAMETER ResourceId
        The desired resource id
    .PARAMETER ClassicApiVersion
        The ARM api version for classic resources
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmResourceMetricDefinition
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion=$Script:DefaultMonitorApiVersion,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ClassicApiVersion=$Script:ClassicMonitorApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            $ArmResource=$item|ConvertFrom-ArmResourceId
            #HACK! (Do something better)
            if($ArmResource.NameSpace -eq "Microsoft.ClassicCompute")
            {
                $ClassicApiVersion='2014-04-01'
            }
            if ($ArmResource.NameSpace -like "Microsoft.Classic*")
            {
                $ArmUriBld.Path="subscriptions/$($ArmResource.SubscriptionId)/resourceGroups/$($ArmResource.ResourceGroup)" + `
                    "/providers/$($ArmResource.NameSpace)/$($ArmResource.ResourceType)/$($ArmResource.Name)/metricDefinitions"
                $ArmUriBld.Query="api-version=$ClassicApiVersion"
            }
            else
            {
                $ArmUriBld.Path="$item/providers/microsoft.insights/metricdefinitions"
                $ArmUriBld.Query="api-version=$ApiVersion"
            }

            Write-Verbose "[Get-ArmResourceMetricDefinition] Retrieving Metric Definitions for $item"
            $RequestResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -ErrorAction Stop
            #HACK for malformed JSON
            if ($RequestResult.GetType().FullName -eq 'System.String') {
                $RequestResult=$RequestResult.Replace("ResourceUri","resourceUri").Replace("ResourceId","resourceId")
                $Result=$RequestResult|ConvertFrom-Json
                Write-Output $Result.value
            }
            else
            {
                Write-Output $RequestResult.value
            }            

        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the metric for the resource
    .PARAMETER ResourceId
        The desired resource id
    .PARAMETER Filter
        The oauth metric filter
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
    .PARAMETER ClassicApiVersion
        The ARM api version for classic resources
#>
Function Get-ArmResourceMetric
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$false)]
        [String]
        $Filter,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion='2016-09-01',
        [Parameter(Mandatory=$false)]
        [System.String]
        $ClassicApiVersion='2014-04-01'
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            $ArmResource=$item|ConvertFrom-ArmResourceId
            if ($ArmResource.NameSpace -like "*.Classic*")
            {
                $ArmUriBld.Path="subscriptions/$($ArmResource.SubscriptionId)/resourceGroups/$($ArmResource.ResourceGroup)" + `
                    "/providers/$($ArmResource.NameSpace)/$($ArmResource.ResourceType)/$($ArmResource.Name)/metrics"
                if([String]::IsNullOrEmpty($Filter))
                {
                    $UtcNow=[DateTime]::UtcNow
                    $End=New-Object System.DateTime($UtcNow.Year,$UtcNow.Month,$UtcNow.Day,$UtcNow.Hour,0,0)
                    $StartTime=(New-Object System.DateTimeOffset($End.AddHours(-1))).ToString('o')
                    $EndTime=(New-Object System.DateTimeOffset($End)).ToString('o')
                    $Filter="startTime eq $($StartTime) and endTime eq $($EndTime) and timeGrain eq duration'PT1H'"
                }
                $ArmUriBld.Query="api-version=$ClassicApiVersion&`$filter=$Filter"
            }
            else
            {
                $ArmUriBld.Path="$item/providers/microsoft.insights/metrics"
                if([String]::IsNullOrEmpty($Filter))
                {
                    $ArmUriBld.Query="api-version=$ApiVersion"
                }
                else
                {
                    $ArmUriBld.Query="api-version=$ApiVersion&`$filter=$Filter"
                }
            }
            try
            {
                Write-Verbose "[Get-ArmResourceMetric] Retrieving Metrics for $item"
                $RequestResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -ErrorAction Continue
                #HACK for malformed JSON
                if ($RequestResult.GetType().FullName -eq 'System.String')
                {
                    $RequestResult=$RequestResult.Replace("ResourceUri","resourceUri").Replace("ResourceId","resourceId")
                    $Result=$RequestResult|ConvertFrom-Json
                    Write-Output $Result|Select-Object -ExpandProperty value
                }
                else
                {
                    Write-Output $RequestResult|Select-Object -ExpandProperty value
                }
            }
            catch [System.Exception]
            {
                Write-Warning "[Get-ArmResourceMetric] Resource $item - $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the metric definition for the resource
    .PARAMETER ResourceId
        The desired resource id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmDiagnosticSetting
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion="2015-07-01"
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            $ArmUriBld.Path="$item/providers/microsoft.insights/diagnosticSettings/service"
            $ArmUriBld.Query="api-version=$ApiVersion"
            Write-Verbose "[Get-ArmDiagnosticSetting] Retrieving Diagnostic Settings for $item"
            $RequestResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if($RequestResult -ne $null)
            {
                Write-Output $RequestResult
            }
        }
    }
    END
    {

    }

}

<#
    .SYNOPSIS
        Retrieves the event log for the subscrption
    .PARAMETER ResourceId
        The desired subscription id
    .PARAMETER Filter
        The oauth event filter
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
    .PARAMETER ClassicApiVersion
        The ARM api version for classic resources
    .PARAMETER DigestEvents
        Whether to return digest events
#>
Function Get-ArmEventLog
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object')]
        [Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id')]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Switch]
        $DigestEvents,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [String]
        $Filter,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [System.String]
        $ApiVersion=$Script:DefaultEventLogApiVersion
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        if ([String]::IsNullOrEmpty($Filter))
        {
            $UtcNow=[DateTime]::UtcNow
            $End=New-Object System.DateTime($UtcNow.Year,$UtcNow.Month,$UtcNow.Day,$UtcNow.Hour,0,0)
            $StartTime=(New-Object System.DateTimeOffset($End.AddHours(-12))).ToString('o')
            $EndTime=(New-Object System.DateTimeOffset($End)).ToString('o')
            #Default filter
            $Filter="eventTimestamp ge '$StartTime' and eventTimestamp le '$EndTime' and eventChannels eq 'Admin, Operation'"
        }
        if ($DigestEvents.IsPresent) {
            $ApiVersion="2014-04-01"
        }
        $QueryStr="api-version=$ApiVersion&`$filter=$Filter"
        if ($Top -gt 0)
        {
           $QueryStr+="&`$top=$Top"
        }
        $ArmUriBld.Query=$QueryStr
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($Id in $SubscriptionId)
        {
            if ($DigestEvents.IsPresent)
            {
                $ArmUriBld.Path="subscriptions/$Id/providers/microsoft.insights/eventtypes/management/digestEvents"
            }
            else
            {
                $ArmUriBld.Path="subscriptions/$Id/providers/microsoft.insights/eventtypes/management/values"
            }
            if($Top -gt 0)
            {
                #These pages are 200 entries long
                $ResultPages=[System.Math]::Ceiling(($Top/200))
            }
            $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -LimitResultPages $ResultPages
            if ($ArmResult -ne $null) {
                Write-Output $ArmResult
            }
        }
    }
    END
    {

    }
}

Function Get-ArmEventCategory
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion='2015-04-01'
    )

    $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Path="providers/microsoft.insights/eventcategories"
    $ArmUriBld.Query="api-version=$ApiVersion"
    $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
    if($ArmResult -ne $null)
    {
        Write-Output $ArmResult
    }
}

#endregion

<#
    .SYNOPSIS
        Retrieves Azure Advisor recommendations from the subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmAdvisorRecommendation
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-05-09-preview"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Advisor/recommendations"
            $Recommendations=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if ($Recommendations -ne $null) {
                Write-Output $Recommendations
            }
        }
    }
    END
    {

    }
}

Function Get-ArmProviderOperation
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Provider,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [System.String[]]
        $ProviderNamespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2015-07-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object') {
            $ProviderNamespace=$Provider|Select-Object -ExpandProperty Namespace
        }
        foreach ($item in $ProviderNamespace)
        {
            $ArmUriBld.Path="/providers/Microsoft.Authorization/providerOperations/$Namespace"
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if ($Result -ne $null) {
                Write-Output $Result
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the classic administrators for a given subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmClassicAdministrator
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2015-06-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/classicAdministrators"
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if ($Result -ne $null) {
                Write-Output $Result
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the role assignments for a given subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER RoleName
        The role name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmRoleAssignment
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [String]
        $RoleName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-07-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleAssignments"
            if ([String]::IsNullOrEmpty($RoleName) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleAssignments/$RoleName"
            }

            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if($Result -ne $null)
            {
                Write-Output $Result
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the role definitions for a given subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER DefinitionName
        The role definition name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmRoleDefinition
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [String]
        $DefinitionName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-07-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleDefinitions" 
            if ([String]::IsNullOrEmpty($RoleName) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleDefinitions/$DefinitionName"
            }
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if($Result -ne $null)
            {
                Write-Output $Result
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the policy definitions for a given subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER DefinitionName
        The policy definition name
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPolicyDefinition
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [String]
        $DefinitionName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-12-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policydefinitions"
            if ([string]::IsNullOrEmpty($DefinitionName) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policydefinitions/$DefinitionName"
            }
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if($Result -ne $null)
            {
                Write-Output $Result
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the policy assignments for a given subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AssignmentName
        The policy assignment name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPolicyAssignment
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [String]
        $AssignmentName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-12-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            if ([string]::IsNullOrEmpty($AssignmentName) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policyassignments/$AssignmentName"
            }
            else
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policyassignments"
            }
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if ($Result -ne $null)
            {
                Write-Output $Result                    
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the compute quota statistics for a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmComputeUsage
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Compute/locations/$Location/usages"
            $Usages=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if($Usages -ne $null)
            {
                Write-Output $Usages
            }      
        }

    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the storage quota statistics for a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmStorageUsage
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-12-01"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Storage/usages"
            $Usages=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers            
            if ($Usages -ne $null) {
                Write-Output $Usages
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves usage statistics over the specified period for a given resource
        This is very haphazardly implemented in ARM
    .PARAMETER ResourceId
        The resource id(s) to retrieve usage for
    .PARAMETER Filter
        An OData filter to query
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
#>
Function Get-ArmResourceUsage
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='offset')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='default',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='filter',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='datetime',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='offset',ValueFromPipeline=$true)]
        [System.String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ParameterSetName='filter')]
        [String]
        $Filter,
        [Parameter(Mandatory=$true,ParameterSetName='filter')]
        [Parameter(Mandatory=$true,ParameterSetName='datetime')]
        [Parameter(Mandatory=$true,ParameterSetName='offset')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$true,ParameterSetName='datetime')]
        [System.DateTime]
        $UsageStart,
        [Parameter(Mandatory=$true,ParameterSetName='datetime')]
        [System.DateTime]
        $UsageEnd,
        [Parameter(Mandatory=$true,ParameterSetName='offset')]
        [System.DateTimeOffset]
        $UsageStartOffset,
        [Parameter(Mandatory=$true,ParameterSetName='offset')]
        [System.DateTimeOffset]
        $UsageEndOffset,
        [Parameter(Mandatory=$false,ParameterSetName='default')]
        [Switch]
        $GetDefault,
        [Parameter(Mandatory=$false,ParameterSetName='default')]
        [Parameter(Mandatory=$false,ParameterSetName='filter')]
        [Parameter(Mandatory=$false,ParameterSetName='datetime')]
        [Parameter(Mandatory=$false,ParameterSetName='offset')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor
    )

    BEGIN
    {
        if ($PSCmdlet.ParameterSetName -eq 'datetime') {
            $UsageStartOffset=New-Object System.DateTimeOffset($UsageStart)
            $UsageEndOffset=New-Object System.DateTimeOffset($UsageEnd)
        }
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            $ResourceData=$item|ConvertFrom-ArmResourceId
            $ArmUriBld.Path="$item/usages"
            #Resolve the api version
            $ResourceType="$($ResourceData.Namespace)/$($ResourceData.ResourceType)"
            $ApiVersions=GetResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId -AccessToken $AccessToken -ResourceType $ResourceType
            foreach ($ApiVersion in $ApiVersions)
            {
                Write-Verbose "Requesting instance $ResourceId with API version $ApiVersion"
                if($PSCmdlet.ParameterSetName -ne 'filter')
                {
                    $Filter="startTime eq $($UsageStartOffset.ToString('o')) and endTime eq $($UsageEndOffset.ToString('o'))"
                }
                if($PSCmdlet.ParameterSetName -eq 'GetDefault')
                {
                    $ArmUriBld.Query="api-version=$ApiVersion"
                }
                else
                {
                    $ArmUriBld.Query="api-version=$ApiVersion&`$filter=$Filter"
                }
                $Usages=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
                if($Usages -ne $null)
                {
                    Write-Output $Usages
                    break
                }
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the quota statistics for a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Namespace
        The provider namespace
    .PARAMETER Location
        The provider location
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmQuotaUsage
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-12-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/$Namespace/locations/$Location/usages"
            $Result=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json'
            Write-Output $Result
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the provider feature registrations
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Namespace
        The provider namespace
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmFeature
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $FeatureName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-12-01'
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken";Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq "object")
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/features"
            if([String]::IsNullOrEmpty($Namespace) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/providers/$Namespace/features"
            }
            if ([string]::IsNullOrEmpty($FeatureName) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/providers/$Namespace/features/$FeatureName"
            }
            $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if($ArmResult -ne $null)
            {
                Write-Output $ArmResult
            }
        }
    }
    END
    {
    }
}

<#
    .SYNOPSIS
        Registers the specified preview feature on the subscription(s)
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Namespace
        The provider namespace
    .PARAMETER FeatureName
        The preview feature name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Register-ArmFeature
{
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $FeatureName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-12-01'
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/providers/$Namespace/features/$FeatureName/register"
            try
            {
                $Result=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -Method Post -ErrorAction Stop
                Write-Output $Result
            }
            catch
            {
                Write-Warning "[Register-ArmFeature] $ApiVersion $item $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the available vm sizes for a subscription and location
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Location
        The location to query
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmVmSize
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Compute/locations/$Location/vmSizes"
            $VmSizes=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if ($VmSizes -ne $null) {
                Write-Output $VmSizes
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the tag name report for the subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmTagName
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-09-01",
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [Switch]
        $ExpandTagValues
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="subscriptions/$item/tagnames"
            if ($ExpandTagValues.IsPresent) {
                $ArmUriBld.Query="`$expand=tagvalues&api-version=$ApiVersion"
            }
            $ArmTags=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
            if($ArmTags -ne $null)
            {
                Write-Output $ArmTags
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves resource group deployments
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER ResourceGroupName
        The resource group name
    .PARAMETER DeploymentName
        The deployment name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
    .PARAMETER Filter
        An OData filter expression to apply
    .PARAMETER Top
        Limit the result set
#>
Function Get-ArmDeployment
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$false)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion="2016-09-01",
        [Parameter(Mandatory=$false)]
        [String]
        $Filter,
        [Parameter(Mandatory=$false)]
        [Int32]
        $Top
    )

    $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $UriQuery="api-version=$ApiVersion"
    if ([String]::IsNullOrEmpty($DeploymentName))
    {
        if ($Top -gt 0) {
            $UriQuery+="&`$top=$Top"
        }
        if([String]::IsNullOrEmpty($Filter) -eq $false)
        {
            $UriQuery+="&`$filter=$Filter"
        }
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments"
    }
    else
    {
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$DeploymentName"
    }
    $ArmUriBld.Query=$UriQuery
    $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'    
    if($ArmResult -ne $null)
    {
        Write-Output $ArmResult
    }
}

<#
    .SYNOPSIS
        Retrieves resource group deployment operations
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER ResourceGroupName
        The resource group name
    .PARAMETER DeploymentName
        The deployment name
    .PARAMETER OperationId
        The deployment operation id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
    .PARAMETER Filter
        An OData filter expression to apply
    .PARAMETER Top
        Limit the result set
#>
Function Get-ArmDeploymentOperation
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$false)]
        [String]
        $OperationId,
        [Parameter(Mandatory=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false)]
        [System.String]
        $ApiVersion="2016-09-01",
        [Parameter(Mandatory=$false)]
        [Int32]
        $Top
    )

    $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$DeploymentName/operations"
    if ($Top -gt 0 -and [String]::IsNullOrEmpty($OperationId))
    {
        $ArmUriBld.Query="api-version=$ApiVersion&`$top=$Top"
    }
    else
    {
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    if ([String]::IsNullOrEmpty($OperationId) -eq $false)
    {
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$DeploymentName/operations/$OperationId"
    }
    $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'
    if ($ArmResult -ne $null)
    {
        Write-Output $ArmResult
    }
}

<#
    .SYNOPSIS
        Retrieves the managed disks from a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ResourceGroup
        The resource group name
    .PARAMETER DiskName
        The managed disk name
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmVmManagedDisk
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $DiskName,        
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-04-30-preview"
    )

    BEGIN
    {
        if ([String]::IsNullOrEmpty($DiskName) -eq $false -and [string]::IsNullOrEmpty($ResourceGroup))
        {
            throw "A resource group must be specified!"
        }        
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            try
            {
                $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/disks"
                if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/disks"
                }
                if ([String]::IsNullOrEmpty($DiskName) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/disks/$DiskName"
                    $ArmDisk=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                    if ($ArmDisk -ne $null) {
                        Write-Output $ArmDisk
                    }                
                }
                else
                {
                    $ArmDisks=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
                    if($ArmDisks -ne $null)
                    {
                        Write-Output $ArmDisks
                    }                    
                }
            }
            catch
            {
                Write-Warning "[Get-ArmVmManagedDisk] $item $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the disk images from a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ResourceGroup
        The resource group name
    .PARAMETER ImageName
        The disk image name
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmVmDiskImage
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ImageName,        
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-04-30-preview"
    )

    BEGIN
    {
        if ([String]::IsNullOrEmpty($ImageName) -eq $false -and [string]::IsNullOrEmpty($ResourceGroup))
        {
            throw "A resource group must be specified!"
        }        
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            try
            {

                $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/images"
                if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/images"
                }
                if ([String]::IsNullOrEmpty($ImageName) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/images/$ImageName"
                    $ArmDisk=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                    if ($ArmDisk -ne $null) {
                        Write-Output $ArmDisk
                    }                    
                }
                else
                {
                    $ArmDisks=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
                    if($ArmDisks -ne $null)
                    {
                        Write-Output $ArmDisks
                    }                    
                }
            }
            catch
            {
                Write-Warning "[Get-ArmVmDiskImage] $item $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the vm snapshots from a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ResourceGroup
        The resource group name
    .PARAMETER SnapshotName
        The snapshot name
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmVmSnapshot
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $SnapshotName,  
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-04-30-preview"
    )

    BEGIN
    {
        if ([String]::IsNullOrEmpty($SnapshotName) -eq $false -and [string]::IsNullOrEmpty($ResourceGroup))
        {
            throw "A resource group must be specified!"
        }        
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            try
            {

                $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/snapshots"
                if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/snapshots"
                }
                if ([String]::IsNullOrEmpty($SnapshotName) -eq $false) {
                    $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/snapshots/$SnapshotName"
                    $ArmDisk=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                    if ($ArmDisk -ne $null) {
                        Write-Output $ArmDisk
                    }                    
                }
                else
                {
                    $ArmDisks=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers
                    if($ArmDisks -ne $null)
                    {
                        Write-Output $ArmDisks
                    }                    
                }
            }
            catch
            {
                Write-Warning "[Get-ArmVmSnapshot] $item $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the platform image publishers for a subscription
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Location
        The image location
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPlatformImagePublisher
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,   
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            try
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Compute/locations/$Location/publishers"
                $Usages=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                if($Usages -ne $null)
                {
                    Write-Output $Usages
                }
            }
            catch
            {
                Write-Warning "[Get-ArmPlatformImagePublisher] $ApiEndpoint $item $_"
            }
        }

    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the platform image publisher offers for a subscription
    .PARAMETER Publisher
        The image publisher as an object
    .PARAMETER PublisherId
        The image publisher id
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Location
        The image location
    .PARAMETER PublisherName
        The image publisher
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPlatformImagePublisherOffer
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='byPublisherObject')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true)]
        [psobject[]]
        $Publisher,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [string[]]
        $PublisherId,        
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,        
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in 'object','id') {
            if ($PSCmdlet.ParameterSetName -eq 'object')
            {
                $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
            }
            foreach ($item in $SubscriptionId) {
                $PublisherId+="/subscriptions/$item/providers/Microsoft.Compute/$Location/publishers/$PublisherName"
            }
        }
        if ($PSCmdlet.ParameterSetName -eq 'byPublisherObject')
        {
            $PublisherId=$Publisher|Select-Object -ExpandProperty id    
        }
        foreach ($ImagePublisher in $PublisherId)
        {
            try
            {
                $ArmUriBld.Path="$ImagePublisher/artifacttypes/vmimage/offers"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                if ($ArmResult -ne $null) {
                    Write-Output $ArmResult
                }                
            }
            catch {
                Write-Warning "[Get-ArmPlatformImagePublisherOffer] $ImagePublisher $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the platform image skus for a subscription
    .PARAMETER Offer
        The image offer as an object
    .PARAMETER OfferId
        The image offer id
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Location
        The image location
    .PARAMETER PublisherName
        The image publisher
    .PARAMETER OfferName
        The image offer
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPlatformImageSku
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='byPublisherObject')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true)]
        [psobject[]]
        $Offer,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [string[]]
        $OfferId,        
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,        
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $OfferName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in 'object','id') {
            if ($PSCmdlet.ParameterSetName -eq 'object')
            {
                $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
            }
            foreach ($item in $SubscriptionId) {
                $OfferId+="/subscriptions/$item/providers/Microsoft.Compute/$Location/publishers/$PublisherName/artifacttypes/vmimage/offers/$OfferName"
            }
        }
        if ($PSCmdlet.ParameterSetName -eq 'byPublisherObject')
        {
            $OfferId=$Offer|Select-Object -ExpandProperty id    
        }
        foreach ($ImageOffer in $OfferId)
        {
            try
            {
                $ArmUriBld.Path="$ImageOffer/skus"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                if ($ArmResult -ne $null) {
                    Write-Output $ArmResult
                }                
            }
            catch {
                Write-Warning "[Get-ArmPlatformImageSku] $ImagePublisher $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

<#
    .SYNOPSIS
        Retrieves the platform image versions for a subscription
    .PARAMETER ImageSku
        The image SKU as an object
    .PARAMETER ImageSkuId
        The image SKU id
    .PARAMETER Subscription
        The subscription as an object
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Location
        The image location
    .PARAMETER PublisherName
        The image publisher
    .PARAMETER OfferName
        The image offer
    .PARAMETER SkuName
        The image SKU name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmPlatformImageVersion
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='byPublisherObject')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true)]
        [psobject[]]
        $ImageSku,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [string[]]
        $ImageSkuId,        
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [psobject[]]
        $Subscription,        
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $OfferName,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $SkuName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='id')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId')]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject')]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2017-03-30"
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in 'object','id') {
            if ($PSCmdlet.ParameterSetName -eq 'object')
            {
                $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
            }
            foreach ($item in $SubscriptionId) {
                $ImageSkuId+="/subscriptions/$item/providers/Microsoft.Compute/$Location/publishers/$PublisherName/artifacttypes/vmimage/offers/$OfferName/skus/$SkuName"
            }
        }
        if ($PSCmdlet.ParameterSetName -eq 'byPublisherObject')
        {
            $ImageSkuId=$ImageSku|Select-Object -ExpandProperty id    
        }
        foreach ($Sku in $ImageSkuId)
        {
            try
            {
                $ArmUriBld.Path="$Sku/versions"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ErrorAction Stop
                if ($ArmResult -ne $null) {
                    Write-Output $ArmResult
                }                
            }
            catch {
                Write-Warning "[Get-ArmPlatformImageVersion] $ImagePublisher $ApiVersion $_"
            }
        }
    }
    END
    {

    }
}

Function Get-ArmBillingInvoice
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,      
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $InvoiceName,      
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $Filter,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String[]]
        $Expand,            
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [Switch]
        $ExpandDownloadUrl,        
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion="2017-02-27-preview" 
    )

    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $Headers=@{Authorization="Bearer $($AccessToken)";Accept="application/json";}
        $ArmQuery="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($SubId in $SubscriptionId)
        {
            try
            {
                if ([string]::IsNullOrEmpty($InvoiceName))
                {
                    $ArmUriBld.Path="subscriptions/$SubId/providers/Microsoft.Billing/invoices"                    
                    if ([String]::IsNullOrEmpty($Filter) -eq $false) {
                        $ArmQuery+="&`$filter=$Filter"
                    }
                    if ($Top -gt 0) {
                        $ArmQuery+="&`$top=$Top"
                    }
                    if ($ExpandDownloadUrl.IsPresent) {
                        if($Expand -notcontains "downloadUrl")
                        {
                            $Expand+="downloadUrl"
                        }
                    }
                    if ($Expand -ne $null)
                    {
                        $ArmQuery+="&`$expand=$([String]::Join(',',$Expand))"
                    }
                }
                else
                {
                    $ArmUriBld.Path="subscriptions/$SubId/providers/Microsoft.Billing/invoices/$InvoiceName"
                    
                }
                $ArmUriBld.Query=$ArmQuery
                $ArmResult=GetArmODataResult -Uri $ArmUriBld.Uri -Headers $Headers -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'
                if($ArmResult -ne $null)
                {
                    Write-Output $ArmResult
                }
            }
            catch
            {
                Write-Warning "[Get-ArmBillingInvoice] Error retrieving invoice(s) $_"
            }
        }
    }
    END
    {

    }
}