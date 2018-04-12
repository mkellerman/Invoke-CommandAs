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
Invoke-CommandAs -ScriptBlock { Get-Process }

# Execute As different Credentials.
Invoke-CommandAs -ScriptBlock { Get-Process } -As $Credential

# Execute Remotely using ComputerName/Credential.
Invoke-CommandAs -ComputerName 'VM01' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely using PSSession.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process }

# Execute Remotely on multiple Computers at the same time.
Invoke-CommandAs -ComputerName 'VM01', 'VM02' -Credential $Credential -ScriptBlock { Get-Process }

# Execute Remotely as Job.
Invoke-CommandAs -Session $PSSession -ScriptBlock { Get-Process } -AsJob
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
