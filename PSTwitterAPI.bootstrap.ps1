using namespace Microsoft.PowerShell.Commands
[CmdletBinding()]
param(
    #
    [ValidateSet("CurrentUser", "AllUsers")]
    $Scope = "CurrentUser"
)

[ModuleSpecification[]]$RequiredModules = @(
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.4.2" }
    @{ ModuleName = "Pester"; RequiredVersion = "4.4.4" }
    @{ ModuleName = "BuildHelpers"; RequiredVersion = "2.0.3" }
    @{ ModuleName = "PSScriptAnalyzer"; RequiredVersion = "1.17.1" }
)

$Policy = (Get-PSRepository PSGallery).InstallationPolicy
Set-PSRepository PSGallery -InstallationPolicy Trusted

try {
    $RequiredModules | Install-Module -Scope $Scope -Repository PSGallery -SkipPublisherCheck -Verbose
} finally {
    Set-PSRepository PSGallery -InstallationPolicy $Policy
}

$RequiredModules | Import-Module