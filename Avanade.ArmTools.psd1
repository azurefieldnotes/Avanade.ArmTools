#
# Module manifest for module 'Avanade.ArmTools'
#
# Generated by: Chris Speers
#
# Generated on: 11/12/2016
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'Module'

# Version number of this module.
ModuleVersion = '1.6'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '0bf2711a-c589-4e54-b186-739d7fcea4b2'

# Author of this module
Author = 'Chris Speers'

# Company or vendor of this module
CompanyName = 'Avanade, Inc.'

# Copyright statement for this module
Copyright = '© 2016 Avanade, Inc.'

# Description of the functionality provided by this module
Description = 'Simple REST Wrappers for Azure Resource Manager'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '3.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# DotNetFrameworkVersion = ''

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @(
                        'ConvertFrom-ArmResourceId','Get-ArmFeature','Get-ArmLocation','Get-ArmProvider',
                        'Get-ArmRateCard','Get-ArmResource','Get-ArmResourceGroup','Get-ArmResourceInstance',
                        'Get-ArmResourceLock','Get-ArmResourceType','Get-ArmResourceTypeApiVersion','Get-ArmResourceTypeLocation','Get-ArmSubscription',
                        'Get-ArmUsageAggregate','Get-ArmWebSite','Get-ArmWebSitePublishingCredential','Get-ArmTenant',
                        'Get-ArmResourceMetric','Get-ArmResourceMetricDefinition','Get-ArmDiagnosticSetting','Get-ArmEventLog',
                        'Get-ArmAdvisorRecommendation','Get-ArmResourceUsage','Get-ArmStorageUsage','Get-ArmComputeUsage','Get-ArmRoleAssignment',
                        'Remove-ArmItem','Get-ArmPolicyAssignment','Get-ArmPolicyDefinition','Register-ArmProvider','Unregister-ArmProvider',
                        'Register-ArmFeature','Get-ArmRoleDefinition','Get-ArmVmSize','Get-ArmTagName','Get-ArmQuotaUsage','Get-ArmDeploymentOperation',
                        'Get-ArmDeployment','Get-ArmClassicAdministrator','Get-ArmProviderOperation','Get-ArmEventCategory',
                        'Get-ArmVmManagedDisk','Get-ArmVmDiskImage','Get-ArmVmSnapshot','Get-ArmPlatformImagePublisher','Get-ArmPlatformImagePublisherOffer',
                        'Get-ArmPlatformImageSku','Get-ArmPlatformImageVersion','Get-ArmBillingInvoice'
                    )

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
#CmdletsToExport = @()

# Variables to export from this module
#VariablesToExport = '*'

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
#AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = @('ARM','Azure','REST')

        # A URL to the license for this module.
        LicenseUri = 'https://raw.githubusercontent.com/azurefieldnotes/Avanade.ArmTools/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/azurefieldnotes/Avanade.ArmTools'

        # A URL to an icon representing this module.
        IconUri = 'https://azurefieldnotesblog.blob.core.windows.net/wp-content/2016/11/ARMRest.png'

        # ReleaseNotes of this module
        # ReleaseNotes = ''

        # External dependent modules of this module
        ExternalModuleDependencies = 'Microsoft.PowerShell.Utility'


    } # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}

