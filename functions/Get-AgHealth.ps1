function Get-AgHealth {
    <#
    .SYNOPSIS
        Returns Availability Group replica and database synchronization health.

    .DESCRIPTION
        Emits two output types from a single call:

        DbaToolbox.AgReplicaHealth — one row per availability replica, from
        Get-DbaAgReplica: role, connection state, and rollup synchronization state.

        DbaToolbox.AgDatabaseHealth — one row per database replica state, from
        Get-DbaAgDatabaseReplicaState: synchronization state, suspension, send/redo
        queue sizes (KB), and estimated data loss (seconds).

        Instances that host no availability groups return nothing.

        Callers can filter by PSTypeName to process each type separately:
            Get-AgHealth -SqlInstance 'SQL01' | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.AgDatabaseHealth' }

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER AvailabilityGroup
        Limit results to one or more specific availability group names.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-AgHealth -SqlInstance 'SQL01'

        Returns replica and database health for all AGs on SQL01.

    .EXAMPLE
        Get-AgHealth -SqlInstance 'SQL01' | Where-Object { $_.IsSuspended -or $_.SynchronizationState -ne 'Synchronized' }

        Returns only database replicas that need attention.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [string[]] $AvailabilityGroup,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-AgHealth: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking availability group health on $($server.DomainInstanceName)"

            # --- Replica health ---
            $splatReplica = @{
                SqlInstance = $server
            }
            if ($AvailabilityGroup) { $splatReplica['AvailabilityGroup'] = $AvailabilityGroup }

            try {
                $replicas = Get-DbaAgReplica @splatReplica
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-AgHealth: Get-DbaAgReplica failed on $instance : $_"
                continue
            }

            foreach ($replica in $replicas) {
                [PSCustomObject]@{
                    PSTypeName           = 'DbaToolbox.AgReplicaHealth'
                    ComputerName         = $server.ComputerName
                    InstanceName         = $server.InstanceName
                    SqlInstance          = $server.DomainInstanceName
                    AvailabilityGroup    = $replica.AvailabilityGroup
                    ReplicaName          = $replica.Name
                    Role                 = $replica.Role
                    ConnectionState      = $replica.ConnectionState
                    SynchronizationState = $replica.RollupSynchronizationState
                    AvailabilityMode     = $replica.AvailabilityMode
                    FailoverMode         = $replica.FailoverMode
                }
            }

            # --- Database replica health ---
            $splatDbState = @{
                SqlInstance = $server
            }
            if ($AvailabilityGroup) { $splatDbState['AvailabilityGroup'] = $AvailabilityGroup }

            try {
                $dbStates = Get-DbaAgDatabaseReplicaState @splatDbState
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-AgHealth: Get-DbaAgDatabaseReplicaState failed on $instance : $_"
                continue
            }

            foreach ($dbState in $dbStates) {
                [PSCustomObject]@{
                    PSTypeName           = 'DbaToolbox.AgDatabaseHealth'
                    ComputerName         = $server.ComputerName
                    InstanceName         = $server.InstanceName
                    SqlInstance          = $server.DomainInstanceName
                    AvailabilityGroup    = $dbState.AvailabilityGroup
                    ReplicaName          = $dbState.ReplicaServerName
                    ReplicaRole          = $dbState.ReplicaRole
                    DatabaseName         = $dbState.AvailabilityDatabaseName
                    SynchronizationState = $dbState.SynchronizationState
                    IsSuspended          = $dbState.IsSuspended
                    SuspendReason        = $dbState.SuspendReason
                    LogSendQueueKB       = $dbState.LogSendQueueSize
                    RedoQueueKB          = $dbState.RedoQueueSize
                    EstimatedDataLossSec = $dbState.EstimatedDataLoss
                    LastCommitTime       = $dbState.LastCommitTime
                }
            }
        }
    }

    end {}
}
