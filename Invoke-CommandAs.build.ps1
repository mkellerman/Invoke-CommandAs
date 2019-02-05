<#
.Synopsis
	Build script (https://github.com/nightroman/Invoke-Build)
#>

param ($Configuration = 'Development')

#region Set-BuildEnvironment
Try { Set-BuildEnvironment -ErrorAction SilentlyContinue -Force } Catch { }
#endregion

#region use the most strict mode
Set-StrictMode -Version Latest
#endregion

#region Task to run all Pester tests in folder .\tests
task Test {

    $OutputPath = New-Item -Path '.\TestResults' -ItemType Directory -Force -Verbose

    $PesterParams = @{
        Script = '.\Tests'
        OutputFile = "${OutputPath}\TestResults.xml"
        CodeCoverage = 'Invoke-CommandAs\*\*.ps1'
        CodeCoverageOutputFile = "${OutputPath}\CodeCoverage.xml"
        CodeCoverageOutputFileFormat = 'JaCoCo'
    }

    $Result = Invoke-Pester @PesterParams -PassThru

    if ($Result.FailedCount -gt 0) {
        throw 'Pester tests failed'
    }

}
#endregion

#region Task to update the Module Manifest file with info from the Changelog in Readme.
task UpdateManifest {
    # Import PlatyPS. Needed for parsing README for Change Log versions
    #Import-Module -Name PlatyPS

    $ModuleManifest = Test-ModuleManifest -Path $env:BHPSModuleManifest
    [System.Version]$ManifestVersion = $ModuleManifest.Version
    Write-Output -InputObject ('Manifest Version  : {0}' -f $ManifestVersion)

    Try {
        $PSGalleryModule = Find-Module -Name $env:BHProjectName -Repository PSGallery
        [System.Version]$PSGalleryVersion = $PSGalleryModule.Version
    } Catch {
        [System.Version]$PSGalleryVersion = '0.0.0'
    }
    Write-Output -InputObject ('PSGallery Version : {0}' -f $PSGalleryVersion)

    If ($PSGalleryVersion -ge $ManifestVersion) {

        [System.Version]$Version = New-Object -TypeName System.Version -ArgumentList ($PSGalleryVersion.Major, $PSGalleryVersion.Minor, ($PSGalleryVersion.Build + 1))
        Write-Output -InputObject ('Updated Version   : {0}' -f $Version)
        Update-ModuleManifest -ModuleVersion $Version -Path .\PSTwitterAPI\PSTwitterAPI.psd1 # -ReleaseNotes $ReleaseNotes

    }

}
#endregion

#region Task to Publish Module to PowerShell Gallery
task PublishModule -If ($Configuration -eq 'Production') {
    Try {

        # Publish to gallery with a few restrictions
        if(
            $env:BHModulePath -and
            $env:BHBuildSystem -ne 'Unknown' -and
            $env:BHBranchName -eq "master" -and
            $env:BHCommitMessage -match '!publish'
        )
        {

            # Build a splat containing the required details and make sure to Stop for errors which will trigger the catch
            $params = @{
                Path        = $env:BHModulePath
                NuGetApiKey = $env:NuGetApiKey
                ErrorAction = 'Stop'
            }
            Publish-Module @params
            Write-Output -InputObject ('PSTwitterAPI PowerShell Module version published to the PowerShell Gallery')

        }
        else
        {
            "Skipping deployment: To deploy, ensure that...`n" +
            "`t* You are in a known build system (Current: $ENV:BHBuildSystem)`n" +
            "`t* You are committing to the master branch (Current: $ENV:BHBranchName) `n" +
            "`t* Your commit message includes !publish (Current: $ENV:BHCommitMessage)" |
                Write-Host
        }

    }
    Catch {
        throw $_
    }
}
#endregion

#region Default Task. Runs Test, UpdateManifest, PublishModule Tasks
task . Test, UpdateManifest, PublishModule
#endregion