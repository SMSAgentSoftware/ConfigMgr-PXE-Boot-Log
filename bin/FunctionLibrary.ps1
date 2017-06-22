# Function to display a pop-up box
function New-PopupMessage {
# Return values for reference (https://msdn.microsoft.com/en-us/library/x83z1d9f(v=vs.84).aspx)

# Decimal value    Description  
# -----------------------------
# -1               The user did not click a button before nSecondsToWait seconds elapsed.
# 1                OK button
# 2                Cancel button
# 3                Abort button
# 4                Retry button
# 5                Ignore button
# 6                Yes button
# 7                No button
# 10               Try Again button
# 11               Continue button

# Define Parameters
[CmdletBinding()]
    [OutputType([int])]
    Param
    (
        # The popup message
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Message,

        # The number of seconds to wait before closing the popup.  Default is 0, which leaves the popup open until a button is clicked.
        [Parameter(Mandatory=$false,Position=1)]
        [int]$SecondsToWait = 0,

        # The window title
        [Parameter(Mandatory=$true,Position=2)]
        [string]$Title,

        # The buttons to add
        [Parameter(Mandatory=$true,Position=3)]
        [ValidateSet('Ok','Ok-Cancel','Abort-Retry-Ignore','Yes-No-Cancel','Yes-No','Retry-Cancel','Cancel-TryAgain-Continue')]
        [array]$ButtonType,

        # The icon type
        [Parameter(Mandatory=$true,Position=4)]
        [ValidateSet('Stop','Question','Exclamation','Information')]
        $IconType
    )

# Convert button types
switch($ButtonType)
    {
        "Ok" { $Button = 0 }
        "Ok-Cancel" { $Button = 1 }
        "Abort-Retry-Ignore" { $Button = 2 }
        "Yes-No-Cancel" { $Button = 3 }
        "Yes-No" { $Button = 4 }
        "Retry-Cancel" { $Button = 5 }
        "Cancel-TryAgain-Continue" { $Button = 6 }
    }

# Convert Icon types
Switch($IconType)
    {
        "Stop" { $Icon = 16 }
        "Question" { $Icon = 32 }
        "Exclamation" { $Icon = 48 }
        "Information" { $Icon = 64 }
    }

# Create the popup
(New-Object -ComObject Wscript.Shell).popup($Message,$SecondsToWait,$Title,$Button + $Icon)
}


# Function to create the required registry keys
Function Create-RegistryKeys
{
    If (!(Test-Path -Path $UI.SessionData[10]))
    {
        New-Item -Path $UI.SessionData[10] -Force | out-null
        New-ItemProperty -Path $UI.SessionData[10] -Name SQLServer -Value "" | out-null
        New-ItemProperty -Path $UI.SessionData[10] -Name Database -Value "" | out-null
        New-ItemProperty -Path $UI.SessionData[10] -Name UseLocalTimeZone -Value "False" | out-null
    }
}


# Function to update registry keys
Function Update-Registry 
{
    param($SQLServer, $Database, $UseLocalTimeZone)

    Set-ItemProperty -Path $UI.SessionData[10] -Name SQLServer -Value $SQLServer | out-null
    Set-ItemProperty -Path $UI.SessionData[10] -Name Database -Value $Database | Out-Null
    Set-ItemProperty -Path $UI.SessionData[10] -Name UseLocalTimeZone -Value $UseLocalTimeZone | Out-Null
}


# Function to read the registry keys
Function Read-Registry 
{
    $UI.SessionData[4] = Get-ItemProperty -Path $UI.SessionData[10] -Name SQLServer |  Select-Object -ExpandProperty SQLServer
    $UI.SessionData[5] = Get-ItemProperty -Path $UI.SessionData[10] -Name Database | Select-Object -ExpandProperty Database
    $UI.SessionData[17] = Get-ItemProperty -Path $UI.SessionData[10] -Name UseLocalTimeZone | Select-Object -ExpandProperty UseLocalTimeZone

    # Prompt user to enter the SQL Server and Database info if not yet populated
    If (!($ui.SessionData[4]) -or !($UI.SessionData[5]))
    {
        New-PopupMessage -Message "Please enter the ConfigMgr database information from the Settings menu!" -Title "ConfigMgr database info missing" -ButtonType Ok -IconType Exclamation
    }
}


# Function to load the PXE Service Points
Function Get-PXEServicePoints {
    
    # Define the source directory
    $Source = $UI.SessionData[15]

    # Load in the class library
    . "$Source\bin\ClassLibrary.ps1"

    #Set the SQL Server and database
    $SQLServer = $UI.SessionData[4]
    $Database = $UI.SessionData[5]

    # Get the UTC offset of the SQL server (if there is one). This is required so that we can correctly search using the selected time periods.
    $Query = "SELECT LEFT(RIGHT(SYSDATETIMEOFFSET(),6),3) as 'UTCOffset'"
    $SQLQuery = [SQLQuery]::new($SQLServer, $Database, $Query)
    Try
    {
        [int]$UTCOffset = $SQLQuery.Execute() | Select -ExpandProperty UTCOffset
    }
    Catch
    {
        New-PopupMessage -Message "Could not run SQL query!`n`n$($Error[1].Exception.Message)" -Title "Get UTC Offset of SQL Server" -ButtonType Ok -IconType Stop
        Return
    }

    # Convert UTCOffset value (ie positive to negative and vice versa) for correct calculation with the DATEADD() function
    If ($UTCOffset -ne 0)
    {
        $UTCOffset  = $UTCOffset - $UTCOffset - $UTCOffset
    }

    # Add the UTC Offset to the session data
    $UI.SessionData[16] = $UTCOffset

    # Get PXE Service Point list
    $Query = "Select ServerName from v_DistributionPoints where IsPxe = 1 Order By ServerName"
    $SQLQuery = [SQLQuery]::new($SQLServer, $Database, $Query)
    $SQLQuery.DisplayResults = $False
    Try
    {
        $SQLQuery.Execute()
    }
    Catch
    {
        New-PopupMessage -Message "Could not run SQL query!`n`n$($Error[1].Exception.Message)" -Title "Get PXE Service Points" -ButtonType Ok -IconType Stop
        Return
    }

    # Add the Service point list to the session data and UI
    $UI.SessionData[0] = $SQLQuery.Result | Select -ExpandProperty ServerName

    # Enable the "retrieve log" button
    $UI.SessionData[11] = "True"

}


# Function to load the PXE boot data from SCCM
Function Get-PXELog {
    
    # Define the source directory
    $Source = $UI.SessionData[15]

    # Load in the class library
    . "$Source\bin\ClassLibrary.ps1"

    # Set values including SQL server, database etc
    $SQLServer = $UI.SessionData[4]
    $Database = $UI.SessionData[5]
    $DistributionPoint = $UI.SessionData[6]
    $TimePeriod = $UI.SessionData[7]
    $UTCOffset = $UI.SessionData[16]
    $ConvertTimezone = $UI.SessionData[17]

    # Convert from FQDN to friendly name only (required for SQL query)
    If ($DistributionPoint -match '.')
    {
        $DistributionPoint = $DistributionPoint.Split('.')[0]
    }

    # Set the time period in hours based on the UI selection
    Switch ($TimePeriod)
    {
        "Last hour" {$TimeInHours = 1}
        "Last 6 hours" {$TimeInHours = 6}
        "Last 12 hours" {$TimeInHours = 12}
        "Last 24 hours" {$TimeInHours = 24}
        "Last 7 days" {$TimeInHours = 168}
        "Last 4 weeks" {$TimeInHours = 672}
    }

    # Define the SQL query to run
    $Query = "
    select smsgs.Time,
    --DATEDIFF(hour,smsgs.Time,(DATEADD(hour, $UTCOffset, GETDATE()))) as 'TimeInHours',
    --$UTCOffset as 'Offset',
    smsgs.MachineName as 'PXE Service Point',
    case smsgs.MessageID
    when 6311 then 'PXE boot'
    when 6314 then 'Normal boot'
    end as 'Boot Type',
    smwis.InsString1 as 'MAC Address',
    smwis.InsString2 as 'SMBIOS GUID',
    bip.Name as 'Boot Image Name',
    --smwis.InsString3 as 'Boot Image ID',
    cd.CollectionName as 'Targeted Collection',
    --smwis.InsString4 as 'Deployment ID',
    case smsgs.MessageID
    when 6311 then 'The PXE Service Point instructed the device to boot to bootimage ' + smwis.InsString3 + ' based on deployment ' + smwis.InsString4 + '.'
    when 6314 then 'The PXE Service Point instructed the device to boot normally as it has no PXE deployment assigned.'
    end as 'Message'
    from v_StatusMessage smsgs   
    join v_StatMsgWithInsStrings smwis on smsgs.RecordID = smwis.RecordID
    join v_StatMsgModuleNames modNames on smsgs.ModuleName = modNames.ModuleName
    left join v_BootImagePackage bip on smwis.InsString3 = bip.PackageID
    left join vClassicDeployments cd on smwis.InsString4 = cd.DeploymentId
    where smsgs.MachineName like '%$DistributionPoint%' 
    and smsgs.MessageID in (6311,6314)
    and DATEDIFF(hour,smsgs.Time,(DATEADD(hour, $UTCOffset, GETDATE()))) <= '$TimeInHours'
    Order by smsgs.Time DESC
    "

    # Run the query
    $SQLQuery = [SQLQuery]::new($SQLServer, $Database, $Query)
    $SQLQuery.DisplayResults = $False
    Try
    {
        $SQLQuery.Execute()
    }
    Catch
    {
        New-PopupMessage -Message "Could not run SQL query!`n`n$($Error[1].Exception.Message)" -Title "SQL Query" -ButtonType Ok -IconType Stop
        Return
    }

    # If no results found...
    If ($SQLQuery.Result.Rows.Count -lt 1)
    {
        New-PopupMessage -Message "No results were found for this time period!" -Title "PXE Log" -ButtonType Ok -IconType Information
        Return
    }

    ## Convert date/time format and timezone (if selected) to local ##
    
    # Add a temporary column
    $SQLQuery.Result.Columns.Add("TimeTemp")

    If ($ConvertTimezone -eq "True")
    {
        Foreach ($Row in $SQLQuery.Result.Rows)
        {
            # Populate the column using the local timezone and format
            $Row.TimeTemp = [System.TimeZone]::CurrentTimeZone.ToLocalTime($($Row.Time | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern))
        }
    }
    Else
    {
        Foreach ($Row in $SQLQuery.Result.Rows)
        {
            # Populate the column using the local format
            $Row.TimeTemp = $Row.Time | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern
        }
    }

    # Put the new column at the beginning
    $SQLQuery.Result.Columns['TimeTemp'].SetOrdinal(0)

    # Remove the existing "Time" column
    $SQLQuery.Result.Columns.Remove("Time")

    # Rename the new column to "Time"
    $SQLQuery.Result.Columns['TimeTemp'].ColumnName = "Time"


    # Add the query results to the session data and the UI
    $UI.SessionData[3] = $SQLQuery.Result.DefaultView

}


# Function to get associated devices from SCCM
Function Get-AssociatedDevices {

    # Set required values
    $SQLServer = $UI.SessionData[4]
    $Database = $UI.SessionData[5]
    $SMBIOSGUID = $UI.SessionData[9]
    $ConvertTimezone = $UI.SessionData[17]

    # Define SQL query
    $Query = "
    Select sys.resourceID as 'ItemKey',
    sys.Name0 as 'Device Name',
    sys.Full_Domain_Name0 as 'Domain',
    sys.Creation_Date0 as 'Record Creation Date',
    ch.ClientStateDescription as 'Client State',
    ch.LastActiveTime as 'Last Active Time',
    sys.SMBIOS_GUID0 as 'SMBIOSGUID'
    from V_R_System sys
    left join V_CH_ClientSummary ch on sys.ResourceID = ch.ResourceID
    where SMBIOS_GUID0 = '$SMBIOSGUID'
    "

    # Run the query
    $SQLQuery = [SQLQuery]::new($SQLServer, $Database, $Query)
    $SQLQuery.DisplayResults = $False
    Try
    {
        $Result = $SQLQuery.Execute()
    }
    Catch
    {
        New-PopupMessage -Message "Could not run SQL query!`n`n$($Error[1].Exception.Message)" -Title "SQL Query" -ButtonType Ok -IconType Stop
        Return
    }

    # If results are returned
    If ($SQLQuery.Result.Rows.Count -ge 1)
    {
        
        ## Convert date/time format and adjust for timezone if selected ##
    
        # Add a temporary column
        $SQLQuery.Result.Columns.Add("CreationDateTemp")

        If ($ConvertTimezone -eq "True")
        {
            Foreach ($Row in $SQLQuery.Result.Rows)
            {
                # Populate the column using the local timezone and format
                $Row.CreationDateTemp = [System.TimeZone]::CurrentTimeZone.ToLocalTime($($Row.'Record Creation Date' | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern))
            }
        }
        Else
        {
            Foreach ($Row in $SQLQuery.Result.Rows)
            {
                # Populate the column using the local format
                $Row.CreationDateTemp = $Row.'Record Creation Date' | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern
            }
        }

        # Put the new column at the beginning
        $SQLQuery.Result.Columns['CreationDateTemp'].SetOrdinal(3)

        # Remove the existing column
        $SQLQuery.Result.Columns.Remove('Record Creation Date')

        # Rename the new column
        $SQLQuery.Result.Columns['CreationDateTemp'].ColumnName = 'Record Creation Date'
        
         # Add a temporary column
        $SQLQuery.Result.Columns.Add("ActiveTimeTemp")

        If ($ConvertTimezone -eq "True")
        {
            Foreach ($Row in $SQLQuery.Result.Rows)
            {
                # Populate the column using the local timezone and format
                If ($Row.'Last Active Time' -isnot [dbnull])
                {
                    $Row.ActiveTimeTemp = [System.TimeZone]::CurrentTimeZone.ToLocalTime($($Row.'Last Active Time' | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern))
                }
            }
        }
        Else
        {
            Foreach ($Row in $SQLQuery.Result.Rows)
            {
                # Populate the column using the local format
                If ($Row.'Last Active Time' -isnot [dbnull])
                {
                    $Row.ActiveTimeTemp = $Row.'Last Active Time' | Get-Date -Format (Get-Culture).DateTimeFormat.FullDateTimePattern
                }
            }
        }

        # Put the new column at the beginning
        $SQLQuery.Result.Columns['ActiveTimeTemp'].SetOrdinal(5)

        # Remove the existing column
        $SQLQuery.Result.Columns.Remove('Last Active Time')

        # Rename the new column 
        $SQLQuery.Result.Columns['ActiveTimeTemp'].ColumnName = 'Last Active Time'
        
        
        
        # Add the results to the session data and UI
        $UI.SessionData[8] = $SQLQuery.Result.DefaultView

        # Create and load the associated records window
        [XML]$Xaml2 = [System.IO.File]::ReadAllLines("$Source\XAML files\Devices.xaml") 
        $UI.DevicesWindow = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml2))
        $UI.DevicesWindow.Icon = "$Source\bin\network.ico"
        $UI.DevicesWindow.DataContext = $UI.SessionData
        $UI.DevicesWindow.Owner = $UI.Window
        $null = $UI.DevicesWindow.ShowDialog()
    }
    Else
    {
        New-PopupMessage -Message "No associated records were found in ConfigMgr!" -Title "Associated Records" -ButtonType Ok -IconType Information
        Return
    }

}


# Function to display settings window
Function Get-Settings {

    # Create the Settings window
    [XML]$Xaml3 = [System.IO.File]::ReadAllLines("$Source\XAML files\Settings.xaml") 
    $UI.SettingsWindow = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml3))
    $xaml3.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
    $UI.$($_.Name) = $UI.SettingsWindow.FindName($_.Name)
    }
    $UI.SettingsWindow.Icon = "$Source\bin\network.ico"
    $UI.SettingsWindow.DataContext = $UI.SessionData
    $UI.SettingsWindow.Owner = $UI.Window

    # Get the IsChecked value and add to the session data (convert to boolean first)
    $UI.UseLocalTimeZone.IsChecked = [System.Convert]::ToBoolean($UI.SessionData[17])

    # Event: Save button clicked
    $UI.Btn_SettingsOK.Add_Click({

        # Get the IsChecked value and add it to the session data
        If ($UI.UseLocalTimeZone.IsChecked -eq $True)
        {
            $UI.SessionData[17] = "True"
        }
        Else
        {
            $UI.SessionData[17] = "False"
        }

        # Update the registry with the [new] values
        Update-Registry -SQLServer $UI.SQLServer.text -Database $UI.Database.text -UseLocalTimeZone $UI.SessionData[17]

        # Read the registry again to make sure valid values are set
        Read-Registry

        # If SQLServer and database are present, load the PXE service points list
        If ($ui.SessionData[4] -and $UI.SessionData[5])
        {
            $Code = {
                Param($UI)
                Get-PXEServicePoints
            }
            $Job = [BackgroundJob]::new($Code, @($UI), "Function:\Get-PXEServicePoints")
            $UI.Jobs += $Job
            $Job.Start()
        }

        # Close the Settings window
        $UI.SettingsWindow.Close()

    })

    # Show the Settings window
    $null = $UI.SettingsWindow.ShowDialog()
}


# Function to display "About" window
Function Display-About {

    # Create the Display window
    [XML]$Xaml4 = [System.IO.File]::ReadAllLines("$Source\XAML files\About.xaml") 
    $UI.AboutWindow = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml4))
    $xaml4.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
        $UI.$($_.Name) = $UI.AboutWindow.FindName($_.Name)
    }
    $UI.AboutWindow.Icon = "$Source\bin\network.ico"
    $UI.AboutWindow.DataContext = $UI.SessionData
    $UI.AboutWindow.Owner = $UI.Window

    # Set events to open the hyperlinks
    $UI.BlogLink, $UI.MDLink, $UI.GitLink, $UI.PayPalLink | Foreach {
        $_.Add_Click({
            Start-Process $This.NavigateURI
        })
    }

    # Show the About window
    $null = $UI.AboutWindow.ShowDialog()
}


# Function to display "Help" window
Function Display-Help {

    # Create the Help window
    [XML]$Xaml5 = [System.IO.File]::ReadAllLines("$Source\XAML files\Help.xaml") 
    $UI.HelpWindow = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml5))
    $xaml5.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
        $UI.$($_.Name) = $UI.HelpWindow.FindName($_.Name)
    }
    $UI.HelpWindow.Icon = "$Source\bin\network.ico"
    $UI.HelpWindow.DataContext = $UI.SessionData
    $UI.HelpWindow.Owner = $UI.Window

    # Read the FlowDocument content
    [XML]$HelpFlow = [System.IO.File]::ReadAllLines("$Source\XAML Files\HelpFlowDocument.xaml")
    $Reader = New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $HelpFlow
    $XamlDoc = [System.Windows.Markup.XamlReader]::Load($Reader)

    # Add the FlowDocument to the Window
    $UI.HelpWindow.AddChild($XamlDoc)

    # Show thw Help window
    $null = $UI.HelpWindow.ShowDialog()
}


# Function to check if a new version has been released
Function Check-CurrentVersion {
    Param($UI)

    # Download XML from internet
    Try
    {
        # Use the raw.gihubusercontent.com/... URL
        $URL = "https://raw.githubusercontent.com/SMSAgentSoftware/ConfigMgr-PXE-Boot-Log/master/Versions/PXE_Boot_Log_Current.xml"
        $WebClient = New-Object System.Net.WebClient
        $webClient.UseDefaultCredentials = $True
        $ByteArray = $WebClient.DownloadData($Url)
        $WebClient.DownloadFile($url, "$env:USERPROFILE\AppData\Local\Temp\PXE_Boot_Log.xml")
        $Stream = New-Object System.IO.MemoryStream($ByteArray, 0, $ByteArray.Length)
        $XMLReader = New-Object System.Xml.XmlTextReader -ArgumentList $Stream
        $XMLDocument = New-Object System.Xml.XmlDocument
        [void]$XMLDocument.Load($XMLReader)
        $Stream.Dispose()
    }
    Catch
    {
        Return
    }

    # Add version history to OC
    $UI.SessionData[12] = $XMLDocument

    # Create a datatable for the version history
    $Table = New-Object -TypeName 'System.Data.DataTable'
    [void]$Table.Columns.Add('Version')
    [void]$Table.Columns.Add('Release Date')
    [void]$Table.Columns.Add('Changes')

    # Add a row for each version
    $XMLDocument.PXE_Boot_Log.Versions.Version | sort Value -Descending | foreach {
    
        # The changes are put into an array, then converted to a string with each change on a new line for correct display
        [array]$Changes = $_.Changes.Change
        $ofs = "`r`n"
        $Table.Rows.Add($_.Value, $_.ReleaseDate, [string]$Changes)
    
    }

    # Set the source of the datagrid
    $UI.SessionData[13] = $Table

    # Get Current version number
    [double]$CurrentVersion = $XMLDocument.PXE_Boot_Log.Versions.Version.Value | Sort -Descending | Select -First 1

    # Enable the "Update" menut item to notify user
    If ($CurrentVersion -gt $UI.SessionData[14])
    {
        Show-BalloonTip -Text "A new version is available. Click to update!" -Title "ConfigMgr PXE Boot Log" -Icon Info -UI $UI
    }

    # Cleanup temp file
    If (Test-Path -Path "$env:USERPROFILE\AppData\Local\Temp\PXE_Boot_Log.xml")
    {
        Remove-Item -Path "$env:USERPROFILE\AppData\Local\Temp\PXE_Boot_Log.xml" -Force -Confirm:$false
    }

}


# Function to display a notification tip
function Show-BalloonTip  
{
 
  [CmdletBinding(SupportsShouldProcess = $true)]
  param
  (
    [Parameter(Mandatory=$true)]
    $Text,
   
    [Parameter(Mandatory=$true)]
    $Title,
   
    [ValidateSet('None', 'Info', 'Warning', 'Error')]
    $Icon = 'Info',
    $Timeout = 30000,
    $UI
  )
 
  Add-Type -AssemblyName System.Windows.Forms

  $Form = New-Object System.Windows.Forms.Form
  $Form.ShowInTaskbar = $false
  $Form.WindowState = "Minimized"

  $balloon = New-Object System.Windows.Forms.NotifyIcon

  $path                    = Get-Process -id $pid | Select-Object -ExpandProperty Path
  $balloon.Icon            = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
  $balloon.BalloonTipIcon  = $Icon
  $balloon.BalloonTipText  = $Text
  $balloon.BalloonTipTitle = $Title
  $balloon.Visible         = $true

  $Balloon.Add_BalloonTipClicked({
    $UI.Host.Runspace.Events.GenerateEvent("InvokeUpdate",$null,$null, "InvokeUpdate")
    $This.Dispose()
    $Form.Dispose()
  })

  $Balloon.Add_BalloonTipClosed({
    $This.Dispose()
    $Form.Dispose()
  })

  $balloon.ShowBalloonTip($Timeout)

  $Form.ShowDialog()

  # Can run as app but generate event won't work (different context)
  #$App = [System.Windows.Application]::new()
  #$app.Run($Form)

} 