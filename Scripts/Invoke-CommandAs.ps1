#####################################################################
# Name        : Invoke-CommandAs
# Version     : 3.1.2
# Description : Invoke Command as System/User on Local/Remote computer using ScheduleTask.
# ProjectUri  : https://github.com/mkellerman/Invoke-CommandAs
# Author      : Marc R Kellerman
#####################################################################

function Invoke-ScheduledTask {

    #Requires -Version 3.0
    
    [cmdletbinding()]
    Param(
    [Parameter(Mandatory = $true)][ScriptBlock]$ScriptBlock,
    [Parameter(Mandatory = $false)][Object[]]$ArgumentList,
    [Parameter(Mandatory = $false)][PSCredential][System.Management.Automation.CredentialAttribute()]$AsUser,
    [Parameter(Mandatory = $false)][Switch]$AsSystem,
    [Parameter(Mandatory = $false)][String]$AsInteractive,
    [Parameter(Mandatory = $false)][String]$AsGMSA

    )

    Process {
    
        $JobName = [guid]::NewGuid().Guid 
        Write-Verbose "$(Get-Date): ScheduledJob: Name: ${JobName}"

        $UseScheduledTask = If (Get-Command 'Register-ScheduledTask' -ErrorAction SilentlyContinue) { $True } Else { $False }

        Try {

            $JobParameters = @{ }
            $JobParameters['Name'] = $JobName
            $JobParameters['ScheduledJobOption'] = New-ScheduledJobOption -RunElevated

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

            Write-Verbose "$(Get-Date): ScheduledJob: Register"
            $ScheduledJob = Register-ScheduledJob @JobParameters -ScriptBlock $JobScriptBlock -ArgumentList $JobArgumentList -ErrorAction Stop

            If ($AsSystem -or $AsInteractive -or $AsUser -or $AsGMSA) {

                # Use ScheduledTask to execute the ScheduledJob to execute with the desired credentials.

                If ($UseScheduledTask) {

                    # For Windows 8 / Server 2012 and Newer

                    Write-Verbose "$(Get-Date): ScheduledTask: Register"
                    $TaskParameters = @{ TaskName = $ScheduledJob.Name }
                    $TaskParameters['Action'] = New-ScheduledTaskAction -Execute $ScheduledJob.PSExecutionPath -Argument $ScheduledJob.PSExecutionArgs
                    If ($AsSystem) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                    } ElseIf ($AsGMSA) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID $AsGMSA -LogonType Password -RunLevel Highest
                    } ElseIf ($AsInteractive) {
                        $TaskParameters['Principal'] = New-ScheduledTaskPrincipal -UserID $AsInteractive -LogonType Interactive -RunLevel Highest
                    } ElseIf ($AsUser) {
                        $TaskParameters['User'] = $AsUser.GetNetworkCredential().UserName
                        $TaskParameters['Password'] = $AsUser.GetNetworkCredential().Password
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
function Invoke-CommandAs {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Invoke Command as System/User on Local/Remote computer using ScheduleTask.
    
    .DESCRIPTION
    
        Invoke Command as System/User on Local/Remote computer using ScheduleTask.
        ScheduledJob will be executed with current user credentials if no -As <credential> or -AsSystem is provided.
    
        Using ScheduledJob as they are ran in the background and the output can be retreived by any other process.
        Using ScheduledTask to Run the ScheduledJob, since you can allow Tasks to run as System or provide any credentials.
        
        Because the ScheduledJob is executed by the Task Scheduler, it is invoked locally as a seperate process and not from within the current Powershell Session.
        Resolving the Double Hop limitations by Powershell Remote Sessions. 
    
        By Marc R Kellerman (@mkellerman)
    
    .PARAMETER AsSystem
    
        ScheduledJob will be executed using 'NT AUTHORITY\SYSTEM'. 
    
    .PARAMETER AsInteractive
    
        ScheduledJob will be executed using another users Interactive session. 
    
    .PARAMETER AsGMSA
    
        ScheduledJob will be executed as the specified GMSA. For Example, 'domain\gmsa$'
            
    .PARAMETER AsUser
    
        ScheduledJob will be executed using this user. Specifies a user account that has permission to perform this action. The default is the current user.
            
        Type a user name, such as User01 or Domain01\User01. Or, enter a PSCredential object, such as one generated by the Get-Credential cmdlet. If you type a user name, this cmdlet prompts you for a password.
            
    #>
    
        #Requires -Version 3

        #Parameters generated using ProxyCommand on v5.1
        #[System.Management.Automation.ProxyCommand]::Create((gcm Invoke-Command))

        [CmdletBinding(DefaultParameterSetName='InProcess', HelpUri='http://go.microsoft.com/fwlink/?LinkID=135225', RemotingCapability='OwnedByCommand')]
        param(
            [Parameter(ParameterSetName='Session', Position=0)]
            [Parameter(ParameterSetName='FilePathRunspace', Position=0)]
            [ValidateNotNullOrEmpty()]
            [System.Management.Automation.Runspaces.PSSession[]]
            ${Session},
        
            [Parameter(ParameterSetName='FilePathComputerName', Position=0)]
            [Parameter(ParameterSetName='ComputerName', Position=0)]
            [Alias('Cn')]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${ComputerName},
        
            [Parameter(ParameterSetName='FilePathComputerName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='Uri', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='ComputerName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathUri', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='VMId', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='VMName', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMId', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMName', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [pscredential]
            [System.Management.Automation.CredentialAttribute()]
            ${Credential},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [ValidateRange(1, 65535)]
            [int]
            ${Port},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [switch]
            ${UseSSL},
        
            [Parameter(ParameterSetName='Uri', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='ComputerName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathComputerName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathUri', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='ContainerId', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='VMId', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='VMName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathContainerId', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMId', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMName', ValueFromPipelineByPropertyName=$true)]
            [string]
            ${ConfigurationName},
        
            [Parameter(ParameterSetName='ComputerName', ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathComputerName', ValueFromPipelineByPropertyName=$true)]
            [string]
            ${ApplicationName},
        
            [Parameter(ParameterSetName='FilePathRunspace')]
            [Parameter(ParameterSetName='Session')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='FilePathUri')]
            [Parameter(ParameterSetName='VMId')]
            [Parameter(ParameterSetName='VMName')]
            [Parameter(ParameterSetName='ContainerId')]
            [Parameter(ParameterSetName='FilePathVMId')]
            [Parameter(ParameterSetName='FilePathVMName')]
            [Parameter(ParameterSetName='FilePathContainerId')]
            [int]
            ${ThrottleLimit},
        
            [Parameter(ParameterSetName='Uri', Position=0)]
            [Parameter(ParameterSetName='FilePathUri', Position=0)]
            [Alias('URI','CU')]
            [ValidateNotNullOrEmpty()]
            [uri[]]
            ${ConnectionUri},
        
            [Parameter(ParameterSetName='FilePathRunspace')]
            [Parameter(ParameterSetName='Session')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='FilePathUri')]
            [Parameter(ParameterSetName='VMId')]
            [Parameter(ParameterSetName='VMName')]
            [Parameter(ParameterSetName='ContainerId')]
            [Parameter(ParameterSetName='FilePathVMId')]
            [Parameter(ParameterSetName='FilePathVMName')]
            [Parameter(ParameterSetName='FilePathContainerId')]
            [switch]
            ${AsJob},
        
            [Parameter(ParameterSetName='FilePathUri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='ComputerName')]
            [Alias('Disconnected')]
            [switch]
            ${InDisconnectedSession},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${SessionName},
        
            [Parameter(ParameterSetName='VMId')]
            [Parameter(ParameterSetName='Session')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='FilePathRunspace')]
            [Parameter(ParameterSetName='FilePathUri')]
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='VMName')]
            [Parameter(ParameterSetName='ContainerId')]
            [Parameter(ParameterSetName='FilePathVMId')]
            [Parameter(ParameterSetName='FilePathVMName')]
            [Parameter(ParameterSetName='FilePathContainerId')]
            [Alias('HCN')]
            [switch]
            ${HideComputerName},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='Session')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='FilePathRunspace')]
            [Parameter(ParameterSetName='FilePathUri')]
            [Parameter(ParameterSetName='ContainerId')]
            [Parameter(ParameterSetName='FilePathContainerId')]
            [string]
            ${JobName},
        
            [Parameter(ParameterSetName='VMId', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='Session', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='Uri', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='InProcess', Mandatory=$true, Position=0)]
            [Parameter(ParameterSetName='ComputerName', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='VMName', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='ContainerId', Mandatory=$true, Position=1)]
            [Alias('Command')]
            [ValidateNotNull()]
            [scriptblock]
            ${ScriptBlock},
        
            [Parameter(ParameterSetName='InProcess')]
            [switch]
            ${NoNewScope},
        
            [Parameter(ParameterSetName='FilePathVMId', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='FilePathRunspace', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='FilePathUri', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='FilePathComputerName', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='FilePathVMName', Mandatory=$true, Position=1)]
            [Parameter(ParameterSetName='FilePathContainerId', Mandatory=$true, Position=1)]
            [Alias('PSPath')]
            [ValidateNotNull()]
            [string]
            ${FilePath},
        
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathUri')]
            [switch]
            ${AllowRedirection},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='FilePathUri')]
            [System.Management.Automation.Remoting.PSSessionOption]
            ${SessionOption},
        
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathUri')]
            [System.Management.Automation.Runspaces.AuthenticationMechanism]
            ${Authentication},
        
            [Parameter(ParameterSetName='FilePathComputerName')]
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='Uri')]
            [Parameter(ParameterSetName='FilePathUri')]
            [switch]
            ${EnableNetworkAccess},
        
            [Parameter(ParameterSetName='ContainerId')]
            [Parameter(ParameterSetName='FilePathContainerId')]
            [switch]
            ${RunAsAdministrator},
        
            [Parameter(ValueFromPipeline=$true)]
            [psobject]
            ${InputObject},
        
            [Alias('Args')]
            [System.Object[]]
            ${ArgumentList},
        
            [Parameter(ParameterSetName='VMId', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMId', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
            [Alias('VMGuid')]
            [ValidateNotNullOrEmpty()]
            [guid[]]
            ${VMId},
        
            [Parameter(ParameterSetName='VMName', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathVMName', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${VMName},
        
            [Parameter(ParameterSetName='ContainerId', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FilePathContainerId', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            ${ContainerId},
        
            [Parameter(ParameterSetName='ComputerName')]
            [Parameter(ParameterSetName='Uri')]
            [string]
            ${CertificateThumbprint},

            [Parameter(Mandatory = $false)]
            [Alias("System")]
            [switch]
            ${AsSystem},
    
            [Parameter(Mandatory = $false)]
            [Alias("Interactive")]
            [string]
            ${AsInteractive},
    
            [Parameter(Mandatory = $false)]
            [Alias("GMSA")]
            [string]
            ${AsGMSA},
        
            [Parameter(Mandatory = $false)]
            [Alias("User")]
            [pscredential]
            [System.Management.Automation.CredentialAttribute()]
            ${AsUser}
        
        )
    
       Process {

            $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

            # Collect all the parameters, and prepare them to be splatted to the Invoke-Command
            [hashtable]$CommandParameters = $PSBoundParameters
            $ParameterNames = @('AsSystem', 'AsInteractive', 'AsUser', 'AsGMSA', 'FilePath','ScriptBlock', 'ArgumentList')
            ForEach ($ParameterName in $ParameterNames) {
                $CommandParameters.Remove($ParameterName)
            }
            
            If ($FilePath) { 
                $ScriptContent = Get-Content -Path $FilePath 
                $ScriptBlock = [ScriptBlock]::Create($ScriptContent)
            }
            
            # Collect the functions to bring with us in the remote session:
            $_Function = ${Function:Invoke-ScheduledTask}.Ast.Extent.Text

            # Collect the $Using variables to load in the remote session:
            $_Using = @()
            $UsingVariables = $ScriptBlock.ast.FindAll({$args[0] -is [System.Management.Automation.Language.UsingExpressionAst]},$True)
            If ($UsingVariables) {

                $ScriptText = $ScriptBlock.Ast.Extent.Text
                $ScriptOffSet = $ScriptBlock.Ast.Extent.StartOffset
                ForEach ($SubExpression in ($UsingVariables.SubExpression | Sort-Object { $_.Extent.StartOffset } -Descending)) {

                    $Name = '__using_{0}' -f (([Guid]::NewGuid().guid) -Replace '-')
                    $Expression = $SubExpression.Extent.Text.Replace('$Using:','$').Replace('${Using:','${'); 
                    $Value = [System.Management.Automation.PSSerializer]::Serialize((Invoke-Expression $Expression))
                    $_Using += [PSCustomObject]@{ Name = $Name; Value = $Value } 
                    $ScriptText = $ScriptText.Substring(0, ($SubExpression.Extent.StartOffSet - $ScriptOffSet)) + "`${Using:$Name}" + $ScriptText.Substring(($SubExpression.Extent.EndOffset - $ScriptOffSet))

                }
                $ScriptBlock = [ScriptBlock]::Create($ScriptText.TrimStart("{").TrimEnd("}"))
            }
        
            Invoke-Command @CommandParameters -ScriptBlock {
                
                If ($PSVersionTable.PSVersion.Major -lt 3) {

                    $ErrorMsg = "The function 'Invoke-ScheduledTask' cannot be run because it contained a '#requires' " + `
                                "statement for PowerShell 3.0. The version of PowerShell that is required by the " + `
                                "module does not match the remotly running version of PowerShell $($PSVersionTable.PSVersion.ToString())."
                    Throw $ErrorMsg
                    Return 

                }

                    # Create the functions/variables we packed up with us previously:
                    $Using:_Function | ForEach-Object { Invoke-Expression $_ }
                    $Using:_Using | ForEach-Object { Set-Variable -Name $_.Name -Value ([System.Management.Automation.PSSerializer]::Deserialize($_.Value)) }
        
                    $Parameters = @{}
                    If ($Using:ScriptBlock)   { $Parameters['ScriptBlock']   = [ScriptBlock]::Create($Using:ScriptBlock) }
                    If ($Using:ArgumentList)  { $Parameters['ArgumentList']  = $Using:ArgumentList                       }
                    If ($Using:AsUser)        { $Parameters['AsUser']        = $Using:AsUser                             }
                    If ($Using:AsSystem)      { $Parameters['AsSystem']      = $Using:AsSystem.IsPresent                 }
                    If ($Using:AsInteractive) { $Parameters['AsInteractive'] = $Using:AsInteractive                      }
                    If ($Using:AsGMSA)        { $Parameters['AsGMSA']        = $Using:AsGMSA                             }
                    If ($Using:IsVerbose)     { $Parameters['Verbose']       = $Using:IsVerbose                          }
        
                    Invoke-ScheduledTask @Parameters

            }

        }
        
    }
    
