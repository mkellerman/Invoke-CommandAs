Try { Set-BuildEnvironment -Path "${PSScriptRoot}\.." -ErrorAction SilentlyContinue -Force } Catch { }

Remove-Module $ENV:BHProjectName -ErrorAction SilentlyContinue -Force -Confirm:$False
$Script:Module = Import-Module $ENV:BHPSModuleManifest -Force -PassThru

Describe 'Get-Module -Name Invoke-CommandAs' {
    Context 'Strict mode' {

        Set-StrictMode -Version Latest

        It 'Should Import' {
            $Script:Module.Name | Should be $ENV:BHProjectName
        }
        It 'Should have ExportedFunctions' {
            $Script:Module.ExportedFunctions.Keys -contains 'Invoke-CommandAs' | Should be $True
        }
    }
}
