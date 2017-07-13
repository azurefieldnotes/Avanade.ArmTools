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
$Script:DefaultKeyVaultApiVersion='2016-10-01'
#endregion

#region Helpers

#region 'Private' Methods

Function CreateDynamicValidateSetParameter
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

#endregion

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
    BEGIN
    {
    }
    PROCESS
    {
        foreach ($ResourceId in $Id)
        {
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
    END
    {
    }
}

<#
    .SYNOPSIS
        Invokes a web request against an ARM compliant URI
    .PARAMETER Uri
        The absolute uri for the request
    .PARAMETER Method
        The request method
    .PARAMETER Body
        The body for the request
    .PARAMETER AdditionalHeaders
        Additional headers for the request
    .PARAMETER AccessToken
        The bearer token
    .PARAMETER ValueProperty
        The odata value property name
    .PARAMETER NextLinkProperty
        The odata next link property name
    .PARAMETER LimitResultPages
        Whether to limit Odata result pages
    .PARAMETER ContentAction
        A scriptblock for modifying the text prior to deserializing JSON
#>
Function Invoke-ArmRequest
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [uri]
        $Uri,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [string]
        $ContentType='application/json',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Object]
        $Body,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method="GET",
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [string]
        $AccessToken,
        [ValidateNotNull()]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Collections.IDictionary]
        $AdditionalHeaders=@{Accept='application/json'},
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [string]
        $ValueProperty='value',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [String]
        $NextLinkProperty='nextLink',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [int]
        $LimitResultPages,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [scriptblock]
        $ContentAction={param([String]$content)Write-Output $content},
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [int]
        $RequestDelayMilliseconds=100
    )
    $ResultPages=0
    $TotalItems=0
    $RequestHeaders=$AdditionalHeaders
    $RequestHeaders['client-request-id']=[Guid]::NewGuid().ToString()
    $RequestHeaders['User-Agent']="PowerShell $($PSVersionTable.PSVersion.ToString())"
    $RequestHeaders['Authorization']="Bearer $AccessToken"
    $BaseUri="$($Uri.Scheme)://$($Uri.Host)"
    $RequestParams=@{
        Headers=$RequestHeaders;
        Uri=$Uri;
        ContentType=$ContentType;
        Method=$Method;
    }
    if ($Body -ne $null) {
        $RequestParams['Body']=$Body
    }
    $RequestResult=$null
    try
    {
        $Response=Invoke-WebRequest @RequestParams -UseBasicParsing -ErrorAction Stop
        Write-Verbose "[Invoke-ArmRequest]$Method $Uri Response:$($Response.StatusCode)-$($Response.StatusDescription) Content-Length:$($Response.RawContentLength)"
        $RequestResult=Invoke-Command -ScriptBlock $ContentAction -ArgumentList $Response.Content|ConvertFrom-Json
    }
    catch
    {
        #See if we can unwind an exception from a response
        if($_.Exception.Response -ne $null)
        {
            $ExceptionResponse=$_.Exception.Response
            $ErrorStream=$ExceptionResponse.GetResponseStream()
            $ErrorStream.Position=0
            $StreamReader = New-Object System.IO.StreamReader($ErrorStream)
            try
            {
                $ErrorContent=$StreamReader.ReadToEnd()
                $StreamReader.Close()
                if(-not [String]::IsNullOrEmpty($ErrorContent))
                {
                    $ErrorObject=$ErrorContent|ConvertFrom-Json
                    if (-not [String]::IsNullOrEmpty($ErrorProperty) -and  $ErrorObject.PSobject.Properties.name -match $ErrorProperty)
                    {
                        $ErrorContent=($ErrorObject|Select-Object -ExpandProperty $ErrorProperty)|ConvertTo-Json
                    }
                }
            }
            catch
            {
            }
            finally
            {
                $StreamReader.Close()
            }
            $ErrorMessage="Error: $($ExceptionResponse.Method) $($ExceptionResponse.ResponseUri) Returned $($ExceptionResponse.StatusCode) $ErrorContent"
        }
        else
        {
            $ErrorMessage="An error occurred $_"
        }
        Write-Verbose "[Invoke-ArmRequest] $ErrorMessage"
        throw $ErrorMessage
    }
    #Should never get here null
    if($RequestResult -ne $null)
    {
        if ($RequestResult.PSobject.Properties.name -match $ValueProperty)
        {
            $Result=$RequestResult|Select-Object -ExpandProperty $ValueProperty
            $TotalItems+=$Result.Count
            Write-Output $Result
        }
        else
        {
            Write-Output $RequestResult
            $TotalItems++ #not sure why I am incrementing..
        }
        #Loop to aggregate OData continutation tokens
        while ($RequestResult.PSobject.Properties.name -match $NextLinkProperty)
        {
            #Throttle the requests a bit..
            Start-Sleep -Milliseconds $RequestDelayMilliseconds
            $ResultPages++
            $UriBld=New-Object System.UriBuilder($BaseUri)
            $NextUri=$RequestResult|Select-Object -ExpandProperty $NextLinkProperty
            if($LimitResultPages -gt 0 -and $ResultPages -eq $LimitResultPages -or [String]::IsNullOrEmpty($NextUri))
            {
                break
            }
            Write-Verbose "[Invoke-ArmRequest] Item Count:$TotalItems Page:$ResultPages More Items available @ $NextUri"
            #Is this an absolute or relative uri?
            if($NextUri -match "$BaseUri*")
            {
                $UriBld=New-Object System.UriBuilder($NextUri)
            }
            else
            {
                $Path=$NextUri.Split('?')|Select-Object -First 1
                $NextQuery=[Uri]::UnescapeDataString(($NextUri.Split('?')|Select-Object -Last 1))
                $UriBld.Path=$Path
                $UriBld.Query=$NextQuery
            }
            try
            {
                $RequestParams['Uri']=$UriBld.Uri
                $Response=Invoke-WebRequest @RequestParams -UseBasicParsing -ErrorAction Stop
                Write-Verbose "[Invoke-ArmRequest]$Method $Uri Response:$($Response.StatusCode)-$($Response.StatusDescription) Content-Length:$($Response.RawContentLength)"
                $RequestResult=Invoke-Command -ScriptBlock $ContentAction -ArgumentList $Response.Content|ConvertFrom-Json
                if ($RequestResult.PSobject.Properties.name -match $ValueProperty)
                {
                    $Result=$RequestResult|Select-Object -ExpandProperty $ValueProperty
                    $TotalItems+=$Result.Count
                    Write-Output $Result
                }
                else
                {
                    Write-Output $RequestResult
                    $TotalItems++ #not sure why I am incrementing..
                }
            }
            catch
            {
                #See if we can unwind an exception from a response
                if($_.Exception.Response -ne $null)
                {
                    $ExceptionResponse=$_.Exception.Response
                    $ErrorStream=$ExceptionResponse.GetResponseStream()
                    $ErrorStream.Position=0
                    $StreamReader = New-Object System.IO.StreamReader($ErrorStream)
                    try
                    {
                        $ErrorContent=$StreamReader.ReadToEnd()
                        $StreamReader.Close()
                        if(-not [String]::IsNullOrEmpty($ErrorContent))
                        {
                            $ErrorObject=$ErrorContent|ConvertFrom-Json
                            if (-not [String]::IsNullOrEmpty($ErrorProperty) -and  $ErrorObject.PSobject.Properties.name -match $ErrorProperty)
                            {
                                $ErrorContent=($ErrorObject|Select-Object -ExpandProperty $ErrorProperty)|ConvertTo-Json
                            }
                        }
                    }
                    catch
                    {
                    }
                    finally
                    {
                        $StreamReader.Close()
                    }
                    $ErrorMessage="Error: $($ExceptionResponse.Method) $($ExceptionResponse.ResponseUri) Returned $($ExceptionResponse.StatusCode) $ErrorContent"
                }
                else
                {
                    $ErrorMessage="An error occurred $_"
                }
                Write-Verbose "[Invoke-ArmRequest] $ErrorMessage"
                throw $ErrorMessage
            }
        }
    }
}

#endregion

#region Resources

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
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $IncludeDetails
    )
    $Headers=@{Accept='application/json';}
    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Query="api-version=$ApiVersion&includeDetails=$($IncludeDetails.IsPresent)"
    $ArmUriBld.Path='subscriptions'
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        $ArmUriBld.Path+="/$SubscriptionId"
    }
    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -ContentType 'application/json' -AccessToken $AccessToken -AdditionalHeaders $Headers
    if ($ArmResult -ne $null) {
        Write-Output $ArmResult
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{'Accept'='application/json';}
    }
    PROCESS
    {
        foreach ($token in $AccessToken)
        {
            $ArmUriBld=New-Object System.UriBuilder($Script:DefaultArmFrontDoor)
            $ArmUriBld.Path='tenants'
            $ArmUriBld.Query="api-version=$ApiVersion"
            $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -ContentType 'application/json' -AccessToken $token -AdditionalHeaders $Headers
            if ($ArmResult -ne $null) {
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
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Name,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{'Accept'="application/json"}
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -ContentType 'application/json' -AdditionalHeaders $Headers -AccessToken $AccessToken
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
        Creates or updates a resource group
    .DESCRIPTION
        Creates a resource group
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Name
        The resource group name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function New-ArmResourceGroup
{
    [CmdletBinding()]
    param
    (  
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $Name,
        [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName = $true)]
        [String]
        $Location,
        [Parameter(Mandatory = $false,ValueFromPipelineByPropertyName = $true)]
        [String]
        $ManagedBy,
        [Parameter(Mandatory = $false,ValueFromPipelineByPropertyName = $true)]
        [System.Collections.IDictionary]
        $Tags,        
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,   
        [System.String]
        $ApiVersion="2016-07-01"
    )
    PROCESS
    {
        Write-Verbose "[New-ArmResourceGroup] Creating resource group $Name on Subscription $SubscriptionId"
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourceGroups/$Name"
        $ArmUriBld.Query="api-version=$ApiVersion"
        $ResGroupProperties = [ordered]@{
            'id'         = "/subscriptions/$SubscriptionId/resourceGroups/$Name";
            'name'       = $Name;
            'location'   = $Location;
            'properties' = [ordered]@{}
        }
        if (-not [String]::IsNullOrEmpty($ManagedBy))
        {
            $ResGroupProperties.properties.Add('managedBy',$ManagedBy)
        }
        if (($Tags -ne $null) -and ($Tags.Count -gt 0))
        {
            $ResGroupProperties.properties.Add('tags',$Tags)
        }        
        $RequestParams=@{
            Uri=$ArmUriBld.Uri;
            Method='PUT';
            AccessToken=$AccessToken;
            AdditionalHeaders=@{'Accept'='application/json'};
            Body=$(New-Object psobject -Property $ResGroupProperties|ConvertTo-Json -Depth 4)
            ErrorAction='STOP'
        }
        $Result=Invoke-ArmRequest @RequestParams
        Write-Output $Result
    }
}

<#
    .SYNOPSIS
        Removes a resource group
    .DESCRIPTION
        Removes a resource group
    .PARAMETER Id
        The resource group id
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER Name
        The resource group name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Remove-ArmResourceGroup
{
    [CmdletBinding()]
    param
    (  
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [String[]]
        $Id,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [String]
        $Name,                     
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [String]
        $AccessToken,
        [System.Uri]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,   
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [System.String]
        $ApiVersion="2016-07-01"
    )
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'explicit')
        {
            $Id=@("/subscriptions/$SubscriptionId/resourceGroups/$Name")
        }
        foreach($ResourceGroupId in $Id)
        {
            Write-Verbose "[Remove-ArmResourceGroup] Removing resource group $ResourceGroupId"
            $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
            $ArmUriBld.Path=$ResourceGroupId
            $ArmUriBld.Query="api-version=$ApiVersion"
            $RequestParams=@{
                Uri=$ArmUriBld.Uri;
                Method='DELETE';
                AccessToken=$AccessToken;
                ErrorAction='Stop'
            }
            Invoke-ArmRequest @RequestParams|Out-Null
        }
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
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Filter,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$true,ParameterSetName='objectByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicitByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectByNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitByNamespace',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json';}
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
            try
            {
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            catch {
                Write-Warning "[Get-ArmResource] $item $_"
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String[]]
        $Id,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [PSObject[]]
        $Resource,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $ExpandProperties,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json';}
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
            #Is the provider type cached??
            if ($Script:SubscriptionProviderApiVersionCache.ContainsKey($ResourceData.SubscriptionId))
            {
                $SubscriptionCache=$Script:SubscriptionProviderApiVersionCache[$ResourceData.SubscriptionId]
                #Is the type there?
                if ($SubscriptionCache.ContainsKey($ResourceType))
                {
                    $ApiVersions=$SubscriptionCache[$ResourceType]
                }
                else
                {
                    $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId -ResourceType $ResourceType `
                        -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint
                    $SubscriptionCache.Add($ResourceType,$ApiVersions)
                    $Script:SubscriptionProviderApiVersionCache[$ResourceData.SubscriptionId]=$SubscriptionCache
                }
            }
            else
            {
                $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId -ResourceType $ResourceType `
                    -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
                $Script:SubscriptionProviderApiVersionCache.Add($ResourceData.SubscriptionId,@{$ResourceType=$ApiVersions})
            }
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
                    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
                    if ($ArmResult -ne $null) {
                        break
                    }
                }
                catch [System.Exception]
                {
                    Write-Warning "[Get-ArmResourceInstance] $ResourceId using api version $Version - $_"
                }
            }
            if ($ArmResult -ne $null) {
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
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{'Accept'="application/json"}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        if ($Subscription -eq $null -and [String]::IsNullOrEmpty($SubscriptionId))
        {
            $ArmUriBld.Path='locations'
            $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
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
                try
                {
                    $ArmUriBld.Path="subscriptions/$item/locations"
                    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
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
                catch {
                    Write-Warning "[Get-ArmLocation] $item $_"
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
        Retrieves the endpoint metadata for a given resource manager endpoint
    .PARAMETER ArmFrontDoor
        The resource manager Uri
    .PARAMETER ApiVersion
        The resource manager API version
#>
Function Get-ArmEndpoints
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri[]]
        $ArmFrontDoor=@($Script:DefaultArmFrontDoor),
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri[]]
        $ApiVersion=@($Script:DefaultArmApiVersion)
    )
    BEGIN
    {
        
    }
    PROCESS
    {
        foreach ($FrontDoor in $ArmFrontDoor)
        {
            try
            {
                $ArmUriBld=New-Object System.UriBuilder($FrontDoor)
                $ArmUriBld.Path='/metadata/endpoints'
                $ArmUriBld.Query="api-version=$ApiVersion"
                $Endpoints=Invoke-RestMethod -Method Get -Uri $ArmUriBld.Uri -ContentType 'application/json' -ErrorAction Stop
                if ($Endpoints -ne $null) {
                    Write-Output $Endpoints
                }
            }
            catch {
                Write-Warning "[Get-ArmEndpoints] Error retrieving resource manager endpoints $_"
            }
        }
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
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [String]
        $ExpandFilter
    )
    BEGIN
    {
        $Headers=@{Accept='application/json';}
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
            if([String]::IsNullOrEmpty($Namespace) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/providers/$Namespace"
            }
            else
            {
                if ([String]::IsNullOrEmpty($ExpandFilter) -eq $false)
                {
                    $ArmUriBld.Query="api-version=$ApiVersion&`$expand=$ExpandFilter"
                }
            }
            try
            {
                $NamespaceResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                if($NamespaceResult -ne $null)
                {
                    Write-Output $NamespaceResult
                }
            }
            catch {
                Write-Warning "[Get-ArmProvider] $item $_"
            }
        }
    }
    END
    {
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -Method Post -ContentType 'application/json'
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -Method Post -ContentType 'application/json'
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
        Removes an ARM item (Resource/Resource Group)
#>
Function Remove-ArmItem
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Resource,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
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
                Invoke-ArmRequest -Uri $UriBuilder.Uri -Method Delete -AccessToken $AccessToken|Out-Null
            }
            catch
            {
                Write-Warning "[Remove-ArmItem] Failed deleting $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace',ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[A-Za-z]+[\.]+[A-Za-z]+([\.]+[A-Za-z]+)*')]
        [System.String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='objectType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idType',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$true,ParameterSetName='objectType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idNamespace',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='objectType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idType',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultArmApiVersion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json'}
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
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
                $Providers=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
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
                        $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
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
                        $Providers=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
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
        $Headers=@{Accept='application/json'}
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
            try
            {
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            catch {
                Write-Warning "[Get-ArmFeature] $item $_"
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
        $Headers=@{Accept="application/json";}
        #cleanup raw feature name
        if ($FeatureName -like "$Namespace/*") {
            $FeatureName=$FeatureName.Split('/')|Select-Object -Last 1
            Write-Verbose "[Register-ArmFeature] Using $FeatureName for registration in $Namespace"
        }
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
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -Method Post -ContentType 'application/json'
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
        Retrieves a list of authorized operations for the provider namespace
#>
Function Get-ArmProviderOperation
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Provider,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [System.String[]]
        $ProviderNamespace,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2015-07-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object') {
            $ProviderNamespace=$Provider|Select-Object -ExpandProperty Namespace
        }
        foreach ($item in $ProviderNamespace)
        {
            $ArmUriBld.Path="/providers/Microsoft.Authorization/providerOperations/$Namespace"
            $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
            Write-Output $Result
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
        $Headers=@{Accept="application/json";}
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
            try
            {
                $ArmTags=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmTags
            }
            catch
            {
                Write-Warning "[Get-ArmTagName] $item $_"
            }
        }
    }
    END
    {
    }
}

<#
    .SYNOPSIS
        Creates a resource group deployment
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
    .PARAMETER Template
        The resource group template
    .PARAMETER Parameters
        The resource group template parameters
    .PARAMETER TemplateLink
        The uri for resource group template
    .PARAMETER ParametersLink
        The uri for resource group template parameters        
#>
Function New-ArmDeployment
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [String[]]
        $ResourceGroupId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.String]
        $DeploymentName,        
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [System.Object]
        $Template,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.Uri]
        $TemplateLink, 
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [String]
        $TemplateVersion,                
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [System.Collections.IDictionary]
        $Parameters,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.Uri]        
        $ParametersLink,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [String]
        $ParametersVersion,        
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [String]
        $Mode='Incremental',
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]        
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='id')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='idLink')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='explicitLink')]
        [System.String]
        $ApiVersion="2016-09-01"
    )
    BEGIN
    {
        $Headers=@{Accept="application/json";}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        #Which parameter set?
        if($PSCmdlet.ParameterSetName -in 'explicit','explicitLink')
        {
            $ResourceGroupId=@("/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName")
        }
        if($PSCmdlet.ParameterSetName -in 'explicitLink','idLink')
        {
            $TemplateUri=[ordered]@{
                'uri'=$TemplateLink;
            }
            $ParameterUri=[ordered]@{
                'uri'=$ParametersLink;
            }
            if(-not [String]::IsNullOrEmpty($TemplateVersion))
            {
                $TemplateUri.Add('contentVersion',$TemplateVersion)
            }
            if(-not [String]::IsNullOrEmpty($ParametersVersion))
            {
                $ParameterUri.Add('contentVersion',$ParametersVersion)
            }
            #Build a linked deployment
            $DeploymentProperties=[ordered]@{
                'templateLink'=$(New-Object PSObject -Property $TemplateUri);
                'parametersLink'=$(New-Object psobject -Property $ParameterUri);
                'mode'=$Mode;
            }
        }
        else
        {
            #Build an inline deployment
            $DeploymentProperties=[ordered]@{
                'template'=$Template;
                'parameters'=$Parameters;
                'mode'=$Mode;
            }
        }
        foreach ($item in $ResourceGroupId)
        {
            $ArmUriBld.Path="$item/providers/Microsoft.Resources/deployments/$DeploymentName"
            $DeploymentRequest=[ordered]@{
                'properties'=$DeploymentProperties;
            }
            $Deployment=New-Object PSObject -Property $DeploymentRequest
            $RequestParams=@{
                Uri=$ArmUriBld.Uri;
                Method='PUT';
                AccessToken=$AccessToken;
                AdditionalHeaders=$Headers;
                ContentType='application/json'
                Body=$($Deployment|ConvertTo-Json -Depth 12);
                ErrorAction='STOP'
            }
            $Response=Invoke-ArmRequest @RequestParams
            Write-Output $Response
        }
    }
}

<#
    .SYNOPSIS
        Stops a resource group deployment
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
#>
Function Stop-ArmDeployment
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01"
    )
    PROCESS
    {
        $Headers=@{Accept="application/json";}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $UriQuery="api-version=$ApiVersion"
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$DeploymentName/cancel"
        $ArmUriBld.Query=$UriQuery
        $RequestParams=@{
            Uri=$ArmUriBld.Uri;
            AdditionalHeaders=$Headers;
            AccessToken=$AccessToken;
            ContentType='application/json';
            Method='POST'
            ErrorAction='STOP'
        }
        Invoke-ArmRequest @RequestParams|Out-Null
    }
}

<#
    .SYNOPSIS
        Removes a resource group deployment
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
#>
Function Remove-ArmDeployment
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01"
    )
    PROCESS
    {
        $Headers=@{Accept="application/json";}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $UriQuery="api-version=$ApiVersion"
        $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$DeploymentName"
        $ArmUriBld.Query=$UriQuery
        $RequestParams=@{
            Uri=$ArmUriBld.Uri;
            AdditionalHeaders=$Headers;
            AccessToken=$AccessToken;
            ContentType='application/json';
            Method='DELETE'
            ErrorAction='STOP'
        }
        Invoke-ArmRequest @RequestParams|Out-Null
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
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01",
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [String]
        $Filter,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Int32]
        $Top
    )
    $Headers=@{Accept="application/json";}
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
    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken `
        -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'
    Write-Output $ArmResult
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
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $DeploymentName,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [String]
        $OperationId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-09-01",
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Int32]
        $Top
    )
    $Headers=@{Accept="application/json";}
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
    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken `
        -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'
    Write-Output $ArmResult
}

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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-05-09-preview"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{"Accept"="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Advisor/recommendations"
                $Recommendations=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Recommendations
            }
            catch {
                Write-Warning "[Get-ArmAdvisorRecommendation] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2015-06-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/classicAdministrators"
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken -ContentType $ContentType
                if ($Result -ne $null) {
                    Write-Output $Result
                }
            }
            catch {
                Write-Warning "[Get-ArmClassicAdministrator] $item $_"
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
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Get-ArmDiagnosticSetting
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2015-07-01"
    )
    BEGIN
    {
        $Headers=@{Accept='application/json'}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            Write-Verbose "[Get-ArmDiagnosticSetting] Retrieving Diagnostic Settings for $item"
            $ArmUriBld.Path="$item/providers/microsoft.insights/diagnosticSettings/service"
            try
            {
                $RequestResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $RequestResult
            }
            catch {
                Write-Warning "[Get-ArmDiagnosticSetting] $item $_"
            }
        }
    }
    END
    {
    }
}

<#
    .SYNOPSIS
        Retrieves the list of event log categories
#>
Function Get-ArmEventCategory
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion='2015-04-01'
    )
    $Headers=@{Accept='application/json'}
    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Path="providers/microsoft.insights/eventcategories"
    $ArmUriBld.Query="api-version=$ApiVersion"
    $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
    Write-Output $ArmResult
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $DigestEvents,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [String]
        $Filter,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultEventLogApiVersion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json'}
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
            try
            {
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json' -LimitResultPages $ResultPages
                Write-Output $ArmResult
            }
            catch
            {
                Write-Warning "[Get-ArmEventLog] $Id $_"
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [String]
        $Filter,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion='2016-09-01',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ClassicApiVersion='2014-04-01'
    )
    BEGIN
    {
        $Headers=@{Accept='application/json'}
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
                $ContentAction=
                {
                    param([string]$input)
                    $input.Replace("ResourceUri","resourceUri").Replace("ResourceId","resourceId")
                }
                $RequestResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers `
                    -ContentAction $ContentAction -ContentType 'application/json'
                Write-Output $RequestResult
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
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultMonitorApiVersion,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ClassicApiVersion=$Script:ClassicMonitorApiVersion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json'}
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
            $ContentAction=
            {
                param([string]$input)
                $input.Replace("ResourceUri","resourceUri").Replace("ResourceId","resourceId")
            }
            Write-Verbose "[Get-ArmResourceMetricDefinition] Retrieving Metric Definitions for $item"
            $RequestResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers `
               -ContentAction $ContentAction -ContentType 'application/json'
            Write-Output $RequestResult
        }
    }
    END
    {
    }
}

#endregion

#region Commerce

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
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $OfferPrefix="MS-AZR-",
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $OfferCode='0003P',
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
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
        $Headers=@{'Accept'='application/json';}
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
        $DesiredRegion=New-Object System.Globalization.RegionInfo($RegionInfo)

        $ArmUriBld.Query="api-version=$ApiVersion&`$filter=OfferDurableId eq '$OfferDurableId' " +
            "and Currency eq '$($DesiredRegion.ISOCurrencySymbol)' " +
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
            try
            {
                Write-Verbose "[Get-ArmRateCard] Subscription:$item OfferDurableId:$OfferDurableId Locale:$Locale Currency:$($DesiredRegion.ISOCurrencySymbol)"
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/RateCard"
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Result
            }
            catch
            {
                Write-Warning "[Get-ArmRateCard] $item $_"
            }
        }
    }
    END
    {
    }
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
    [CmdletBinding(DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.DateTime]
        $StartTime,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.DateTime]
        $EndTime=[System.DateTime]::UtcNow,
        [Parameter(Mandatory=$true,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [System.DateTimeOffset]
        $StartTimeOffset,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [System.DateTimeOffset]
        $EndTimeOffset,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Int32]
        $LimitResultPages,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('Daily','Hourly')]
        [System.String]
        $Granularity='Daily',
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $ShowDetails,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='objectOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicitOffset',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultBillingApiVerion
    )
    BEGIN
    {
        $Headers=@{Accept='application/json';}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        if ($PSCmdlet.ParameterSetName -in 'object','explicit')
        {
            if ($Granularity -eq "Hourly")
            {
                $StartTime=New-Object System.DateTime($StartTime.Year,$StartTime.Month,$StartTime.Day,$StartTime.Hour)
                $EndTime=New-Object System.DateTime($EndTime.Year,$EndTime.Month,$EndTime.Day,$EndTime.Hour)
            }
            else
            {
                $StartTime=New-Object System.DateTime($StartTime.Year,$StartTime.Month,$StartTime.Day)
                $EndTime=New-Object System.DateTime($EndTime.Year,$EndTime.Month,$EndTime.Day)
            }
            $StartTimeString=$StartTime.ToString('o')
            $EndTimeString=$EndTime.ToString('o')
        }
        else
        {
            $StartTimeString=$StartTimeOffset.ToString('o')
            $EndTimeString=$EndTimeOffset.ToString('o')
        }
        $ArmUriBld.Query="api-version=$ApiVersion" +
            "&reportedStartTime=$($StartTimeString)&reportedEndTime=$($EndTimeString)" +
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
            try
            {
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Commerce/UsageAggregates"
                $AggregateResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -LimitResultPages $LimitResultPages
                Write-Output $AggregateResult
            }
            catch
            {
                Write-Warning "[Get-ArmUsageAggregate] $item $_"
            }
        }
    }
    END
    {
    }
}

<#
    .SYNOPSIS
        Retrieves billing invoices for the subscription
#>
Function Get-ArmBillingInvoice
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='object')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $InvoiceName,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Filter,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $Expand,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Int32]
        $Top,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $ExpandDownloadUrl,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-02-27-preview"
    )
    BEGIN
    {
        $Headers=@{Accept="application/json";}
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken `
                    -ContentType 'application/json' -ValueProperty 'value' -NextLinkProperty 'nextLink'
                Write-Output $ArmResult
            }
            catch
            {
                Write-Warning "[Get-ArmBillingInvoice] Error retrieving invoice(s) $SubId $_"
            }
        }
    }
    END
    {
    }
}
#endregion

#region RBAC and policy

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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AssignmentName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-12-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                if ([string]::IsNullOrEmpty($AssignmentName) -eq $false)
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policyassignments/$AssignmentName"
                }
                else
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policyassignments"
                }
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Result
            }
            catch
            {
                Write-Warning "[Get-ArmPolicyAssignment] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $DefinitionName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-12-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policydefinitions"
                if ([string]::IsNullOrEmpty($DefinitionName) -eq $false)
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/policydefinitions/$DefinitionName"
                }
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Result
            }
            catch
            {
                 Write-Warning "[Get-ArmPolicyDefinition] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $RoleName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-07-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleAssignments"
                if ([String]::IsNullOrEmpty($RoleName) -eq $false)
                {
                    $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Authorization/roleAssignments/$RoleName"
                }
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Result
            }
            catch
            {
                Write-Warning "[Get-ArmRoleAssignment] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceType,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='explicit',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion='2015-01-01'
    )
    BEGIN
    {
        $Headers=@{Accept='application/json';}
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
            try
            {
                $ArmUriBld.Path+="/providers/microsoft.authorization/locks"
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -ContentType 'application/json' -AccessToken $AccessToken
                if($ArmResult -ne $null)
                {
                    Write-Output $ArmResult
                }
            }
            catch {
                Write-Warning "[Get-ArmResourceLock] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $DefinitionName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-07-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
            try
            {
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken
                Write-Output $Result
            }
            catch
            {
                Write-Warning "[Get-ArmRoleDefinition] $item $_"
            }
        }
    }
    END
    {
    }
}

#endregion

#region VM and Website

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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ImageName,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
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
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/images"
            if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/images"
            }
            if ([String]::IsNullOrEmpty($ImageName) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/images/$ImageName"
            }
            try {
                $ArmDisks=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken -ContentType 'application/json'
                Write-Output $ArmDisks
            }
            catch {
                Write-Warning "[Get-ArmVmDiskImage] $item $_"
            }
        }
    }
    END
    {
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $DiskName,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
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
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/disks"
            if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/disks"
            }
            if ([String]::IsNullOrEmpty($DiskName) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/disks/$DiskName"
            }
            try
            {
                $ArmDisks=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmDisks
            }
            catch {
                Write-Warning "[Get-ArmVmManagedDisk] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Compute/locations/$Location/vmSizes"
                $VmSizes=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $VmSizes
            }
            catch {
                Write-Warning "[Get-ArmVmSize] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroup,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SnapshotName,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
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
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            $ArmUriBld.Path="/subscriptions/$item/providers/Microsoft.Compute/snapshots"
            if ([string]::IsNullOrEmpty($ResourceGroup) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/snapshots"
            }
            elseif ([String]::IsNullOrEmpty($SnapshotName) -eq $false) {
                $ArmUriBld.Path="/subscriptions/$item/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/snapshots/$SnapshotName"
            }
            try
            {
                $ArmDisks=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmDisks
            }
            catch {
                Write-Warning "[Get-ArmVmSnapshot] $item $_"
            }
        }
    }
    END
    {
    }
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
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idWithName',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='idWithName',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='idWithName',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='idWithName',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='objectWithName',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idWithName',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectWithName',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='idWithName',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='objectWithName',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultWebsiteApiVersion
    )
    BEGIN
    {
        $Headers=@{'Accept'='application/json';}
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
            if ($PSCmdlet.ParameterSetName -in 'objectWithName','idWithName')
            {
                $UriBuilder.Path="/subscriptions/$Id/resourcegroups/$ResourceGroupName/providers/Microsoft.Web/sites/$WebsiteName"
            }
            else
            {
                $UriBuilder.Path="/subscriptions/$Id/providers/Microsoft.Web/sites"
            }
            try
            {
                $ArmResult=Invoke-ArmRequest -Uri $UriBuilder.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                if ($ArmResult -ne $null) {
                    Write-Output $ArmResult
                }
            }
            catch {
                Write-Warning "[Get-ArmWebSite] $id $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Object]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='bySiteObject',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.Object[]]
        $Website,
        [Parameter(Mandatory=$true,ParameterSetName='bySiteObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='bySiteObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='bySiteObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion=$Script:DefaultWebsiteApiVersion
    )
    BEGIN
    {
        $Headers=@{'Accept'='application/json';}
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
            try {
                $CredResult=Invoke-ArmRequest -Uri $UriBuilder.Uri -Method Post -AccessToken $AccessToken -ContentType 'application/json' -AdditionalHeaders $Headers
                if($CredResult -ne $null)
                {
                    Write-Output $CredResult
                }
            }
            catch {
                Write-Warning "[Get-ArmWebSitePublishingCredential] $item $_"
            }
        }
    }
    END
    {
    }
}

#endregion

#region Quota

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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-12-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Storage/usages"
                $Usages=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Usages
            }
            catch {
                Write-Warning "[Get-ArmStorageUsage] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmUriBld.Path="subscriptions/$item/providers/Microsoft.Compute/locations/$Location/usages"
                $Usages=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Usages
            }
            catch {
                Write-Warning "[Get-ArmComputeUsage] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [ValidatePattern('^[A-Za-z]+.[A-Za-z]+$')]
        [String]
        $Namespace,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-12-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        if ($PSCmdlet.ParameterSetName -eq 'object')
        {
            $SubscriptionId=$Subscription|Select-Object -ExpandProperty subscriptionId
        }
        foreach ($item in $SubscriptionId)
        {
            try {
                $ArmUriBld.Path="subscriptions/$item/providers/$Namespace/locations/$Location/usages"
                $Result=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $Result
            }
            catch {
                Write-Warning "[Get-ArmQuotaUsage] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='default',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='filter',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='datetime',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='offset',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $ResourceId,
        [Parameter(Mandatory=$true,ParameterSetName='filter',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Filter,
        [Parameter(Mandatory=$true,ParameterSetName='filter',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='datetime',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='offset',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$true,ParameterSetName='datetime',ValueFromPipelineByPropertyName=$true)]
        [System.DateTime]
        $UsageStart,
        [Parameter(Mandatory=$true,ParameterSetName='datetime',ValueFromPipelineByPropertyName=$true)]
        [System.DateTime]
        $UsageEnd,
        [Parameter(Mandatory=$true,ParameterSetName='offset',ValueFromPipelineByPropertyName=$true)]
        [System.DateTimeOffset]
        $UsageStartOffset,
        [Parameter(Mandatory=$true,ParameterSetName='offset',ValueFromPipelineByPropertyName=$true)]
        [System.DateTimeOffset]
        $UsageEndOffset,
        [Parameter(Mandatory=$false,ParameterSetName='default',ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $GetDefault,
        [Parameter(Mandatory=$false,ParameterSetName='default',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='filter',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='datetime',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='offset',ValueFromPipelineByPropertyName=$true)]
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
        $Headers=@{Accept="application/json";}
    }
    PROCESS
    {
        foreach ($item in $ResourceId)
        {
            $ResourceData=$item|ConvertFrom-ArmResourceId
            $ArmUriBld.Path="$item/usages"
            #Resolve the api version
            $ResourceType="$($ResourceData.Namespace)/$($ResourceData.ResourceType)"
            if ($Script:SubscriptionProviderApiVersionCache.ContainsKey($ResourceData.SubscriptionId))
            {
                $SubscriptionCache=$Script:SubscriptionProviderApiVersionCache[$ResourceData.SubscriptionId]
                #Is the type there?
                if ($SubscriptionCache.ContainsKey($ResourceType))
                {
                    $ApiVersions=$SubscriptionCache[$ResourceType]
                }
                else
                {
                    $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $ResourceData.SubscriptionId -ResourceType $ResourceType `
                        -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint
                    $SubscriptionCache.Add($ResourceType,$ApiVersions)
                    $Script:SubscriptionProviderApiVersionCache[$ResourceData.SubscriptionId]=$SubscriptionCache
                }
            }
            else
            {
                $ApiVersions=Get-ArmResourceTypeApiVersion -SubscriptionId $SubscriptionId -ResourceType $ResourceType `
                    -AccessToken $AccessToken -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion
                $Script:SubscriptionProviderApiVersionCache.Add($SubscriptionId,@{$ResourceType=$ApiVersions})
            }
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
                $Usages=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AdditionalHeaders $Headers -AccessToken $AccessToken -ContentType 'application/json'
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

#endregion

#region Platform Image Repository

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
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ImagePublishers=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ImagePublishers
            }
            catch {
                Write-Warning  "[Get-ArmPlatformImagePublisher] $item $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Publisher,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [string[]]
        $PublisherId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            catch {
                Write-Warning "[Get-ArmPlatformImagePublisherOffer] $ImagePublisher $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Offer,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [string[]]
        $OfferId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $OfferName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            catch {
                Write-Warning "[Get-ArmPlatformImageSku] $ImageOffer $_"
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
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $ImageSku,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [string[]]
        $ImageSkuId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [psobject[]]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $Location,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $PublisherName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $OfferName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $SkuName,
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$true,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherId',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='byPublisherObject',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='object',ValueFromPipelineByPropertyName=$true)]
        [Parameter(Mandatory=$false,ParameterSetName='id',ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2017-03-30"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
        $Headers=@{Accept="application/json";}
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
                $ArmResult=Invoke-ArmRequest -Uri $ArmUriBld.Uri -AccessToken $AccessToken -AdditionalHeaders $Headers -ContentType 'application/json'
                Write-Output $ArmResult
            }
            catch {
                Write-Warning "[Get-ArmPlatformImageVersion] $Sku $_"
            }
        }
    }
    END
    {
    }
}

#endregion

#region KeyVault

<#
    .SYNOPSIS
        Creates a new key vault
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER ResourceGroupName
        The resource group name
    .PARAMETER VaultName
        The vault name
    .PARAMETER TenantId
        The associated Tenant Id for authentication
    .PARAMETER Location
        The placement region
    .PARAMETER ObjectId
        The associated directory object
    .PARAMETER Sku
        The Sku Name
    .PARAMETER SkuFamily
        The Sku Family
    .PARAMETER CreateMode
        The vault creation mode 
    .PARAMETER Tags
        Metadata Tags to be added
    .PARAMETER EnableForDeployment
        Whether to enable for virtual machine use
    .PARAMETER EnableForDiskEncryption
        Whether to enable for disk encryption
    .PARAMETER EnableForTemplateDeployment
        Whether to enable for ARM templates
    .PARAMETER EnableSoftDelete
        Whether to enable soft delete functionality
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function New-ArmKeyVault
{
    [CmdletBinding(ConfirmImpact='None')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $VaultName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $TenantId,       
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Location,        
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ObjectId, 
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $Sku='Standard',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $SkuFamily='A',        
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $CreateMode='default',
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $AllowedKeyPermissions=@('all'),
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String[]]
        $AllowedSecretPermissions=@('all'),
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Collections.IDictionary]
        $Tags,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $EnableForDeployment,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $EnableForDiskEncryption,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $EnableForTemplateDeployment,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $EnableSoftDelete,          
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [System.String]
        $ApiVersion="2016-10-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"        
        $RequestParams=@{
            ContentType='application/json';
            AdditionalHeaders=@{Accept="application/json";};
            AccessToken=$AccessToken;
            Method='PUT'
        }        
    }
    PROCESS
    {
        $ArmUriPath="/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$VaultName"
        $ArmUriBld.Path=$ArmUriPath
        $RequestParams['Uri']=$ArmUriBld.Uri
        $VaultSku=New-Object PSObject -Property @{
                name=$Sku;
                family=$SkuFamily;
        };
        $VaultAccessPolicy=@()
        if([string]::IsNullOrEmpty($ObjectId) -eq $false)
        {
            $VaultAccessPolicy=@(New-Object PSObject @{
                "tenantId"=$TenantId;
                "objectId"=$ObjectId;
                "permissions"=@{
                    "keys"=@($AllowedKeyPermissions);
                    "secrets"=@($AllowedSecretPermissions);
                }
            })
        }
        $VaultProperties=[ordered]@{
            tenantId=$TenantId;
            sku=$VaultSku;
            accessPolicies=@($VaultAccessPolicy);
            enabledForDeployment=$($EnableForDeployment.IsPresent);
            enabledForDiskEncryption=$($EnableForDiskEncryption.IsPresent)
            enabledForTemplateDeployment=$($EnableForDeployment.IsPresent);
            resourceGroupName=$ResourceGroupName;
            subscriptionId=$SubscriptionId;
            vaultName=$VaultName;
        }
        if($EnableSoftDelete.IsPresent)
        {
            $VaultProperties.Add('enableSoftDelete',$true)
        }
        $VaultProperties.Add('createMode',$CreateMode)
        $NewVault=[ordered]@{        
            location=$Location;
            tags=$Tags;
            properties=$VaultProperties;
        }
        $RequestParams['Body']=$($NewVault|ConvertTo-Json -Depth 10)
        $ArmResult=Invoke-ArmRequest @RequestParams
        Write-Output $ArmResult
    }
}

<#
    .SYNOPSIS
        Deletes a key vault
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER ResourceGroupName
        The resource group name
    .PARAMETER VaultName
        The vault name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
#>
Function Remove-ArmKeyVault
{
    [CmdletBinding(DefaultParameterSetName='ByName')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $VaultName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByName')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByName')]
        [System.String]
        $ApiVersion="2016-10-01"
    )
    BEGIN
    {
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
        $ArmUriBld.Query="api-version=$ApiVersion"
    }
    PROCESS
    {
        $ArmUriBld.Path="/subscriptions/${SubscriptionId}/resourceGroups/${ResourceGroupName}/providers/Microsoft.KeyVault/vaults/${VaultName}"
        $RequestParams=@{
            Method='DELETE';
            AdditionalHeaders=@{'Accept'='application/json'};
            ContentType='application/json';
            AccessToken=$AccessToken;
            Uri=$ArmUriBld.Uri
        }
        $DeleteResult=Invoke-ArmRequest @RequestParams
        Write-Output $DeleteResult
    }
}

<#
    .SYNOPSIS
        Retreives Key Vault(s)
    .PARAMETER SubscriptionId
        The subscription id
    .PARAMETER ResourceGroupName
        The resource group name
    .PARAMETER VaultName
        The vault name
    .PARAMETER AccessToken
        The OAuth access token
    .PARAMETER ApiEndpoint
        The ARM api endpoint
    .PARAMETER ApiVersion
        The ARM api version
    .PARAMETER Filter
        The OData filter
    .PARAMETER Top
        Limit the result set returned
#>
Function Get-ArmKeyVault
{
    [CmdletBinding(ConfirmImpact='None',DefaultParameterSetName='ByFilter')]
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByFilter')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [System.String]
        $VaultName,
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByFilter')]
        [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByName')]
        [String]
        $AccessToken,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByFilter')]
        [String]
        $Filter="resourceType eq 'Microsoft.KeyVault/vaults'",
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,ParameterSetName='ByFilter')]
        [int]
        $Top,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByFilter')]          
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByName')]
        [System.Uri]
        $ApiEndpoint=$Script:DefaultArmFrontDoor,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByFilter')]
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$false,ParameterSetName='ByName')]
        [System.String]
        $ApiVersion="2017-06-01"
    )

    BEGIN
    {
        $ArmQuery="api-version=$ApiVersion"
        $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)       
        $RequestParams=@{
            ContentType='application/json';
            AdditionalHeaders=@{Accept="application/json";};
            AccessToken=$AccessToken;
            Method='GET'
        }        
    }
    PROCESS
    {
        if($PSCmdlet.ParameterSetName -eq 'ByName')
        {
            $ArmQuery="api-version=$($Script:DefaultKeyVaultApiVersion)"
            $ArmUriBld.Path="/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$VaultName"
        }
        else
        {
            $ArmUriBld.Path="/subscriptions/$SubscriptionId/resources"
            $ArmQuery+="&`$filter=$($Filter)"
            if($Top -gt 0)
            {
                $ArmQuery+="&Top=$($Top)"
            }
        }
        $ArmUriBld.Query=$ArmQuery
        $RequestParams['Uri']=$ArmUriBld.Uri
        $ArmResult=Invoke-ArmRequest @RequestParams
        Write-Output $ArmResult
    }

}

#endregion