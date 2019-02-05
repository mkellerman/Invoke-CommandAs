function Invoke-ScheduledTask {

    #Requires -Version 3
    
    [cmdletbinding()]
    Param(
    [Parameter(Mandatory = $true)][ScriptBlock]$ScriptBlock,
    [Parameter(Mandatory = $false)][Object[]]$ArgumentList,
    [Parameter(Mandatory = $false)][System.Management.Automation.PSCredential]$AsCredential,
    [Parameter(Mandatory = $false)][Switch]$AsSystem,
    [Parameter(Mandatory = $false)][String]$AsGMSA,
    [Parameter(Mandatory = $false)][Switch]$RunElevated

    )

    Begin { 
    
        $JobName = [guid]::NewGuid().Guid 

    }

    Process {
    
        Try {

            $JobParameters = @{ }
            $JobParameters['Name'] = $JobName
            If ($RunElevated)  { $JobParameters['ScheduledJobOption'] = New-ScheduledJobOption -RunElevated }

            $JobArgumentList = @{ }
            If ($ScriptBlock)  { $JobArgumentList['ScriptBlock']  = $ScriptBlock }
            If ($ArgumentList) { $JobArgumentList['ArgumentList'] = $ArgumentList }

            # Little bit of inception to get $Using variables to work.
            # Collect $Using:variables, Rename and set new variables inside the job.

            # Inspired by Boe Prox, and his https://github.com/proxb/PoshRSJob module
            #      and by Warren Framem and his https://github.com/RamblingCookieMonster/Invoke-Parallel module

            $JobArgumentList['Using'] = @()
            $UsingVariables = $ScriptBlock.ast.FindAll({$args[0] -is [System.Management.Automation.Language.UsingExpressionAst]},$True)
            If ($UsingVariables) {

                $ScriptText = $ScriptBlock.Ast.Extent.Text
                $ScriptOffSet = $ScriptBlock.Ast.Extent.StartOffset
                ForEach ($SubExpression in ($UsingVariables.SubExpression | Sort-Object { $_.Extent.StartOffset } -Descending)) {

                    $Name = '__using_{0}' -f (([Guid]::NewGuid().guid) -Replace '-')
                    $Expression = $SubExpression.Extent.Text.Replace('$Using:','$').Replace('${Using:','${'); 
                    $Value = [System.Management.Automation.PSSerializer]::Serialize((Invoke-Expression $Expression))
                    $JobArgumentList['Using'] += [PSCustomObject]@{ Name = $Name; Value = $Value } 
                    $ScriptText = $ScriptText.Substring(0, ($SubExpression.Extent.StartOffSet - $ScriptOffSet)) + "`${Using:$Name}" + $ScriptText.Substring(($SubExpression.Extent.EndOffset - $ScriptOffSet))

                }
                $JobArgumentList['ScriptBlock'] = [ScriptBlock]::Create($ScriptText.TrimStart("{").TrimEnd("}"))
            }

            $JobScriptBlock = [ScriptBlock]::Create(@"

                Param(`$Parameters)

                `$JobParameters = @{}
                If (`$Parameters.ScriptBlock)  { `$JobParameters['ScriptBlock']  = [ScriptBlock]::Create(`$Parameters.ScriptBlock) }
                If (`$Parameters.ArgumentList) { `$JobParameters['ArgumentList'] = `$Parameters.ArgumentList }

                If (`$Parameters.Using) { 
                    `$Parameters.Using | % { Set-Variable -Name `$_.Name -Value ([System.Management.Automation.PSSerializer]::Deserialize(`$_.Value)) }
                    Start-Job @JobParameters | Receive-Job -Wait -AutoRemoveJob
                } Else {
                    Invoke-Command @JobParameters
                }
"@)

            Write-Verbose "Register-ScheduledJob: $($JobParameters['Name'])"
            $ScheduledJob = Register-ScheduledJob @JobParameters -ScriptBlock $JobScriptBlock -ArgumentList $JobArgumentList -ErrorAction Stop

            If (($AsCredential) -or ($AsSystem) -or ($AsGMSA)) {

                # Use ScheduledTask to execute the ScheduledJob to execute with the desired credentials.

                If (Get-Command 'Register-ScheduledTask' -ErrorAction SilentlyContinue) {

                    # For Windows 8 / Server 2012 and Newer

                    Write-Verbose "Register-ScheduledTask"
                    $TaskParameters = @{ TaskName = $ScheduledJob.Name }
                    $TaskParameters['Action'] = New-ScheduledTaskAction -Execute $ScheduledJob.PSExecutionPath -Argument $ScheduledJob.PSExecutionArgs
                    $RunLevel = If ($RunElevated) { 'Highest' } Else { 'Limited' }
                    If ($AsCredential) {
                        $TaskParameters['User'] = $AsCredential.GetNetworkCredential().UserName
                        $TaskParameters['Password'] = $AsCredential.GetNetworkCredential().Password
                    } ElseIf ($AsSystem) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel $RunLevel
                    } ElseIf ($AsGMSA) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID $AsGMSA -LogonType Password -RunLevel $RunLevel
                    }
                    $ScheduledTask = Register-ScheduledTask @TaskParameters -ErrorAction Stop

                    Write-Verbose "Start-ScheduledTask"
                    $CimJob = $ScheduledTask | Start-ScheduledTask -AsJob -ErrorAction Stop
                    $CimJob | Wait-Job | Remove-Job -Force -Confirm:$False

                } Else {

                    # For Windows 7 / Server 2008 R2

                    Write-Verbose "Register-ScheduledTask"
                    $ScheduleService = New-Object -ComObject("Schedule.Service")
                    $ScheduleService.Connect()
                    $ScheduleTaskFolder = $ScheduleService.GetFolder("\")
                    $TaskDefinition = $ScheduleService.NewTask(0) 
                    $TaskAction = $TaskDefinition.Actions.Create(0)
                    $TaskAction.Path = $ScheduledJob.PSExecutionPath
                    $TaskAction.Arguments = $ScheduledJob.PSExecutionArgs

                    If ($AsCredential) {
                        $Username = $AsCredential.GetNetworkCredential().UserName
                        $Password = $AsCredential.GetNetworkCredential().Password
                        $LogonType = 1
                    } ElseIf ($AsSystem) {
                        $Username = "System"
                        $Password = $null
                        $LogonType = 5
                    } ElseIf ($AsGMSA) {
                        # Needs to be tested
                        $Username = $AsGMSA
                        $Password = $null
                        $LogonType = 5
                    }

                    $TaskDefinition = $ScheduleTaskFolder.RegisterTaskDefinition($ScheduledJob.Name,$TaskDefinition,6,$Username,$Password,$LogonType)

                    Write-Verbose "Start-ScheduledTask"
                    $TaskInfo = $TaskDefinition.Run($null)
                    
                    $ScheduledTask = Get-ScheduledTask -TaskName $TaskInfo.Name -TaskPath "\"

                }

                Write-Verbose "Get-ScheduledTaskInfo"
                $ScheduledTaskInfo = $ScheduledTask | Get-ScheduledTaskInfo
                If ($ScheduledTaskInfo.LastRunTime.Year -gt 1999) {

                    Write-Verbose "Get-ScheduledJob"
                    While (-Not($Job = Get-Job -Name $ScheduledJob.Name -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 200 }
    
                    Write-Verbose "Receive-ScheduledJob"
                    $Job | Wait-Job | Receive-Job -Wait -AutoRemoveJob

                } Else {

                    Write-Error 'Task was unable to be executed.'

                }

            } Else {

                # It no other credentials where provided, execute the ScheduledJob as is.
                Write-Verbose "Start-ScheduledTask"
                $Job = $ScheduledJob.StartJob()

                Write-Verbose "Receive-ScheduledJob"
                $Job  | Receive-Job -Wait -AutoRemoveJob

            }

        } Catch { Write-Error $_ }

    }

    End {

        If ($ScheduledTask) {
            Write-Verbose "Unregister ScheduledTask"
            # For Windows 8 / Server 2012 and Newer
            Try { $ScheduledTask | Unregister-ScheduledTask -Confirm:$False } Catch { $Null }
            # For Windows 7 / Server 2008 R2
            Try { $ScheduleTaskFolder.DeleteTask($ScheduledTask.Name, 0) | Out-Null } Catch { $Null }
        }

        If ($ScheduledJob) {
            Write-Verbose "Unregister ScheduledJob"
            # For Windows 8 / Server 2012 and Newer
            Try { $ScheduledJob | Unregister-ScheduledJob -Force -Confirm:$False | Out-Null } Catch { $Null } 
            # For Windows 7 / Server 2008 R2
            Try { $ScheduleTaskFolder.DeleteTask($ScheduledJob.Name, 0) | Out-Null } Catch { $Null }
        }

    }

}