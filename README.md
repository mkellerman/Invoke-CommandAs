# Invoke-CommandAs

```
.SYNOPSIS

    Invoke Command as System/User on Local/Remote computer using ScheduleTask.

.DESCRIPTION

    Invoke Command as System/User on Local/Remote computer using ScheduleTask.
    ScheduledJob will be executed with current user credentials if no -As <credential> or -AsSystem is provided.

    Using ScheduledJob as they are ran in the background and the output can be retreived by any other process.
    Using ScheduledTask to Run the ScheduledJob, since you can allow Tasks to run as System or provide any credentials.
    
    Because the ScheduledJob is executed by the Task Scheduler, it is invoked locally as a seperate process and not from within the current Powershell Session.
    Resolving the Double Hop limitations by Powershell Remote Sessions. 

```
## Examples

```
# Execute Locally.
Invoke-CommandAs -ScriptBlock { Get-Process }

# Execute As System.
Invoke-CommandAs -ScriptBlock { Get-Process } -AsSystem

# Execute As different Credentials.
Invoke-CommandAs -ScriptBlock { Get-Process } -As $Credential

# Execute Remotely using ComputerName/Credential.
Invoke-CommandAs -ComputerName 'VM01' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely using PSSession.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process }

# Execute Remotely using PSSession, and execute ScriptBlock as SYSTEM and RunElevated.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process } -AsSystem -RunElevated

# Execute Remotely on multiple Computers at the same time.
Invoke-CommandAs -ComputerName 'VM01', 'VM02' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely as Job.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process } -AsJob
```

## How to see if it works:
```
$ScriptBlock = { [System.Security.Principal.Windowsidentity]::GetCurrent() }
Invoke-CommandAs -ScriptBlock $ScriptBlock -AsSystem
```

## Install Module (PSv5):
```
Install-Module -Name Invoke-CommandAs
```    

## Install Module (PSv4 or earlier):
```
Copy Invoke-CommandAs.psm1 to:
C:\Program Files\WindowsPowerShell\Modules\Invoke-CommandAs\Invoke-CommandAs.psm1
```

## Import Module directly from GitHub:
```
$WebClient = New-Object Net.WebClient
$psm1 = $WebClient.DownloadString("https://raw.githubusercontent.com/mkellerman/Invoke-CommandAs/master/Invoke-CommandAs.psm1")
Invoke-Expression $psm1
```
One liner:
```
(New-Object Net.WebClient).DownloadString("https://raw.githubusercontent.com/mkellerman/Invoke-CommandAs/master/Invoke-CommandAs.psm1") | iex
```
