<#
    Avanade.ArmTools
#>

Function Get-ArmWebSite
{
    [CmdletBinding(DefaultParameterSetName='all')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [Parameter(Mandatory=$true,ParameterSetName='all')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='namedObject')]
        [Parameter(Mandatory=$true,ParameterSetName='allObject')]
        [System.Object]
        $Subscription,
        [Parameter(Mandatory=$true,ParameterSetName='namedObject')]    
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='namedObject')]
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [System.String]
        $ResourceGroupName,
        [Parameter(Mandatory=$true,ParameterSetName='namedObject')]
        [Parameter(Mandatory=$true,ParameterSetName='named')]
        [Parameter(Mandatory=$true,ParameterSetName='all')]
        [Parameter(Mandatory=$true,ParameterSetName='allObject')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='namedObject')]
        [Parameter(Mandatory=$false,ParameterSetName='named')]
        [Parameter(Mandatory=$false,ParameterSetName='all')]
        [Parameter(Mandatory=$false,ParameterSetName='allObject')]
        [System.Uri]
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='namedObject')]
        [Parameter(Mandatory=$false,ParameterSetName='named')]
        [Parameter(Mandatory=$false,ParameterSetName='all')]
        [Parameter(Mandatory=$false,ParameterSetName='allObject')]
        [System.String]
        $ApiVersion='2016-08-01'
    )

    if($PSCmdlet.ParameterSetName -in "namedObject","allObject") {
        $SubscriptionId=$Subscription.subscriptionId
    }

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

Function Get-ArmWebSitePublishingCredential
{
    [CmdletBinding(DefaultParameterSetName='explicit')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [System.String]
        $SubscriptionId,
        [Parameter(Mandatory=$true,ParameterSetName='explicitObject')]
        [System.Object]
        $Subscription,                
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitObject')]
        [System.String]
        $ResourceGroupName,        
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitObject')]
        [System.String]
        $WebsiteName,
        [Parameter(Mandatory=$true,ParameterSetName='object',ValueFromPipeline=$true)]
        [System.Object[]]
        $Website,
        [Parameter(Mandatory=$true,ParameterSetName='object')]
        [Parameter(Mandatory=$true,ParameterSetName='explicit')]
        [Parameter(Mandatory=$true,ParameterSetName='explicitObject')]
        [System.String]
        $AccessToken,
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitObject')]
        [System.Uri]
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [Parameter(Mandatory=$false,ParameterSetName='explicitObject')]
        [System.String]
        $ApiVersion='2016-08-01'
    )

    BEGIN
    {
        $Headers=@{
            'Authorization'="Bearer $AccessToken";
            'Accept'='application/json';
        }

        if($PSCmdlet.ParameterSetName -in 'explicit','explicitObject')
        {
            if ($PSCmdlet.ParameterSetName -eq "explicitObject") {
                $Subscription.subscriptionId
            }
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
    if ([string]::IsNullOrEmpty($SubscriptionId) -eq $false) {
        Write-Output $ArmResult
    }
    else {
        Write-Output $ArmResult.value
    }
}

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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='objectType')]
        [Parameter(Mandatory=$false,ParameterSetName='objectNamespace')]
        [Parameter(Mandatory=$false,ParameterSetName='idType')]
        [Parameter(Mandatory=$false,ParameterSetName='idNamespace')]
        [System.String]
        $ApiVersion='2015-11-01'
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
                $ArmUriBld.Path="subscriptions/$item/providers"
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
        $ApiEndpoint='https://management.azure.com',
        [Parameter(Mandatory=$false,ParameterSetName='object')]
        [Parameter(Mandatory=$false,ParameterSetName='explicit')]
        [System.String]
        $ApiVersion='2015-11-01'
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