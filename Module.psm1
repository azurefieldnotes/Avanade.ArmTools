<#
    Avanade.ArmTools
#>

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
        $ApiVersion='2016-08-01'
    )

    BEGIN
    {
        $Headers=@{
            'Authorization'="Bearer $AccessToken";
            'Accept'='application/json';
        }
        $UriBuilder=New-Object System.UriBuilder($ApiEndpoint)
        $UriBuilder.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -in 'object','objectWithName') {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($id in $SubscriptionId) 
        {
            if ($PSCmdlet.ParameterSetName -in 'objectWithName','idWithName') {
                $UriBuilder.Path="/subscriptions/$Id/resourcegroups/$ResourceGroupName/providers/Microsoft.Web/sites/$WebsiteName"
                $ArmResult=Invoke-RestMethod -Uri $UriBuilder.Uri -Headers $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            else {
                $UriBuilder.Path="/subscriptions/$Id/providers/Microsoft.Web/sites"
                do 
                {
                    try 
                    {
                        $ArmResult=Invoke-RestMethod -Uri $UriBuilder.Uri -Headers $Headers -ContentType 'application/json'
                        Write-Output $ArmResult.value
                        $nextLink=$ArmResult.nextLink
                        $UriBuilder=New-Object System.UriBuilder($nextLink)                
                    }
                    catch [System.Exception] {
                        Write-Warning $_
                        $nextLink=$null
                    }
                } 
                while ($nextLink -ne $null)
            }
        }
    }
    END
    {

    }
}

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
        $ApiVersion='2016-08-01'
    )

    BEGIN
    {
        $Headers=@{
            'Authorization'="Bearer $AccessToken";
            'Accept'='application/json';
        }
        if ($PSCmdlet.ParameterSetName -eq "object") {
            $SubscriptionId=$Subscription.subscriptionId
            $ArmSite=Get-ArmWebSite -SubscriptionId $SubscriptionId -WebsiteName $WebsiteName `
                -ResourceGroupName $ResourceGroupName -AccessToken $AccessToken `
                -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
            $Website+=$ArmSite
        }          
    }
    PROCESS
    {
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
        Retrieves Azure subscriptions
    .PARAMETER SubscriptionId
        The azure subscription id
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmSubscription
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )

    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Query="api-version=$ApiVersion"
    $ArmUriBld.Path='subscriptions'
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        $ArmUriBld.Path+="/$SubscriptionId"
    }
    $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        Write-Output $ArmResult
    }
    else {
        Write-Output $ArmResult.value
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
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmProvider
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
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

        if($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId)) {
            $ArmUriBld.Path="providers"
            if([String]::IsNullOrEmpty($Namespace) -eq $false)
            {
                $ArmUriBld.Path="providers/$Namespace"
            }
            $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
            if([String]::IsNullOrEmpty($Namespace) -eq $false) {
                Write-Output $ArmResult
            }
            else {
                #TODO: Could this page?
                Write-Output $ArmResult.value
            }
        }
        else {
            if($PSCmdlet.ParameterSetName -eq 'object')
            {
                foreach ($sub in $Subscription) {
                    $SubscriptionId+=$sub.subscriptionId
                }
            }
            foreach ($item in $SubscriptionId) {
                $ArmUriBld.Path="subscriptions/$item/providers"
                if([String]::IsNullOrEmpty($Namespace) -eq $false)
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                }
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                if([String]::IsNullOrEmpty($Namespace) -eq $false) {
                    Write-Output $ArmResult
                }
                else {
                    #TODO: Could this page?
                    Write-Output $ArmResult.value
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
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmResourceType
{
    [CmdletBinding(DefaultParameterSetName='idNamespace')]
    param
    (
        [Parameter(Mandatory=$false,ParameterSetName='idType',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='objectType',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace',ValueFromPipeline=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace')]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace')]
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
        if($PSCmdlet.ParameterSetName -in 'objectType','idType') {
            $Namespace=$ResourceType.Split('/')|Select-Object -First 1
            $TypeName=$ResourceType.Replace("$Namespace/",[String]::Empty)
        }
    }
    PROCESS
    {
        if ($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId)) {
            if($PSCmdlet.ParameterSetName -in 'objectType','idType') {
                $ArmUriBld.Path="providers/$Namespace"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                $ResProvType=$ArmResult.resourceTypes|Where-Object{$_.resourceType -eq $TypeName }|Select-Object -First 1
                if ($ResProvType -ne $null) {
                    Write-Output $ResProvType
                }
                else {
                    Write-Warning "$ResourceType was not found in subscription:$item"
                }
            }
            else {
                $ArmUriBld.Path="providers/$Namespace"
                $Providers=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                foreach ($Provider in $Providers)
                {
                    Write-Output $Provider.resourceTypes
                }
            }            
        }
        else {
            if($PSCmdlet.ParameterSetName -eq 'object')
            {
                foreach ($sub in $Subscription) {
                    $SubscriptionId+=$sub.subscriptionId
                }
            }
            foreach ($item in $SubscriptionId) {
                if($PSCmdlet.ParameterSetName -in 'objectType','idType') {
                    $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                    $ResProvType=$ArmResult.resourceTypes|Where-Object{$_.resourceType -eq $TypeName }|Select-Object -First 1
                    if ($ResProvType -ne $null) {
                        Write-Output $ResProvType
                    }
                    else {
                        Write-Warning "$ResourceType was not found in subscription:$item"
                    }
                }
                else {
                    $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
                    $Providers=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                    foreach ($Provider in $Providers)
                    {
                        Write-Output $Provider.resourceTypes
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
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmResourceTypeApiVersion
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
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

    switch ($PSCmdlet.ParameterSetName) {
        "explicit" {
            $ArmResourceType=Get-ArmResourceType -SubscriptionId $SubscriptionId `
                -ResourceType $ResourceType -AccessToken $AccessToken `
                -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
        }
        "object" {
            $ArmResourceType=Get-ArmResourceType -Subscription $Subscription `
                -ResourceType $ResourceType -AccessToken $AccessToken `
                -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
        }
    }
    return $ArmResourceType.apiVersions
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
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmResourceGroup
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
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
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId) {
            $ArmUriBld.Path="subscriptions/$item/resourcegroups"
            if([String]::IsNullOrEmpty($Name) -eq $false)
            {
                $ArmUriBld.Path+="/$Name"
            }
            try {
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Continue
                if([String]::IsNullOrEmpty($Name) -eq $false) {
                    Write-Output $ArmResult
                }
                else {
                    Write-Output $ArmResult.value
                }
            }
            catch [System.Exception] {
                Write-Warning $_
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
    .PARAMETER ApiVersions
        The ARM api version

#>
Function Get-ArmLocation
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipeline=$true)]
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
        if ($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId)) {     
            $ArmUriBld.Path='locations'
            $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
            if([String]::IsNullOrEmpty($Location) -eq $false) {
                $ArmLocation=$ArmResult.value|Where-Object{$_.name -eq $Location -or $_.displayName -eq $Location}|Select-Object -First 1
                if($ArmLocation -ne $null) {
                    Write-Output $ArmLocation
                }
                else {
                    Write-Warning "There is no location $Location available"
                }
            }
            else {
                Write-Output $ArmResult.value
            }
        }
        else {
            if($PSCmdlet.ParameterSetName -eq 'object')
            {
                foreach ($sub in $Subscription) {
                    $SubscriptionId+=$sub.subscriptionId
                }
            }
            foreach ($item in $SubscriptionId) {
                $ArmUriBld.Path="subscriptions/$item/locations"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json'
                if([String]::IsNullOrEmpty($Location) -eq $false) {
                $ArmLocation=$ArmResult.value|Where-Object{$_.name -eq $Location -or $_.displayName -eq $Location}|Select-Object -First 1
                    if($ArmLocation -ne $null) {
                        Write-Output $ArmLocation
                    }
                    else {
                        Write-Warning "There is no location $Location available"
                    }
                }
                else {
                    Write-Output $ArmResult.value
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
    [CmdletBinding(DefaultParameterSetName='explicit')]
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
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId) 
        {
            $ArmUriBld.Path="subscriptions/$item"
            if([String]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                $ArmUriBld.Path+="/resourceGroups/$ResourceGroup"
            }
            if([String]::IsNullOrEmpty($ResourceType) -eq $false -and [String]::IsNullOrEmpty($ResourceName) -eq $false){
                $ArmUriBld.Path+="/providers/$ResourceType/$ResourceName"
            }
            $ArmUriBld.Path+="/providers/microsoft.authorization/locks"            
            do
            {
                try 
                {
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Continue
                    Write-Output $ArmResult.value
                    if([String]::IsNullOrEmpty($nextLink) -eq $false)
                    {
                        Write-Verbose "More results @ $nextLink"
                        $ArmUriBld=New-Object System.UriBuilder($nextLink)
                    }                    
                }
                catch [System.Exception] {
                    $nextLink=$null
                    Write-Warning "Subscription $item - $_"
                }
            }
            while ($nextLink -ne $null)          
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
    .PARAMETER ApiVersions
        The ARM api version
#>
Function Get-ArmFeature
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
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
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId) 
        {
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/features"
            do 
            {
                try 
                {
                    if([String]::IsNullOrEmpty($Namespace) -eq $false)
                    {
                        $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Features/providers/$Namespace/features"
                    }
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Continue
                    Write-Output $ArmResult.value
                    if([String]::IsNullOrEmpty($nextLink) -eq $false)
                    {
                        Write-Verbose "More results @ $nextLink"
                        $ArmUriBld=New-Object System.UriBuilder($nextLink)
                    }
                }
                catch [System.Exception] {
                    $nextLink=$null
                    Write-Warning "Subscription $item - $_"                                        
                }                
            } while ($nextLink -ne $null)          
        }
    }
    END{}

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
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version        
#>
Function Get-ArmResource
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
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
        $Filter,        
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]        
        [System.Int32]
        $Top,              
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
        $QueryStr+="&api-version=$ApiVersion"
        if ($Top -gt 0) {
            $QueryStr+="&`$top=$Top"
        }
        if ([String]::IsNullOrEmpty($Filter) -eq $false) {
            $QueryStr+="&`$filter=$Filter"
        }
        $QueryStr+="&api-version=$ApiVersion"
        $ArmUriBld.Query=$QueryStr
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId) 
        {
            $ArmUriBld.Path="subscriptions/$item/resources"
            if ([String]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                $ArmUriBld.Path+="/resourceGroups/$ResourceGroup"
            }
            do
            {
                try 
                {
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Continue
                    Write-Output $ArmResult.value
                    if([String]::IsNullOrEmpty($nextLink) -eq $false)
                    {
                        Write-Verbose "More results @ $nextLink"
                        $ArmUriBld=New-Object System.UriBuilder($nextLink)
                    }                    
                }
                catch [System.Exception] {
                    $nextLink=$null
                    Write-Warning "Subscription $item - $_"
                }
            }
            while ($nextLink -ne $null)          
        }        
    }
    END{}

}

<#
    .SYNOPSIS
        Retrieves detailed resource instance(s)
    .PARAMETER SubscriptionId
        The azure subscription id(s)
    .PARAMETER Subscription
        The azure subscription(s)
    .PARAMETER Id
        The resource id to retrieve
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version        
#>
Function Get-ArmResourceInstance
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [String[]]
        $Id,
        [Parameter(Mandatory=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor
    )

    BEGIN
    {
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    }
    PROCESS
    {
        foreach ($ResourceId in $Id) {
            $ArmResult=$null
            $ResourceData=$ResourceId|ConvertFrom-ArmResourceId
            #Resolve the api version
            $ResourceType="$($ResourceData.Namespace)/$($ResourceData.ResourceType)"
            $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId `
                -ResourceType $ResourceType `
                -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint
            foreach ($ApiVersion in $ApiVersions) {
                Write-Verbose "Requesting instance $ResourceId with API version $ApiVersion"
                $ArmUriBld.Path=$ResourceId
                $ArmUriBld.Query="api-version=$ApiVersion"
                try {
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders -ErrorAction Stop
                    break
                }
                catch [System.Exception] {
                    Write-Warning "$ResourceId - $_"
                }
            }
            if ($ArmResult -ne $null) {
                Write-Output $ArmResult
            }
        }
    }
    END{}
}

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
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset')]
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
        if ($PSCmdlet.ParameterSetName -in 'object','explicit') {
            if ($Granularity -eq "Hourly") {
                $StartTimeOffset=New-Object System.DateTimeOffset($StartTime.Year,$StartTime.Month,$StartTime.Day,$StartTime.Hour,0,0,0)
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,$StartTime.Hour,0,0,0)
            }
            else {
                $StartTimeOffset=New-Object System.DateTimeOffset($StartTime.Year,$StartTime.Month,$StartTime.Day,0,0,0,0)
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,0,0,0,0)
            }
        }
        else {
            if ($Granularity -eq "Hourly") {
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,$StartTime.Hour,0,0,0)
            }
            else {
                $EndTimeOffset=New-Object System.DateTimeOffset($EndTime.Year,$EndTime.Month,$EndTime.Day,0,0,0,0)
            }
        }
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $StartTimeString=[Uri]::EscapeDataString($StartTimeOffset.ToString('o'))
        $EndTimeString=[Uri]::EscapeDataString($EndTimeOffset.ToString('o'))
        $ArmUriBld.Query="api-version=$ApiVersion&reportedStartTime=$($StartTimeString)&reportedEndTime=$($EndTimeString)" + 
            "&aggregationGranularity=$Granularity&showDetails=$($ShowDetails.IsPresent)"
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId)
        {
            $ResultPages=0
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/UsageAggregates"
            do
            {
                $ResultPages++
                try 
                {
                    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -ErrorAction Stop
                    Write-Output $ArmResult.value
                    if ($LimitResultPages -gt 0) {
                        if ($ResultPages -lt $LimitResultPages) {
                            $nextLink=$ArmResult.nextLink
                        }
                        else {
                            $nextLink=$null
                            Write-Verbose "Stopped iterating at $ResultPages pages. More data available?:$([string]::IsNullOrEmpty($nextLink))"
                        }
                    }            
                    else {
                        $nextLink=$ArmResult.nextLink
                    }
                    if([String]::IsNullOrEmpty($nextLink) -eq $false)
                    {
                        Write-Verbose "More results @ $nextLink"
                        $ArmUriBld=New-Object System.UriBuilder($nextLink)
                    }                    
                }
                catch [System.Exception] {
                    Write-Warning "Subscription $item - $_"
                    $nextLink=$null
                }
            } while ($nextLink -ne $null)
        }
    }
    END{}
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
    [CmdletBinding(DefaultParameterSetName='explicit')]
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
        $ApiVersion='2015-06-01-preview'
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
        $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        if ($PSBoundParameters.Locale) {
            $Locale=$PSBoundParameters.Locale    
        }
        else {
            $Locale='en-US'
        }
        if ($PSBoundParameters.RegionInfo) {
            $RegionInfo=$PSBoundParameters.RegionInfo    
        }
        else {
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
        if($PSCmdlet.ParameterSetName -eq 'object')
        {
            foreach ($sub in $Subscription) {
                $SubscriptionId+=$sub.subscriptionId
            }
        }
        foreach ($item in $SubscriptionId)
        {
            Write-Verbose "Subscription:$item OfferDurableId:$OfferDurableId Locale:$Locale Currency:$($DesiredRegion.ISOCurrencySymbol)"
            $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/RateCard"          
            try
            {
                $Result=Invoke-RestMethod -Uri $ArmUriBld.Uri -Headers $AuthHeaders -ContentType 'application/json' -ErrorAction Continue
                Write-Output $Result
            }
            catch [System.Exception]
            { 
                Write-Warning "Subscription $item - $_"
            }
        }
    }
    END{}
}