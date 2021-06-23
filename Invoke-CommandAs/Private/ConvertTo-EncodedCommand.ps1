function ConvertTo-EncodedCommand
{

    [CmdletBinding( DefaultParameterSetName = 'FilePath')] Param (
        [Parameter(Position = 0, ValueFromPipeline = $True, ParameterSetName = 'ScriptBlock' )]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Position = 0, ParameterSetName = 'FilePath' )]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path,

        [Switch]
        $NoExit,

        [Switch]
        $NoProfile,

        [Switch]
        $NonInteractive,

        [Switch]
        $Wow64,

        [ValidateSet('Normal', 'Minimized', 'Maximized', 'Hidden')]
        [String]
        $WindowStyle,

        [Switch]
        $EncodedOutput
    )

    if ($PSBoundParameters['Path'])
    {
        Get-ChildItem $Path -ErrorAction Stop | Out-Null
        $ScriptBytes = [IO.File]::ReadAllBytes((Resolve-Path $Path))
    }
    else
    {
        $ScriptBytes = ([Text.Encoding]::ASCII).GetBytes($ScriptBlock)
    }

    $CompressedStream = New-Object IO.MemoryStream
    $DeflateStream = New-Object IO.Compression.DeflateStream ($CompressedStream, [IO.Compression.CompressionMode]::Compress)
    $DeflateStream.Write($ScriptBytes, 0, $ScriptBytes.Length)
    $DeflateStream.Dispose()
    $CompressedScriptBytes = $CompressedStream.ToArray()
    $CompressedStream.Dispose()
    $EncodedCompressedScript = [Convert]::ToBase64String($CompressedScriptBytes)

    # Generate the code that will decompress and execute the payload.
    # This code is intentionally ugly to save space.
    $NewScript = 'sal a New-Object;iex(a IO.StreamReader((a IO.Compression.DeflateStream([IO.MemoryStream][Convert]::FromBase64String(' + "'$EncodedCompressedScript'" + '),[IO.Compression.CompressionMode]::Decompress)),[Text.Encoding]::ASCII)).ReadToEnd()'

    # Base-64 strings passed to -EncodedCommand must be unicode encoded.
    $UnicodeEncoder = New-Object System.Text.UnicodeEncoding
    $EncodedPayloadScript = [Convert]::ToBase64String($UnicodeEncoder.GetBytes($NewScript))

    # Build the command line options
    # Use the shortest possible command-line arguments to save space. Thanks @obscuresec for the idea.
    $CommandlineOptions = New-Object String[](0)
    if ($PSBoundParameters['NoExit'])
    { $CommandlineOptions += '-NoE' }
    if ($PSBoundParameters['NoProfile'])
    { $CommandlineOptions += '-NoP' }
    if ($PSBoundParameters['NonInteractive'])
    { $CommandlineOptions += '-NonI' }
    if ($PSBoundParameters['WindowStyle'])
    { $CommandlineOptions += "-W $($PSBoundParameters['WindowStyle'])" }

    $CmdMaxLength = 8190

    # Build up the full command-line string. Default to outputting a fully base-64 encoded command.
    # If the fully base-64 encoded output exceeds the cmd.exe character limit, fall back to partial
    # base-64 encoding to save space. Thanks @Carlos_Perez for the idea.
    if ($PSBoundParameters['Wow64'])
    {
        $CommandLineOutput = "$($Env:windir)\SysWOW64\WindowsPowerShell\v1.0\powershell.exe $($CommandlineOptions -join ' ') -C `"$NewScript`""

        if ($PSBoundParameters['EncodedOutput'] -or $CommandLineOutput.Length -le $CmdMaxLength)
        {
            $CommandLineOutput = "$($Env:windir)\SysWOW64\WindowsPowerShell\v1.0\powershell.exe $($CommandlineOptions -join ' ') -E `"$EncodedPayloadScript`""
        }

        if (($CommandLineOutput.Length -gt $CmdMaxLength) -and (-not $PSBoundParameters['EncodedOutput']))
        {
            $CommandLineOutput = "$($Env:windir)\SysWOW64\WindowsPowerShell\v1.0\powershell.exe $($CommandlineOptions -join ' ') -C `"$NewScript`""
        }
    }
    else
    {
        $CommandLineOutput = "powershell $($CommandlineOptions -join ' ') -C `"$NewScript`""

        if ($PSBoundParameters['EncodedOutput'] -or $CommandLineOutput.Length -le $CmdMaxLength)
        {
            $CommandLineOutput = "powershell $($CommandlineOptions -join ' ') -E `"$EncodedPayloadScript`""
        }

        if (($CommandLineOutput.Length -gt $CmdMaxLength) -and (-not $PSBoundParameters['EncodedOutput']))
        {
            $CommandLineOutput = "powershell $($CommandlineOptions -join ' ') -C `"$NewScript`""
        }
    }

    if ($CommandLineOutput.Length -gt $CmdMaxLength)
    {
            Write-Warning 'This command exceeds the cmd.exe maximum allowed length!'
    }

    Write-Output $CommandLineOutput
}