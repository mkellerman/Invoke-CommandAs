[![PSGallery Version](https://img.shields.io/powershellgallery/v/Invoke-CommandAs.svg?style=for-the-badge&label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Invoke-CommandAs/)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/Invoke-CommandAs.svg?style=for-the-badge&label=Downloads)](https://www.powershellgallery.com/packages/Invoke-CommandAs/)

[![Azure Pipeline](https://img.shields.io/azure-devops/build/mkellerman/Invoke-CommandAs/8.svg?style=for-the-badge&label=Azure%20Pipeline)](https://dev.azure.com/mkellerman/Invoke-CommandAs/_build?definitionId=8)
[![Analytics](https://ga-beacon.appspot.com/UA-133882862-1/Invoke-CommandAs?pixel)](https://github.com/mkellerman)

# Invoke-CommandAs

```
.SYNOPSIS

    Invoke Command as System/User on Local/Remote computer using ScheduleTask.

.DESCRIPTION

    Invoke Command as System/User on Local/Remote computer using ScheduleTask.
    ScheduledJob will be executed with current user credentials if no -AsUser <credential> or -AsSystem is provided.

    Using ScheduledJob as they are ran in the background and the output can be retreived by any other process.
    Using ScheduledTask to Run the ScheduledJob, since you can allow Tasks to run as System or provide any credentials.
    
    Because the ScheduledJob is executed by the Task Scheduler, it is invoked locally as a seperate process and not from within the current Powershell Session.
    Resolving the Double Hop limitations by Powershell Remote Sessions. 

```
## Examples

```powershell
# Execute Locally.
Invoke-CommandAs -ScriptBlock { Get-Process }

# Execute As System.
Invoke-CommandAs -ScriptBlock { Get-Process } -AsSystem

# Execute As a GMSA.
Invoke-CommandAs -ScriptBlock { Get-Process } -AsGMSA 'domain\gmsa$'

# Execute As Credential of another user.
Invoke-CommandAs -ScriptBlock { Get-Process } -AsUser $Credential

# Execute As Interactive session of another user.
Invoke-CommandAs -ScriptBlock { Get-Process } -AsInteractive 'username'

```
### You can execute all the same commands as above against a remote machine.
### Use -ComputerName/Credential or -Session to authenticate
```powershell
# Execute Remotely using ComputerName/Credential.
Invoke-CommandAs -ComputerName 'VM01' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely using Session.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process }

# Execute Remotely using PSSession, and execute ScriptBlock as SYSTEM and RunElevated.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process } -AsSystem -RunElevated

# Execute Remotely on multiple Computers at the same time.
Invoke-CommandAs -ComputerName 'VM01', 'VM02' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely as Job.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process } -AsJob
```

## How to see if it works:
```powershell
$ScriptBlock = { [System.Security.Principal.Windowsidentity]::GetCurrent() }
Invoke-CommandAs -ScriptBlock $ScriptBlock -AsSystem
```

## Install Module (PSv5):
```powershell
Install-Module -Name Invoke-CommandAs
```    

## Install Module (PSv4 or earlier):
```
Copy Invoke-CommandAs folder to:
C:\Program Files\WindowsPowerShell\Modules\Invoke-CommandAs
```

## Import Module directly from GitHub:
```
$WebClient = New-Object Net.WebClient
$WebClient.DownloadString("https://raw.githubusercontent.com/mkellerman/Invoke-CommandAs/master/Invoke-CommandAs/Private/Invoke-ScheduledTask.ps1") | Set-Content -Path ".\Invoke-ScheduledTask.ps1"
$WebClient.DownloadString("https://raw.githubusercontent.com/mkellerman/Invoke-CommandAs/master/Invoke-CommandAs/Public/Invoke-CommandAs.ps1") | Set-Content -Path ".\Invoke-CommandAs.ps1"
Import-Module ".\Invoke-ScheduleTask.ps1"
Import-Module ".\Invoke-CommandAs.ps1"
```
One liner (dont write to disk):
```
"Public/Invoke-CommandAs.ps1", "Private/Invoke-ScheduledTask.ps1" | % {
    . ([ScriptBlock]::Create((New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/mkellerman/Invoke-CommandAs/master/Invoke-CommandAs/${_}")))
}
```
