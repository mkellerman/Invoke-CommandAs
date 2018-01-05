# Invoke-CommandAs

```
.SYNOPSIS

    Invoke Command using ScheduledJob with Credential on remote computer.

.DESCRIPTION

    Invoke a ScheduledJob on machine (Remote if ComputerName/Session is provided).
    ScheduledJob will be executed with current user credentials if no -As credential are provided.

    Because the ScheduledJob is executed by the Task Scheduler, it runs as if it was ran locally. And not from within the Powershell Session.
    Resolving the Double Hop limitations by Powershell Remote Sessions. 

    By Marc R Kellerman (@mkellerman)
```

