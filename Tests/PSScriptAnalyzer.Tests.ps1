Try   { Set-BuildEnvironment -Path "${PSScriptRoot}\.." -ErrorAction Stop -Force } 
Catch { Set-BuildEnvironment -Path ".\.." -ErrorAction Stop -Force -Force }

Remove-Module ${env:BHProjectName} -ErrorAction SilentlyContinue -Force -Confirm:$False
$Script:Module = Import-Module ${env:BHPSModuleManifest} -Force -PassThru

Describe "General project validation" {

    Context 'Basic Module Testing' {
        # Original idea from: https://kevinmarquette.github.io/2017-01-21-powershell-module-continious-delivery-pipeline/
        [array]$scripts = Get-ChildItem ${env:BHModulePath} -Include *.ps1, *.psm1, *.psd1 -Recurse
        [array]$testCase = $scripts | Foreach-Object {
            @{
                FilePath = $_.fullname
                FileName = $_.Name

            }
        }
        It "Script <FileName> should be valid powershell" -TestCases $testCase {
            param(
                $FilePath,
                $FileName
            )

            $FilePath | Should Exist

            $contents = Get-Content -Path $FilePath -ErrorAction Stop
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)
            $errors.Count | Should Be 0
        }

        It "Module '${env:BHProjectName}' can import cleanly" {
            { $Script:Module = Import-Module ${env:BHPSModuleManifest} -Force -PassThru } | Should Not Throw
        }
    }

    Context 'Manifest Testing' {
        It 'Valid Module Manifest' {
            {
                $Script:Manifest = Test-ModuleManifest -Path ${env:BHPSModuleManifest} -ErrorAction Stop -WarningAction SilentlyContinue
            } | Should Not Throw
        }
        It 'Valid Manifest Name' {
            $Script:Manifest.Name | Should be ${env:BHProjectName}
        }
        It 'Generic Version Check' {
            $Script:Manifest.Version -as [Version] | Should Not BeNullOrEmpty
        }
        It 'Valid Manifest Description' {
            $Script:Manifest.Description | Should Not BeNullOrEmpty
        }
        It 'Valid Manifest Root Module' {
            $Script:Manifest.RootModule | Should Be "${env:BHProjectName}.psm1"
        }
        It 'Valid Manifest GUID' {
            $Script:Manifest.Guid | Should be '9b7281cf-c80f-44bb-96c0-ed1137056164'
        }
        It 'No Format File' {
            $Script:Manifest.ExportedFormatFiles | Should BeNullOrEmpty
        }

        It 'Required Modules' {
            $Script:Manifest.RequiredModules | Should BeNullOrEmpty
        }
    }

    Context 'Exported Functions' {

        [array]$ManifestFunctions = $Script:Manifest.ExportedFunctions.Keys
        [array]$ExportedFunctions = $Script:Module.ExportedFunctions.Keys
        [array]$ExpectedFunctions = (Get-ChildItem -Path "${env:BHModulePath}\public" -Filter *.ps1 -Recurse | Select-Object -ExpandProperty Name ) -replace '\.ps1$'
        [array]$CommandFunctions = Get-Command -Module $Script:Module.Name -CommandType Function | Select-Object -ExpandProperty Name

        [array]$testCase = $ExpectedFunctions | Foreach-Object {@{FunctionName = $_}}
        It "Function <FunctionName> should be in manifest" -TestCases $testCase -Skip {
            param($FunctionName)
            $FunctionName -in $ManifestFunctions | Should Be $true
        }

        It "Function <FunctionName> should be exported" -TestCases $testCase {
            param($FunctionName)
            $FunctionName -in $ExportedFunctions | Should Be $true
            $FunctionName -in $CommandFunctions | Should Be $true
        }

        It 'Number of Functions Exported compared to Manifest' -Skip {
            $CommandFunctions.Count | Should be $ManifestFunctions.Count
        }

        It 'Number of Functions Exported compared to Files' {
            $CommandFunctions.Count | Should be $ExpectedFunctions.Count
        }

        $InternalFunctions = (Get-ChildItem -Path "${env:BHModulePath}\private" -Filter *.ps1 | Select-Object -ExpandProperty Name ) -replace '\.ps1$'
        $testCase = $InternalFunctions | Foreach-Object {@{FunctionName = $_}}
        It "Internal function <FunctionName> is not directly accessible outside the module" -TestCases $testCase {
            param($FunctionName)
            { . $FunctionName } | Should Throw
        }
    }

    Context 'Exported Aliases' {
        It 'Proper Number of Aliases Exported compared to Manifest' {
            $ExportedCount = Get-Command -Module ${env:BHProjectName} -CommandType Alias | Measure-Object | Select-Object -ExpandProperty Count
            $ManifestCount = $Manifest.ExportedAliases.Count

            $ExportedCount | Should be $ManifestCount
        }

        It 'Proper Number of Aliases Exported compared to Files' {
            $AliasCount = Get-ChildItem -Path "${env:BHModulePath}\public" -Filter *.ps1 | Select-String "New-Alias" | Measure-Object | Select-Object -ExpandProperty Count
            $ManifestCount = $Manifest.ExportedAliases.Count

            $AliasCount  | Should be $ManifestCount
        }
    }
}

Describe "ScriptAnalyzer" -Tag 'Compliance' {

    # Get a list of all internal and Exported functions
    $ItemFiles = @()
    $ItemFiles += Get-ChildItem -Path "${env:BHModulePath}\private" -Filter *.ps1 -Recurse
    $ItemFiles += Get-ChildItem -Path "${env:BHModulePath}\public" -Filter *.ps1 -Recurse
    
    $PSScriptAnalyzerSettings = @{
        Severity    = @('Error', 'Warning')
        ExcludeRule = @('PSUseSingularNouns', 'PSUseShouldProcessForStateChangingFunctions', 'PSAvoidUsingInvokeExpression' )
    }

    Context "Strict mode" {
 
        Set-StrictMode -Version Latest
        ForEach ($ItemFile in $ItemFiles) {

            $ScriptAnalyzerResults = Invoke-ScriptAnalyzer -Path $ItemFile.FullName @PSScriptAnalyzerSettings
            $TestResults = $ScriptAnalyzerResults | Foreach-Object {
                @{
                    RuleName   = $_.RuleName
                    ScriptName = $_.ScriptName
                    Message    = $_.Message
                    Severity   = $_.Severity
                    Line       = $_.Line
                }
            }
            If ($TestResults) {
                It "Function <ScriptName> should not use <Message> on line <Line>" -TestCases $TestResults {
                    param(
                        $RuleName,
                        $ScriptName,
                        $Message,
                        $Severity,
                        $Line
                    )
                    $ScriptName | Should BeNullOrEmpty
                }
            } Else {
                It "Function $($ItemFile.Name) should return no errors" {
                    $TestResults | Should BeNullOrEmpty
                }
            }

        }

    }
    
}
