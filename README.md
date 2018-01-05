# Invoke-CommandAs

```
.SYNOPSIS

    Invoke Command using ScheduledJob with Credential on remote computer.

.DESCRIPTION

    Invoke a ScheduledJob on machine (Remote if ComputerName/Session is provided).
    ScheduledJob will be executed with current user credentials if no -As credential are provided.

    Because the ScheduledJob is executed by the Task Scheduler, it runs as if it was ran locally. And not from within the Powershell Session.
    Resolving the Double Hop limitations by Powershell Remote Sessions. 

```
## Examples

```
# Execute Locally.
Invoke-CommandAs -ScriptBlock { & notepad.exe }

# Execute Remotelly using ComputerName/Credential.
Invoke-CommandAs -ComputerName 'VM01' -Credential $Credential -ScriptBlock { & notepad.exe }

# Execute Remotelly using PSSession.
Invoke-CommandAs -Session $PSSession -ScriptBlock { & notepad.exe }

# Execute Remotelly on multiple Remote Computers at the same time.
Invoke-CommandAs -ComputerName 'VM01', 'VM02' -Credential $Credential -ScriptBlock { & notepad.exe }

# Execute Remotelly as Job.
Invoke-CommandAs -Session $PSSession -ScriptBlock { & notepad.exe } -AsJob
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
