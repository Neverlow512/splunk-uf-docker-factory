# gather_host_info.ps1 - JSON Output Version
# Run this script on the HOST machine (where Docker runs) as Administrator.
# It gathers diagnostic information relevant to the Splunk UF container setup.
# Output: host_report.json in the script's directory.

<#
.SYNOPSIS
    Gathers diagnostic information from the Docker host machine related to network
    configuration, Docker status, firewall rules, and connectivity to a specified
    Splunk indexer VM/port. Outputs results to host_report.json.

.DESCRIPTION
    This script performs several checks crucial for troubleshooting Splunk Universal
    Forwarder Docker containers trying to connect to a Splunk indexer:
    - Basic system information (hostname, OS, timestamp).
    - Network IP addresses and routing table.
    - Docker information (version, networks, containers, specific container inspect).
    - Windows Firewall rules potentially allowing traffic TO the Splunk indexer port (outbound).
      Note: This script primarily checks INBOUND rules relevant if the *host* were receiving,
      but outbound is usually less restrictive by default. For UF sending data, the VM's
      INBOUND firewall is more critical.
    - Connectivity tests (TCP port connection, ICMP Ping) from the host TO the Splunk VM.

.PARAMETER VmIpAddress
    The IP address or hostname of the target Splunk Enterprise indexer VM.
    Defaults to '192.168.1.100' if not specified.

.PARAMETER SplunkPort
    The TCP port the Splunk Enterprise indexer is expected to be listening on.
    Defaults to 9997 if not specified.

.PARAMETER DockerContainerName
    The exact name of the Splunk UF Docker container to inspect.
    Defaults to 'splunk-uf' if not specified (NOTE: setup.py now generates dynamic names like 'project-uf').
    You may need to provide the specific name like: .\gather_host_info.ps1 -DockerContainerName myproject-uf

.EXAMPLE
    .\gather_host_info.ps1 -VmIpAddress 10.0.0.50 -SplunkPort 9997 -DockerContainerName webapp_logs-uf
    Gathers diagnostics targeting Splunk VM at 10.0.0.50:9997 and inspects the container 'webapp_logs-uf'.

.EXAMPLE
    .\gather_host_info.ps1
    Gathers diagnostics using default values (check Parameter defaults). Provide the actual container name if it differs from 'splunk-uf'.

.OUTPUTS
    host_report.json - A JSON file containing the collected diagnostic information.

.NOTES
    Requires running PowerShell as Administrator for full access (especially Docker inspect, Get-Net* cmdlets).
    Ensure the 'NetSecurity' module (for Get-NetFirewall*Filter) is available on the host OS.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$VmIpAddress = '192.168.1.100', # Default Placeholder - User should ideally provide

    [Parameter(Mandatory=$false)]
    [int]$SplunkPort = 9997,

    [Parameter(Mandatory=$false)]
    [string]$DockerContainerName = 'splunk-uf' # Default base, remind user setup.py creates dynamic names
)

$ErrorActionPreference = 'SilentlyContinue' # Allow script to continue past non-critical errors
$reportJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "host_report.json"
$reportData = [ordered]@{}

Write-Host "--- Splunk UF Docker - Host Diagnostics ---"
Write-Host "Target Splunk VM: $VmIpAddress : $SplunkPort"
Write-Host "Target Container: $DockerContainerName (Note: setup.py creates names like 'projectname-uf')"
Write-Host "Output File: $reportJsonPath"
Write-Host "Running as Administrator is recommended for full results."
Write-Host "-" * 40

# --- Basic Info ---
Write-Host "[1/5] Gathering Basic System Info..."
$reportData.BasicInfo = @{
    Timestamp       = Get-Date -Format 'o' # ISO 8601 format
    ScriptName      = $MyInvocation.MyCommand.Name
    HostComputerName= $env:COMPUTERNAME
    HostOSVersion   = (Get-CimInstance Win32_OperatingSystem).Caption
    HostUserName    = try { ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) } catch { "N/A (Permission?)" }
    PowerShellVersion = $PSVersionTable.PSVersion
}

# --- Network Config ---
Write-Host "[2/5] Gathering Network Configuration..."
$networkInfo = @{}
try {
    $networkInfo.IPAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.254\.' } |
                               Select-Object InterfaceAlias, IPAddress, PrefixLength
    $networkInfo.Routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
                          Select-Object InterfaceAlias, DestinationPrefix, NextHop, RouteMetric
} catch {
    $networkInfo.Error = "Failed to get network configuration: $($_.Exception.Message)"
    Write-Warning "Could not gather full network info: $($_.Exception.Message)"
}
$reportData.Network = $networkInfo

# --- Docker Info ---
Write-Host "[3/5] Gathering Docker Information..."
$dockerInfo = @{}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $dockerInfo.Error = "'docker' command not found. Is Docker installed and in PATH?"
    Write-Error $dockerInfo.Error
} else {
    try {
        Write-Host "  - Docker Version..."
        $dockerInfo.DockerVersion = (docker version --format '{{json .}}' | ConvertFrom-Json -ErrorAction Stop)

        Write-Host "  - Docker Networks..."
        $dockerInfo.Networks = (docker network ls --format '{{json .}}' --no-trunc | ConvertFrom-Json -ErrorAction Stop)

        Write-Host "  - Docker Containers (All)..."
        $dockerInfo.Containers = (docker ps -a --format '{{json .}}' --no-trunc | ConvertFrom-Json -ErrorAction Stop)

        $inspectResult = $null
        Write-Host "  - Inspecting target container '$DockerContainerName'..."
        try {
            $inspectOutput = & docker inspect $DockerContainerName 2>&1 # Capture stderr too
            if ($LASTEXITCODE -eq 0) {
                 $inspectResult = $inspectOutput | ConvertFrom-Json -ErrorAction Stop
                 Write-Host "    Container found and inspected."
            } else {
                if ($inspectOutput -match 'No such object:') {
                    $inspectResult = @{ Status = "Container '$DockerContainerName' not found." }
                    Write-Warning "Target container '$DockerContainerName' not found."
                } else {
                     $inspectResult = @{ Error = "Failed to inspect container '$DockerContainerName'. Exit Code: $LASTEXITCODE Output: $inspectOutput" }
                     Write-Warning "Error inspecting container '$DockerContainerName'."
                }
            }
        } catch {
             $inspectResult = @{ Error = "Exception during 'docker inspect': $($_.Exception.Message)"}
             Write-Warning "Exception during 'docker inspect': $($_.Exception.Message)"
        }
         $dockerInfo.InspectTargetContainer = $inspectResult

    } catch {
        $dockerInfo.Error = "Failed to get Docker info. Is Docker daemon running? Error: $($_.Exception.Message)"
        Write-Warning "Could not gather full Docker info: $($_.Exception.Message)"
    }
}
$reportData.Docker = $dockerInfo

# --- Firewall Rules ---
# Note: Host's OUTBOUND rules are usually less restrictive. The VM's INBOUND rule is key.
# This check is more for completeness or complex network scenarios.
Write-Host "[4/5] Gathering Host Firewall Rules (Outbound related to Port $SplunkPort)..."
$firewallInfo = @{ Note = "Checking HOST outbound rules (less common issue). VM INBOUND rules are more critical for UF." }
try {
    # Check if relevant cmdlets exist
    if ((Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) -and `
        (Get-Command Get-NetFirewallPortFilter -ErrorAction SilentlyContinue) -and `
        (Get-Command Get-NetFirewallProtocolFilter -ErrorAction SilentlyContinue))
    {
        # Look for rules explicitly BLOCKING outbound TCP traffic to the specific port/IP
        $baseOutboundRules = Get-NetFirewallRule -Direction Outbound -ErrorAction Stop | Where-Object { $_.Enabled -eq $true -and $_.Action -eq 'Block' }
        $blockingRules = $baseOutboundRules | Where-Object {
            $portFilter = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $protoFilter = $_ | Get-NetFirewallProtocolFilter -ErrorAction SilentlyContinue
            $remoteAddrFilter = $_ | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

            # Check if rule blocks TCP AND (blocks the specific port OR Any port) AND (blocks the specific IP OR Any IP)
            ($protoFilter -ne $null -and ($protoFilter.Protocol -eq 'TCP' -or $protoFilter.Protocol -eq 'Any')) -and `
            ($portFilter -ne $null -and ($portFilter.RemotePort -contains $SplunkPort -or $portFilter.RemotePort -eq 'Any')) -and `
            ($remoteAddrFilter -ne $null -and ($remoteAddrFilter.RemoteAddress -contains $VmIpAddress -or $remoteAddrFilter.RemoteAddress -eq 'Any'))
        }
        $firewallInfo.OutboundTcpBlockRulesForTarget = $blockingRules | Select-Object Name, DisplayName, Enabled, Profile, Direction, Action, @{Name='RemotePort';Expression={($_.RemotePort | Out-String).Trim()}}, Protocol, @{Name='RemoteAddress';Expression={($_.RemoteAddress | Out-String).Trim()}}
        Write-Host "  Found $($firewallInfo.OutboundTcpBlockRulesForTarget.Count) potentially relevant OUTBOUND BLOCK rule(s)."
    } else {
        $firewallInfo.Warning = "Cannot perform detailed firewall check. Get-NetFirewall* cmdlets not found or 'NetSecurity' module unavailable."
        Write-Warning $firewallInfo.Warning
    }
} catch {
    $firewallInfo.Error = "Failed to get firewall rules: $($_.Exception.Message)"
    Write-Warning "Error querying firewall rules: $($_.Exception.Message)"
}
$reportData.Firewall = $firewallInfo

# --- Connectivity Checks ---
Write-Host "[5/5] Performing Connectivity Checks from Host to $VmIpAddress`:$SplunkPort..."
$connectivityInfo = @{ VmIpTarget = $VmIpAddress; PortTarget = $SplunkPort }
try {
    Write-Host "  - Testing TCP connection..."
    # Use timeout to prevent long hangs if VM is unreachable
    $tcpTestResult = Test-NetConnection -ComputerName $VmIpAddress -Port $SplunkPort -InformationLevel Detailed -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($tcpTestResult -ne $null) {
        $connectivityInfo.TcpTest = $tcpTestResult | Select-Object ComputerName, RemotePort, InterfaceAlias, SourceAddress, TcpTestSucceeded, PingSucceeded, PingReplyDetails*, NetRoute*
        Write-Host "    TCP Test Succeeded: $($tcpTestResult.TcpTestSucceeded)"
        if (-not $tcpTestResult.TcpTestSucceeded) { Write-Warning "TCP connection test FAILED." }
    } else {
        $connectivityInfo.TcpTest = @{ Result = "Failed"; Error = "Test-NetConnection returned no result (possible timeout, DNS failure, or host unreachable)." }
        Write-Warning "TCP connection test FAILED (No result returned)."
    }
} catch {
    $connectivityInfo.Error = "Exception during connectivity tests: $($_.Exception.Message)"
    Write-Warning "Exception during connectivity tests: $($_.Exception.Message)"
}
$reportData.Connectivity = $connectivityInfo

# --- Write JSON Report ---
Write-Host "-" * 40
Write-Host "Attempting to write JSON report..."
try {
    $reportData | ConvertTo-Json -Depth 6 | Out-File -FilePath $reportJsonPath -Encoding UTF8 -Force -ErrorAction Stop
    Write-Host "Host diagnostic report written successfully to '$reportJsonPath'"
} catch {
    Write-Error "FATAL: Failed to write JSON report to '$reportJsonPath' : $($_.Exception.Message)"
}
Write-Host "--- Diagnostics Complete ---"