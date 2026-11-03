# PowerShell Developer Environment V2 - Profile Loader
$PdeProfilePath = Join-Path $HOME 'PDE-V2.ps1'

if (Test-Path -LiteralPath $PdeProfilePath -PathType Leaf) {
    . $PdeProfilePath
} else {
    Write-Warning "PDE V2 profile not found: $PdeProfilePath"
}

function global:ssh {
    if (@($args) -contains 'arthu@black.local') {

        $secretFile = Join-Path $HOME '.ssh\black_knock.dpapi'
        $secure = Get-Content $secretFile | ConvertTo-SecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

        try {
            $sequence = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

        $ports = @($sequence.Split(',') | ForEach-Object { [int]$_.Trim() })

        if ($ports.Count -ne 4) {
            throw 'Expected four knock ports.'
        }

        $address = [System.Net.Dns]::GetHostAddresses('black.local') |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
            Select-Object -First 1

        if (-not $address) {
            throw 'Cannot resolve black.local to an IPv4 address.'
        }

        Write-Host "Knocking on black.local..."

        foreach ($port in $ports) {
            $client = New-Object System.Net.Sockets.TcpClient

            try {
                $attempt = $client.BeginConnect($address, $port, $null, $null)
                [void]$attempt.AsyncWaitHandle.WaitOne(500)
                $attempt.AsyncWaitHandle.Close()
            }
            finally {
                $client.Close()
            }

            Start-Sleep -Milliseconds 150
        }

        Write-Host "Knock sequence sent. Connecting via SSH..."
    }

    & ssh.exe @args
}


function global:ssh {
    if (@($args) -contains 'arthu@black.local') {

        $secretFile = Join-Path $HOME '.ssh\black_knock.dpapi'
        $secure = Get-Content $secretFile | ConvertTo-SecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

        try {
            $sequence = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

        $ports = @($sequence.Split(',') | ForEach-Object { [int]$_.Trim() })

        if ($ports.Count -ne 4) {
            throw 'Expected four knock ports.'
        }

        $address = [System.Net.Dns]::GetHostAddresses('black.local') |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
            Select-Object -First 1

        if (-not $address) {
            throw 'Cannot resolve black.local to an IPv4 address.'
        }

        Write-Host "Knocking on black.local..."

        foreach ($port in $ports) {
            $client = New-Object System.Net.Sockets.TcpClient

            try {
                $attempt = $client.BeginConnect($address, $port, $null, $null)
                [void]$attempt.AsyncWaitHandle.WaitOne(500)
                $attempt.AsyncWaitHandle.Close()
            }
            finally {
                $client.Close()
            }

            Start-Sleep -Milliseconds 150
        }

        Write-Host "Knock sequence sent. Connecting via SSH..."
    }

    & ssh.exe @args
}

