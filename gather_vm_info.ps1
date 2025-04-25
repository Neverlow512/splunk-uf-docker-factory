# gather_vm_info.ps1 - JSON Output Version
# Run this script on the Splunk Enterprise VM as Administrator.
# It gathers diagnostics about Splunk listening status, relevant config, and firewall rules.
# Output: vm_report.json in the script's directory.

<#
.SYNOPSIS
    Gathers diagnostic information from the Splunk Enterprise VM related to Splunk's
    listening status, TCP input configuration, network settings, and firewall rules
    relevant to receiving data from forwarders. Outputs results to vm_report.json.

.DESCRIPTION
    This script checks key aspects on the Splunk indexer VM:
    - Basic system information.
    - Network IP addresses and routing table.
    - Splunk process listening status on the specified port using Get-NetTCPConnection.
    - Splunk TCP input configuration using `splunk btool inputs list`.
    - Windows Firewall rules allowing INBOUND traffic on the specified port.

.PARAMETER SplunkPort
    The TCP port Splunk Enterprise should be listening on for incoming forwarder data.
    Defaults to 9997 if not specified.

.PARAMETER SplunkHomePath
    The full path to the Splunk installation directory (e.g., "C:\Program Files\Splunk").
    Defaults to "C:\Program Files\Splunk". Adjust if your installation differs.

.EXAMPLE
    .\gather_vm_info.ps1 -SplunkPort 9997 -SplunkHomePath "D:\Splunk"
    Gathers diagnostics checking port 9997 and Splunk installed in D:\Splunk.

.EXAMPLE
    .\gather_vm_info.ps1
    Gathers diagnostics using default values (Port 9997, "C:\Program Files\Splunk").

.OUTPUTS
    vm_report.json - A JSON file containing the collected diagnostic information.

.NOTES
    Requires running PowerShell as Administrator for full access (especially Get-Net*, btool, firewall).
    Ensure the 'NetSecurity' module (for Get-NetFirewall*Filter) is available on the VM OS.
#>
param(
    [Parameter(Mandatory=$false)]
    [int]$SplunkPort = 9997,

    [Parameter(Mandatory=$false)]
    [string]$SplunkHomePath = "C:\Program Files\Splunk"
)

$ErrorActionPreference = 'SilentlyContinue' # Allow script to continue past non-critical errors
$reportJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "vm_report.json"
$reportData = [ordered]@{}

Write-Host "--- Splunk UF Docker - Splunk VM Diagnostics ---"
Write-Host "Checking Port: $SplunkPort"
Write-Host "Splunk Home: '$SplunkHomePath'"
Write-Host "Output File: $reportJsonPath"
Write-Host "Running as Administrator is recommended for full results."
Write-Host "-" * 40

# --- Basic Info ---
Write-Host "[1/5] Gathering Basic System Info..."
$reportData.BasicInfo = @{
    Timestamp       = Get-Date -Format 'o'
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

# --- Splunk Listener & Config ---
Write-Host "[3/5] Gathering Splunk Listener & Config Info..."
$splunkInfo = @{ SplunkHome = $SplunkHomePath; TargetPort = $SplunkPort }
if (-not (Test-Path -Path $SplunkHomePath -PathType Container)) {
    $splunkInfo.Error = "Splunk Home directory not found or is not a directory at '$SplunkHomePath'"
    Write-Error $splunkInfo.Error
} else {
    $splunkInfo.SplunkHomeExists = $true
    $listeningProcessInfo = $null
    # Check if Splunk is listening on the port
    try {
        Write-Host "  - Checking network connections for port $SplunkPort..."
        $netstatEntries = Get-NetTCPConnection -LocalPort $SplunkPort -State Listen -ErrorAction Stop # More reliable than parsing netstat
        if ($netstatEntries) {
            $splunkInfo.IsListeningOnPort = $true
            $pids = $netstatEntries.OwningProcess | Select-Object -Unique
            Write-Host "    Found $($netstatEntries.Count) listening endpoint(s) on port $SplunkPort, Owning Process IDs: $($pids -join ', ')"
            if ($pids) {
                # Get process details for the PIDs found
                $listeningProcessInfo = Get-Process -Id $pids -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path
                $splunkInfo.ListeningProcesses = $listeningProcessInfo
                # Check if splunkd.exe is among them
                if ($listeningProcessInfo.ProcessName -contains 'splunkd') {
                     Write-Host "    Confirmed 'splunkd.exe' process is listening."
                } else {
                     Write-Warning "    Port $SplunkPort is in LISTEN state, but 'splunkd.exe' was NOT identified as the owner. Found: $($listeningProcessInfo.ProcessName -join ', ')"
                }
            } else {
                 Write-Warning "    Port $SplunkPort is listening, but could not determine Owning Process ID via Get-NetTCPConnection."
                 $splunkInfo.ListeningProcesses = "(Could not determine Process ID)"
            }
        } else {
             Write-Host "    Port $SplunkPort NOT found in LISTEN state via Get-NetTCPConnection."
            $splunkInfo.IsListeningOnPort = $false
        }
    } catch {
        $splunkInfo.ListeningCheckError = "Error checking Get-NetTCPConnection: $($_.Exception.Message)"
        Write-Warning "Error checking network connections: $($_.Exception.Message)"
        $splunkInfo.IsListeningOnPort = $false
    }

    # Get Splunk input config via btool
    $btoolPath = Join-Path -Path $SplunkHomePath -ChildPath "bin\splunk.exe"
    if (-not (Test-Path -Path $btoolPath -PathType Leaf)) {
        $splunkInfo.BtoolError = "splunk.exe not found at '$btoolPath'"
        Write-Warning $splunkInfo.BtoolError
    } else {
        Write-Host "  - Checking Splunk TCP input config via btool..."
        try {
            # Use full path, quote if necessary, capture output
            $btoolCmd = "& `"$btoolPath`" btool inputs list --debug"
            $btoolOutput = Invoke-Expression $btoolCmd 2>&1 # Capture potential errors too
            # Filter for relevant TCP input stanzas and disabled status
            $relevantLines = $btoolOutput | Select-String -Pattern '\[(?:splunktcp|tcp)(?::|://).*?\]|disabled\s*=\s*(true|1|false|0)' -Context 0, 6 # Show stanza + 6 lines after for context
            $splunkInfo.BtoolTcpInputConfigRaw = $relevantLines -join "`n"
             if (-not $relevantLines) {
                 $splunkInfo.BtoolTcpInputConfigStatus = "(No relevant [splunktcp://...] or [tcp://...] stanzas found in btool output)"
                 Write-Warning "No [splunktcp://...] or [tcp://...] stanzas found by btool."
             } else {
                 # Simple check for explicit disabled=true/1 within relevant context
                 if ($splunkInfo.BtoolTcpInputConfigRaw -match 'disabled\s*=\s*(true|1)') {
                     $splunkInfo.BtoolTcpInputConfigStatus = "Warning: Found relevant TCP input stanza(s), but at least one appears explicitly disabled ('disabled = true' or 'disabled = 1'). Check raw output."
                     Write-Warning "btool output suggests a relevant TCP input might be disabled."
                 } else {
                     $splunkInfo.BtoolTcpInputConfigStatus = "Found relevant TCP input stanza(s). Check raw output for specific port and settings. Ensure 'disabled = false' or is absent."
                     Write-Host "    Found relevant stanza(s). Verify port $SplunkPort is configured and enabled."
                 }
             }
        } catch {
            $splunkInfo.BtoolError = "Error running btool: $($_.Exception.Message)"
            Write-Warning "Error running btool: $($_.Exception.Message)"
            if ($_.Exception.ErrorRecord -and $_.Exception.ErrorRecord.TargetObject -is [System.Management.Automation.ErrorRecord]) {
                $stderr = $_.Exception.ErrorRecord.TargetObject.Stderr
                if ($stderr) { $splunkInfo.BtoolStderr = $stderr -join "`n" }
            }
        }
    }
}
$reportData.Splunk = $splunkInfo

# --- Firewall Rules ---
Write-Host "[4/5] Gathering VM Firewall Rules (Inbound for Port $SplunkPort)..."
$firewallInfo = @{}
try {
    if ((Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) -and `
        (Get-Command Get-NetFirewallPortFilter -ErrorAction SilentlyContinue) -and `
        (Get-Command Get-NetFirewallProtocolFilter -ErrorAction SilentlyContinue))
    {
        # Look for rules explicitly ALLOWING inbound TCP traffic on the specific port
        $baseInboundRules = Get-NetFirewallRule -Direction Inbound -ErrorAction Stop | Where-Object { $_.Enabled -eq $true -and $_.Action -eq 'Allow' }
        $allowingRules = $baseInboundRules | Where-Object {
            $portFilter = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $protoFilter = $_ | Get-NetFirewallProtocolFilter -ErrorAction SilentlyContinue

            ($portFilter -ne $null -and ($portFilter.LocalPort -contains $SplunkPort -or $portFilter.LocalPort -eq 'Any')) -and `
            ($protoFilter -ne $null -and ($protoFilter.Protocol -eq 'TCP' -or $protoFilter.Protocol -eq 'Any'))
        }
        $firewallInfo.InboundTcpAllowRulesForPort = $allowingRules | Select-Object Name, DisplayName, Enabled, Profile, Direction, Action, @{Name='LocalPort';Expression={($_.LocalPort | Out-String).Trim()}}, Protocol
        Write-Host "  Found $($firewallInfo.InboundTcpAllowRulesForPort.Count) potentially relevant INBOUND ALLOW rule(s)."
        if ($firewallInfo.InboundTcpAllowRulesForPort.Count -eq 0) {
             Write-Warning "No active firewall rule found explicitly allowing inbound TCP traffic on port $SplunkPort. Data forwarding will likely fail."
        }
    } else {
         $firewallInfo.Warning = "Cannot perform detailed firewall check. Get-NetFirewall* cmdlets not found or 'NetSecurity' module unavailable."
         Write-Warning $firewallInfo.Warning
    }
} catch {
    $firewallInfo.Error = "Failed to get firewall rules: $($_.Exception.Message)"
    Write-Warning "Error querying firewall rules: $($_.Exception.Message)"
}
$reportData.Firewall = $firewallInfo

# --- Write JSON Report ---
Write-Host "-" * 40
Write-Host "[5/5] Attempting to write JSON report..."
try {
    $reportData | ConvertTo-Json -Depth 6 | Out-File -FilePath $reportJsonPath -Encoding UTF8 -Force -ErrorAction Stop
    Write-Host "VM diagnostic report written successfully to '$reportJsonPath'"
} catch {
    Write-Error "FATAL: Failed to write JSON report to '$reportJsonPath' : $($_.Exception.Message)"
}
Write-Host "--- Diagnostics Complete ---"