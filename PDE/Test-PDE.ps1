#requires -Version 5.1
# Modified for PDE 4.3.0-rc1. See README.md.
[CmdletBinding()]
param([string]$ReportPath, [switch]$Interactive, [switch]$Coloring)
$ErrorActionPreference='Stop'
if ($Interactive -and $Coloring) { throw 'Choose one test mode per process.' }
if ($Coloring) {
    . (Join-Path $PSScriptRoot 'PDE.ps1') -NoStart
    $global:PDE_Config = @{ HighlightMode = 'Token'; CharacterHighlightMaxDistance = 2 }
    $global:PDE_State = @{
        CommandNames = (New-PDEStringSet)
        CommandPrefixes = (New-PDEStringSet)
        HistoryCommandNames = (New-PDEStringSet)
        DiscoveryHealthy = $true
    }
    foreach ($command in @('ssh', 'Get-Date', 'Get-ChildItem')) {
        $null = $global:PDE_State.CommandNames.Add($command)
    }
    foreach ($command in @('ssh', 'Get-Date')) {
        $null = $global:PDE_State.HistoryCommandNames.Add($command)
    }
    foreach ($prefix in @('ss', 'Get-Dat', 'Get-')) {
        $null = $global:PDE_State.CommandPrefixes.Add($prefix)
    }

    function Assert-Map {
        param([string]$Label, [int[]]$Actual, [int[]]$Expected)
        $actualText = ($Actual -join ',')
        $expectedText = ($Expected -join ',')
        if ($actualText -cne $expectedText) {
            throw "$Label : expected [$expectedText], got [$actualText]"
        }
        Write-Host "PASS $Label"
    }

    Assert-Map 'token-mode invalid' (Get-PDECommandNameColorMap 'sse') @(2,2,2)
    Assert-Map 'token-mode valid' (Get-PDECommandNameColorMap 'ssh') @(3,3,3)
    Assert-Map 'token-mode line' (Get-PDELineColorMap 'sse') @(2,2,2)

    $global:PDE_Config.HighlightMode = 'Character'
    Assert-Map 'character-mode invalid sse' (Get-PDECommandNameColorMap 'sse') @(3,3,2)
    Assert-Map 'character-mode invalid Get-Datf' (Get-PDECommandNameColorMap 'Get-Datf') @(3,3,3,3,3,3,3,2)
    Assert-Map 'case-insensitive known command' (Get-PDECommandNameColorMap 'SSH') @(3,3,3)
    Assert-Map 'known but not used' (Get-PDECommandNameColorMap 'Get-ChildItem') @(3,3,3,3,3,3,3,3,3,3,3,3,3)
    Assert-Map 'exact prefix is green' (Get-PDECommandNameColorMap 'Get-Dat') @(3,3,3,3,3,3,3)
    Assert-Map 'extra typed character' (Get-PDECommandNameColorMap 'sshh') @(3,3,3,2)
    Assert-Map 'no close candidate' (Get-PDECommandNameColorMap 'zzzzzzzzzz') @(2,2,2,2,2,2,2,2,2,2)
    Assert-Map 'line-map sse' (Get-PDELineColorMap 'sse') @(3,3,2)
    Assert-Map 'line-map Get-Datf' (Get-PDELineColorMap 'Get-Datf') @(3,3,3,3,3,3,3,2)
    Assert-Map 'two commands with offsets' (Get-PDELineColorMap 'sse; Get-Datf') @(3,3,2,0,0,3,3,3,3,3,3,3,2)

    Assert-Map 'transposed letters' (Get-PDECommandNameColorMap 'Get-Dtae') @(3,3,3,3,3,1,1,3)
    Assert-Map 'exact matches take priority over duplicates' (Get-PDECommandNameColorMap 'shh') @(3,2,3)
    Assert-Map 'pipeline and quoted command' (Get-PDELineColorMap "ss | & 'Get-Dtae'") @(3,3,0,0,0,0,0,0,3,3,3,3,3,1,1,3,0)
    # When discovery is not healthy, unknown names are uncertain (orange), not red.
    try {
        $global:PDE_State.DiscoveryHealthy = $false
        Assert-Map 'unhealthy discovery base class' @((Get-PDECommandClass 'sse')) @(1)
        Assert-Map 'unhealthy discovery is not red' (Get-PDECommandNameColorMap 'sse') @(1,1,1)
        Assert-Map 'unhealthy discovery line-map' (Get-PDELineColorMap 'sse') @(1,1,1)
        Assert-Map 'known name remains green during unhealthy discovery' (Get-PDECommandNameColorMap 'ssh') @(3,3,3)
    }
    finally {
        $global:PDE_State.DiscoveryHealthy = $true
    }
    # This line is not reached if any assertion throws (when run as a script).
    Write-Host 'All colouring tests passed.'
    return
}
if ($Interactive) {
    if([Console]::IsInputRedirected -or [Console]::IsOutputRedirected){throw 'An interactive console with a human observer is required.'}
    Import-Module PSReadLine -ErrorAction Stop
    $old=Get-PSReadLineOption
    $oldSave=$old.HistorySaveStyle; $oldHandler=$old.AddToHistoryHandler
    $results=[Collections.Generic.List[object]]::new()
    try {
        # Never save the supplied test lines to personal command history.
        Set-PSReadLineOption -HistorySaveStyle SaveNothing -AddToHistoryHandler {$false}
        . (Join-Path $PSScriptRoot 'PDE.ps1')
        Disable-PDEPromptLearning
        Write-Host 'Guided terminal checks. Entered test text is returned as DATA, never executed.'
        Write-Host 'Live command colours are expected. Check green/orange/red/gray while typing.'
        Write-Host 'Use a fresh process, not your everyday terminal. Ctrl+C cancels.'
        $cases=@(
            @{Name='Rapid typing and cursor edits';Text='Get-Date';Instruction='Type Get-Datx quickly, use Backspace, type e. Move Left/Right/Home/End, then Enter.'},
            @{Name='Delete and pipeline editing';Text='Get-Date | FakeCommand';Instruction='Type Get-Date | FakeXCommand. Move to X, Delete it, move End, then Enter.'},
            @{Name='Paste';Text='Get-Process -Name explorer';Instruction='Paste the expected line exactly, then Enter. Check no duplication.'},
            @{Name='Wrapping and resize';Text=('Write-Output '+('abcdefghij'*30));Instruction='Paste the expected line. Resize narrower and wider, move the cursor across wraps, then Enter.'},
            @{Name='Unicode';Text=('Write-Output '+[char]0x03bb);Instruction='Paste the expected line. Move the cursor and confirm characters remain aligned, then Enter.'},
            @{Name='Multiline';Text="Get-Date`nGet-Process";Instruction='Type Get-Date, Shift+Enter, Get-Process, Enter. Confirm the continuation prompt and cursor.'},
            @{Name='Tab completion';Text='Get-Process';Instruction='Type Get-Pro then use Tab/Shift+Tab to reach Get-Process, then Enter.'}
        )
        foreach($case in $cases){
            Write-Host "`n$($case.Name): $($case.Instruction)"
            Write-Host ('Expected: '+$case.Text)
            Write-Host 'PDE test> ' -NoNewline
            $actual=PSConsoleHostReadLine
            $matches=($actual.Replace("`r`n","`n") -ceq $case.Text)
            $answer=Read-Host 'Did the display stay correct, without flicker, overlap, lost input or cursor jumps? [y/n/s]'
            $status=if($answer -eq 's'){'SKIP'}elseif($matches -and $answer -eq 'y'){'PASS'}else{'FAIL'}
            $results.Add([pscustomobject]@{Name=$case.Name;Status=$status;BufferMatches=$matches;Observer=$answer})
        }
        $before=Get-PSReadLineKeyHandler | ConvertTo-Json -Depth 4 -Compress
        for($i=0;$i -lt 20;$i++){$null=Enable-PDELiveHighlight -Quiet;Disable-PDELiveHighlight}
        $after=Get-PSReadLineKeyHandler | ConvertTo-Json -Depth 4 -Compress
        $results.Add([pscustomobject]@{Name='Repeated toggles preserve bindings';Status=$(if($before -ceq $after){'PASS'}else{'FAIL'});BufferMatches=$null;Observer='automated'})
        Show-PDEHighlight 'Get-Dtae | FakeCommand'
        $answer=Read-Host 'Preview only: swapped t and a orange, other Get-Dtae letters green, unknown command red? [y/n/s]'
        $results.Add([pscustomobject]@{Name='Standalone preview';Status=$(if($answer -eq 'y'){'PASS'}elseif($answer -eq 'n'){'FAIL'}else{'SKIP'});BufferMatches=$null;Observer=$answer})
        $answer=Read-Host 'Did live command-status colours update correctly while editing? [y/n/s]'
        $results.Add([pscustomobject]@{Name='Live four-colour editing';Status=$(if($answer -eq 'y'){'PASS'}elseif($answer -eq 'n'){'FAIL'}else{'SKIP'});BufferMatches=$null;Observer=$answer})
        $results.Add([pscustomobject]@{Name='History, custom keys, jobs and full profile interactions';Status='SKIP';BufferMatches=$null;Observer='Follow isolated-console procedure in README.md'})
        $results | Format-Table -AutoSize | Out-Host
        if($ReportPath){[IO.File]::WriteAllText($ReportPath,($results | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
    } finally {
        if(Get-Command Stop-PDE -ErrorAction SilentlyContinue){Stop-PDE}
        Set-PSReadLineOption -HistorySaveStyle $oldSave -AddToHistoryHandler $oldHandler
    }
    return
}
try {
    . (Join-Path $PSScriptRoot 'PDE.ps1') -NoStart
    Start-PDE -NonInteractive
    $result=Invoke-PDETestSuite
    if($ReportPath){[IO.File]::WriteAllText($ReportPath,($result | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
    $result.Checks | Format-Table Status,Name,Detail -Wrap | Out-Host
    Write-Host ("PASS: {0}; FAIL: {1}; SKIP: {2}. Production acceptance remains incomplete." -f $result.PassedCount,$result.FailedCount,$result.SkippedCount)
    if(-not $result.Passed){exit 1}
    exit 0
}catch{Write-Host $_ -ForegroundColor Red;exit 1}
