function Get-ReplicationStatus {
    <#
    .SYNOPSIS
        Returns replication publications and subscriptions for one or more SQL Server
        instances.

    .DESCRIPTION
        Emits two output types from a single call:

        DbaToolbox.ReplPublication — one row per publication, from Get-DbaReplPublication:
        publication database, name, type, and article/subscription counts.

        DbaToolbox.ReplSubscription — one row per subscription, from
        Get-DbaReplSubscription: publication, subscriber, and subscription type.

        This function only reads replication metadata. For active latency measurement,
        use Test-DbaReplLatency — deliberately not called here because it writes tracer
        tokens to the publication database.

        Instances with no replication configured return nothing.

    .PARAMETER SqlInstance
        One or more SQL Server instances to query. Accepts strings, DbaInstanceParameter
        objects, or Server SMO objects. Supports pipeline input.

    .PARAMETER SqlCredential
        Login to use instead of Windows Authentication.

    .PARAMETER EnableException
        By default, when something goes wrong the function writes a warning and continues.
        With -EnableException, errors become terminating exceptions instead.

    .EXAMPLE
        Get-ReplicationStatus -SqlInstance 'SQL01'

        Returns all publications and subscriptions on SQL01.

    .EXAMPLE
        Get-ReplicationStatus -SqlInstance 'SQL01' | Where-Object { $_.PSObject.TypeNames[0] -eq 'DbaToolbox.ReplPublication' }

        Returns only publication rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter[]] $SqlInstance,

        [PSCredential] $SqlCredential,

        [switch] $EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-ReplicationStatus: Failed to connect to $instance : $_"
                continue
            }

            Write-Verbose "Checking replication status on $($server.DomainInstanceName)"

            # --- Publications ---
            try {
                $publications = Get-DbaReplPublication -SqlInstance $server
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-ReplicationStatus: Get-DbaReplPublication failed on $instance : $_"
                continue
            }

            foreach ($publication in $publications) {
                [PSCustomObject]@{
                    PSTypeName        = 'DbaToolbox.ReplPublication'
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.InstanceName
                    SqlInstance       = $server.DomainInstanceName
                    DatabaseName      = $publication.DatabaseName
                    PublicationName   = $publication.Name
                    Type              = $publication.Type
                    ArticleCount      = @($publication.Articles).Count
                    SubscriptionCount = @($publication.Subscriptions).Count
                }
            }

            # --- Subscriptions ---
            try {
                $subscriptions = Get-DbaReplSubscription -SqlInstance $server
            } catch {
                if ($EnableException) { throw }
                Write-Warning "Get-ReplicationStatus: Get-DbaReplSubscription failed on $instance : $_"
                continue
            }

            foreach ($subscription in $subscriptions) {
                [PSCustomObject]@{
                    PSTypeName       = 'DbaToolbox.ReplSubscription'
                    ComputerName     = $server.ComputerName
                    InstanceName     = $server.InstanceName
                    SqlInstance      = $server.DomainInstanceName
                    DatabaseName     = $subscription.DatabaseName
                    PublicationName  = $subscription.PublicationName
                    SubscriberName   = $subscription.SubscriberName
                    SubscriptionDb   = $subscription.SubscriptionDBName
                    SubscriptionType = $subscription.SubscriptionType
                }
            }
        }
    }

    end {}
}
