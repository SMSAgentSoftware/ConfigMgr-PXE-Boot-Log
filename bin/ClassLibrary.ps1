class SQLQuery
{

    # Properties
    [string]$SQLServer
    [string]$Database
    [string]$Query
    [string]$QueryFile
    [string]$Path
    [int]$ConnectionTimeout = 5
    [int]$CommandTimeout = 600
    # Connection string keywords: https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.connectionstring(v=vs.110).aspx
    [string]$ConnectionString
    [object]$SQLConnection
    [object]$SQLCommand
    hidden $SQLReader
    [System.Data.DataTable]$Result
    [System.Data.DataTable]$Tables
    [System.Data.DataTable]$Views
    [bool]$DisplayResults = $True
    
     # Constructor -empty object
    SQLQuery ()
    { 
        Return
    }
    
    # Constructor - sql server and database
    SQLQuery ([String]$SQLServer,[String]$Database)
    { 
        $This.SQLServer = $SQLServer
        $This.Database = $Database
    }

    # Constructor - sql server, database and query
    SQLQuery ([String]$SQLServer,[String]$Database,[string]$Query)
    { 
        $This.SQLServer = $SQLServer
        $This.Database = $Database
        $This.Query = $Query
    }

    # Method
    LoadQueryFromFile([String]$Path)
    {
       If (Test-Path $Path)
       {
        If ([IO.Path]::GetExtension($Path) -ne ".sql")
        {
            throw [System.IO.FileFormatException] "'$Path' does not have an '.sql' extension'"
        }
        Else
        {
            Try
            {
                [String]$This.Query = Get-Content -Path $Path -Raw -ErrorAction Stop
                [String]$This.QueryFile = $Path
            }
            Catch
            {
                $_
            }
        }

       } 
       Else
       {
         throw [System.IO.FileNotFoundException] "'$Path' not found"
       }
    }

    # Method
    [Object] Execute()
    {
        If ($This.SQLConnection)
        {
            $This.SQLConnection.Dispose()
        }

        If ($This.ConnectionString)
        {

        }
        Else
        {
            $This.ConnectionString = "Server=$($This.SQLServer);Database=$($This.Database);Integrated Security=SSPI;Connection Timeout=$($This.ConnectionTimeout)"
        }

        $This.SQLConnection = [System.Data.SqlClient.SqlConnection]::new()
        $This.SQLConnection.ConnectionString = $This.ConnectionString

        Try
        {
            $This.SQLConnection.Open()
        }
        Catch
        {
            return $(Write-host $_ -ForegroundColor Red)    
        }

        Try
        {
            $This.SQLCommand = $This.SQLConnection.CreateCommand()
            $This.SQLCommand.CommandText = $This.Query
            $This.SQLCommand.CommandTimeout = $This.CommandTimeout
            $This.SQLReader = $This.SQLCommand.ExecuteReader()
        }
        Catch
        {
            $This.SQLConnection.Close()
            return $(Write-host $_ -ForegroundColor Red)           
        }

        If ($This.SQLReader)
        {
            $This.Result = [System.Data.DataTable]::new()
            $This.Result.Load($This.SQLReader)
            $This.SQLConnection.Close()
        }

        If ($This.DisplayResults)
        {
            Return $This.Result
        }
        Else
        {
            Return $null
        }

    }


    # Method
    [Object] ListTables()
    {

        If ($This.ConnectionString)
        {
            $TableConnectionString = $This.ConnectionString
        }
        Else
        {
            $TableConnectionString = "Server=$($This.SQLServer);Database=$($This.Database);Integrated Security=SSPI;Connection Timeout=$($This.ConnectionTimeout)"
        }

        $TableSQLConnection = [System.Data.SqlClient.SqlConnection]::new()
        $TableSQLConnection.ConnectionString = $TableConnectionString

        Try
        {
            $TableSQLConnection.Open()
        }
        Catch
        {
            return $(Write-host $_ -ForegroundColor Red)    
        }

        Try
        {
            $TableQuery = "Select Name from Sys.Tables Order by Name"
            
            $TableSQLCommand = $TableSQLConnection.CreateCommand()
            $TableSQLCommand.CommandText = $TableQuery
            $TableSQLCommand.CommandTimeout = $This.CommandTimeout
            $TableSQLReader = $TableSQLCommand.ExecuteReader()
        }
        Catch
        {
            $TableSQLConnection.Close()
            $TableSQLConnection.Dispose()
            return $(Write-host $_ -ForegroundColor Red)           
        }

        If ($TableSQLReader)
        {
            $This.Tables = [System.Data.DataTable]::new()
            $This.Tables.Load($TableSQLReader)
            $TableSQLConnection.Close()
            $TableSQLConnection.Dispose()
        }

        If ($This.DisplayResults)
        {
            Return $This.Tables
        }
        Else
        {
            Return $null
        }

    }

    # Method
    [Object] ListViews()
    {

        If ($This.ConnectionString)
        {
            $ViewConnectionString = $This.ConnectionString
        }
        Else
        {
            $ViewConnectionString = "Server=$($This.SQLServer);Database=$($This.Database);Integrated Security=SSPI;Connection Timeout=$($This.ConnectionTimeout)"
        }

        $ViewSQLConnection = [System.Data.SqlClient.SqlConnection]::new()
        $ViewSQLConnection.ConnectionString = $ViewConnectionString

        Try
        {
            $ViewSQLConnection.Open()
        }
        Catch
        {
            return $(Write-host $_ -ForegroundColor Red)    
        }

        Try
        {
            $ViewQuery = "Select Name from Sys.Views Order by Name"
            
            $ViewSQLCommand = $ViewSQLConnection.CreateCommand()
            $ViewSQLCommand.CommandText = $ViewQuery
            $ViewSQLCommand.CommandTimeout = $This.CommandTimeout
            $ViewSQLReader = $ViewSQLCommand.ExecuteReader()
        }
        Catch
        {
            $ViewSQLConnection.Close()
            $ViewSQLConnection.Dispose()
            return $(Write-host $_ -ForegroundColor Red)           
        }

        If ($ViewSQLReader)
        {
            $This.Views = [System.Data.DataTable]::new()
            $This.Views.Load($ViewSQLReader)
            $ViewSQLConnection.Close()
            $ViewSQLConnection.Dispose()
        }

        If ($This.DisplayResults)
        {
            Return $This.Views
        }
        Else
        {
            Return $null
        }

    }

}

# Define a class
class BackgroundJob
{
    # Properties
    hidden $PowerShell = [powershell]::Create() 
    hidden $Handle = $null
    hidden $Runspace = $null
    $Result = $null
    $RunspaceID = $This.PowerShell.Runspace.ID
    $PSInstance = $This.PowerShell

    
    # Constructor (just code block)
    BackgroundJob ([scriptblock]$Code)
    { 
        $This.PowerShell.AddScript($Code)
    }

    # Constructor (code block + arguments)
    BackgroundJob ([scriptblock]$Code,$Arguments)
    { 
        $This.PowerShell.AddScript($Code)
        foreach ($Argument in $Arguments)
        {
            $This.PowerShell.AddArgument($Argument)
        }
    }

    # Constructor (code block + arguments + functions)
    BackgroundJob ([scriptblock]$Code,$Arguments,$Functions)
    { 
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $Scope = [System.Management.Automation.ScopedItemOptions]::AllScope
        foreach ($Function in $Functions)
        {
            $FunctionName = $Function.Split('\')[1]
            $FunctionDefinition = Get-Content $Function -ErrorAction Stop
            $SessionStateFunction = New-Object -TypeName System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $FunctionName, $FunctionDefinition, $Scope, $null
            $InitialSessionState.Commands.Add($SessionStateFunction)
        }
        $This.Runspace = [runspacefactory]::CreateRunspace($InitialSessionState)
        $This.PowerShell.Runspace = $This.Runspace
        $This.Runspace.Open()
        $This.PowerShell.AddScript($Code)
        foreach ($Argument in $Arguments)
        {
            $This.PowerShell.AddArgument($Argument)
        }
    }
    
    # Start Method
    Start()
    {
        $THis.Handle = $This.PowerShell.BeginInvoke()
    }

    # Stop Method
    Stop()
    {
        $This.PowerShell.Stop()
    }

    # Receive Method
    [object]Receive()
    {
        $This.Result = $This.PowerShell.EndInvoke($This.Handle)
        return $This.Result
    }

    # Remove Method
    Remove()
    {
        $This.PowerShell.Dispose()
        If ($This.Runspace)
        {
            $This.Runspace.Dispose()
        }
    }

    # Get Status Method
    [object]GetStatus()
    {
        return $This.PowerShell.InvocationStateInfo
    }
}