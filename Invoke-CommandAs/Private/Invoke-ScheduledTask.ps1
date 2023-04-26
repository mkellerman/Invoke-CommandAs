function Invoke-ScheduledTask {

    #Requires -Version 3.0
    
    [cmdletbinding()]
    Param(
    [Parameter(Mandatory = $true)][ScriptBlock]$ScriptBlock,
    [Parameter(Mandatory = $false)][Object[]]$ArgumentList,
    [Parameter(Mandatory = $false)][PSCredential][System.Management.Automation.CredentialAttribute()]$AsUser,
    [Parameter(Mandatory = $false)][Switch]$AsSystem,
    [Parameter(Mandatory = $false)][String]$AsInteractive,
    [Parameter(Mandatory = $false)][String]$AsGMSA,
    [Parameter(Mandatory = $false)][Switch]$RunElevated

    )

    Process {
    
        $JobName = [guid]::NewGuid().Guid 
        Write-Verbose "$(Get-Date): ScheduledJob: Name: ${JobName}"

        $UseScheduledTask = If (Get-Command 'Register-ScheduledTask' -ErrorAction SilentlyContinue) { $True } Else { $False }

        Try {

            $JobParameters = @{
                Name = $JobName
            }
            If ($AsUser) { $JobParameters['Credential'] = $AsUser}
            If ($RunElevated.IsPresent) {
                $JobParameters['ScheduledJobOption'] = New-ScheduledJobOption -RunElevated -StartIfOnBattery -ContinueIfGoingOnBattery
            }
            Else {
                $JobParameters['ScheduledJobOption'] = New-ScheduledJobOption -StartIfOnBattery -ContinueIfGoingOnBattery
            }


            $JobArgumentList = @{
                Using = @()
            }
            If ($ScriptBlock)  { $JobArgumentList['ScriptBlock']  = $ScriptBlock }
            If ($ArgumentList) { $JobArgumentList['ArgumentList'] = $ArgumentList }

            # Little bit of inception to get $Using variables to work.
            # Collect $Using:variables, Rename and set new variables inside the job.

            # Inspired by Boe Prox, and his https://github.com/proxb/PoshRSJob module
            #      and by Warren Framem and his https://github.com/RamblingCookieMonster/Invoke-Parallel module

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

            Write-Verbose "$(Get-Date): ScheduledJob: Register"
            $ScheduledJob = Register-ScheduledJob @JobParameters -ScriptBlock $JobScriptBlock -ArgumentList $JobArgumentList -ErrorAction Stop

            If ($AsSystem -or $AsInteractive -or $AsUser -or $AsGMSA) {

                # Use ScheduledTask to execute the ScheduledJob to execute with the desired credentials.

                If ($UseScheduledTask) {

                    # For Windows 8 / Server 2012 and Newer

                    Write-Verbose "$(Get-Date): ScheduledTask: Register"
                    $TaskParameters = @{ TaskName = $ScheduledJob.Name }
                    $TaskParameters['Action'] = New-ScheduledTaskAction -Execute $ScheduledJob.PSExecutionPath -Argument $ScheduledJob.PSExecutionArgs
                    $TaskParameters['Settings'] = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                    If ($AsSystem) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                    } ElseIf ($AsGMSA) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID $AsGMSA -LogonType Password -RunLevel Highest
                    } ElseIf ($AsInteractive) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID $AsInteractive -LogonType Interactive -RunLevel Highest
                    } ElseIf ($AsUser) {
                        $TaskParameters['User'] = $AsUser.GetNetworkCredential().UserName
                        $TaskParameters['Password'] = $AsUser.GetNetworkCredential().Password
                    }
                    If ($RunElevated.IsPresent) {
                        $TaskParameters['RunLevel'] = 'Highest'
                    }
        
                    $ScheduledTask = Register-ScheduledTask @TaskParameters -ErrorAction Stop

                    Write-Verbose "$(Get-Date): ScheduledTask: Start"
                    $CimJob = $ScheduledTask | Start-ScheduledTask -AsJob -ErrorAction Stop
                    $CimJob | Wait-Job | Remove-Job -Force -Confirm:$False

                    Write-Verbose "$(Get-Date): ScheduledTask: Wait"
                    While (($ScheduledTaskInfo = $ScheduledTask | Get-ScheduledTaskInfo).LastTaskResult -eq 267009) { Start-Sleep -Milliseconds 200 }

                } Else {

                    # For Windows 7 / Server 2008 R2

                    Write-Verbose "$(Get-Date): ScheduleService: Register"
                    $ScheduleService = New-Object -ComObject("Schedule.Service")
                    $ScheduleService.Connect()
                    $ScheduleTaskFolder = $ScheduleService.GetFolder("\")
                    $TaskDefinition = $ScheduleService.NewTask(0) 
                    $TaskDefinition.Principal.RunLevel = $RunElevated.IsPresent
                    $TaskAction = $TaskDefinition.Actions.Create(0)
                    $TaskAction.Path = $ScheduledJob.PSExecutionPath
                    $TaskAction.Arguments = $ScheduledJob.PSExecutionArgs
                    
                    If ($AsUser) {
                        $Username = $AsUser.GetNetworkCredential().UserName
                        $Password = $AsUser.GetNetworkCredential().Password
                        $LogonType = 1
                    } ElseIf ($AsInteractive) {
                        $Username = $AsInteractive
                        $Password = $null
                        $LogonType = 3
                        $TaskDefinition.Principal.RunLevel = 1
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


                    $RegisteredTask = $ScheduleTaskFolder.RegisterTaskDefinition($ScheduledJob.Name,$TaskDefinition,6,$Username,$Password,$LogonType)

                    Write-Verbose "$(Get-Date): ScheduleService: Start"
                    $ScheduledTask = $RegisteredTask.Run($null)

                    Write-Verbose "$(Get-Date): ScheduleService: Wait: Start"
                    Do { $ScheduledTaskInfo = $ScheduleTaskFolder.GetTasks(1) | Where-Object Name -eq $ScheduledTask.Name; Start-Sleep -Milliseconds 100 }
                    While ($ScheduledTaskInfo.State -eq 3 -and $ScheduledTaskInfo.LastTaskResult -eq 267045)

                    Write-Verbose "$(Get-Date): ScheduleService: Wait: End"
                    Do { $ScheduledTaskInfo = $ScheduleTaskFolder.GetTasks(1) | Where-Object Name -eq $ScheduledTask.Name; Start-Sleep -Milliseconds 100 }
                    While ($ScheduledTaskInfo.State -eq 4)

                }

                If ($ScheduledTaskInfo.LastRunTime.Year -ne (Get-Date).Year) { 
                    Write-Error 'Task was unable to be executed.'
                    Return 
                }

            } Else {

                # It no other credentials where provided, execute the ScheduledJob as is.
                Write-Verbose "$(Get-Date): ScheduledTask: Start"
                $ScheduledJob.StartJob() | Out-Null

            }

            Write-Verbose "$(Get-Date): ScheduledJob: Get"
            $Job = Get-Job -Name $ScheduledJob.Name -ErrorAction SilentlyContinue

            Write-Verbose "$(Get-Date): ScheduledJob: Receive"
            If ($Job) { $Job | Wait-Job | Receive-Job -Wait -AutoRemoveJob }

        } Catch { 
            
            Write-Verbose "$(Get-Date): TryCatch: Error"
            Write-Error $_ 
        
        } Finally {

            Write-Verbose "$(Get-Date): ScheduledJob: Unregister"
            If ($ScheduledJob) { Get-ScheduledJob -Id $ScheduledJob.Id -ErrorAction SilentlyContinue | Unregister-ScheduledJob -Force -Confirm:$False | Out-Null }

            Write-Verbose "$(Get-Date): ScheduledTask: Unregister"
            If ($ScheduledTask) { 
                If ($UseScheduledTask) {
                    $ScheduledTask | Get-ScheduledTask -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$False | Out-Null
                } Else {
                    $ScheduleTaskFolder.DeleteTask($ScheduledTask.Name, 0) | Out-Null 
                }
            }
        
        }

    }

}
