Function Get-ArmWebSite
{
    [CmdletBinding(DefaultParameterSetName='all')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [Parameter(Mandatory=$true,ParameterSetName='all')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [Parameter(Mandatory=$true,ParameterSetName='all')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='named')]
        [Parameter(Mandatory=$false,ParameterSetName='all')]
        [System.Uri]
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='named')]
        [Parameter(Mandatory=$false,ParameterSetName='all')]
        [System.String]
        $ApiVersion='2016-08-01'
    )

    $Headers=@{
        'Authorization'="Bearer $AccessToken";
        'Accept'='application/json';
    }
    $UriBuilder=New-Object System.UriBuilder($ApiEndpoint)
    $UriBuilder.Path="/subscriptions/$SubscriptionId/providers/Microsoft.Web/sites"
    if($PSCmdlet.ParameterSetName -eq 'named')
    {
        $UriBuilder.Path="/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Web/sites/$WebsiteName"
    }
    $UriBuilder.Query="api-version=$ApiVersion"
    $Result=Invoke-RestMethod -Uri $UriBuilder.Uri -Method Get -ContentType 'application/json' -Headers $Headers
    if($PSCmdlet.ParameterSetName -eq 'named')
    {
        Write-Output -InputObject $Result
    }
    else
    {
        foreach ($webresult in $Result.value)
        {
            Write-Output $webresult
        }
        $AllDone=[String]::IsNullOrEmpty($Result.nextLink)
        if($AllDone -eq $false)
        {
            do
            {
                $AllDone=[String]::IsNullOrEmpty($Result.nextLink)
                $Result=Invoke-RestMethod -Uri $Result.nextLink -Method Get -ContentType 'application/json' -Headers $Headers
                foreach ($webresult in $Result.value)
                {
                    Write-Output $webresult
                }
            }
            while ($AllDone -eq $false)
        }

    }
}

Function Get-ArmWebSitePublishingCredentials
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $ResourceGroupName,        
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Website,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2016-08-01'
    )

    BEGIN
    {
        $Headers=@{
            'Authorization'="Bearer $AccessToken";
            'Accept'='application/json';
        }
        if($PSCmdlet.ParameterSetName -eq 'explicit')
        {
            $Website+=Get-ArmWebSite -SubscriptionId $SubscriptionId -ApiEndpoint $ApiEndpoint -ApiVersion $ApiVersion -AccessToken $AccessToken|? name -In $WebsiteName
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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
    )

    $ArmUriBld=New-Object System.UriBuilder($ApiEndpoint)
    $ArmUriBld.Query="api-version=$ApiVersion"
    $ArmUriBld.Path='subscriptions'
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        $ArmUriBld.Path+="/$SubscriptionId"
    }
    $AuthHeaders=@{'Authorization'="Bearer $AccessToken"}
    $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
    Write-Output $ArmResult
}

Function Get-ArmProvider
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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
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
            $ArmUriBld.Path="subscriptions/$item"
            if([String]::IsNullOrEmpty($Namespace) -eq $false)
            {
                $ArmUriBld.Path="subscriptions/$item/$Namespace"
            }
            $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
            #TODO: Could this page?
            Write-Output $ArmResult.value
        }
    }
    END
    {

    }

}

Function Get-ArmResourceType
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
        $ResourceType,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.Uri]
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
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
            $ArmUriBld.Path="subscriptions/$item/providers"
            if([String]::IsNullOrEmpty($ResourceType) -eq $false) {
                $Namespace=$ResourceType.Split('/')|Select-Object -First 1
                $TypeName=$ResourceType.Replace("$Namespace/",[String]::Empty)
                $ArmUriBld.Path="subscriptions/$item/$Namespace"
                $ArmResult=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders
                $ResProvType=$ArmResult.resourceTypes|Where-Object{$_.Name -eq $TypeName }|Select-Object -First 1
                if ($ResProvType -ne $null) {
                    Write-Output $ResProvType
                }
                else {
                    Write-Warning "$ResourceType was not found in subscription:$item"
                }
            }
            else {
                $Providers=Invoke-RestMethod -Uri $ArmUriBld.Uri -ContentType 'application/json' -Headers $AuthHeaders|Select-Object -ExpandProperty 'value'
                foreach ($Provider in $Providers)
                {
                    Write-Output $Provider.resourceTypes
                }
            }
        }
    }
    END
    {

    }

}

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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
    )    
}

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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
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
                Write-Output $ArmResult
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