# Event: Window loaded
$UI.Window.Add_Loaded({
    
    # Activate the window
    $This.Activate()

    # Create registry keys in the CU hive if they don't exist
    Create-RegistryKeys

    # Read the registry keys
    Read-Registry

    # If we have a SQL server and database...
    If ($ui.SessionData[4] -and $UI.SessionData[5])
    {
        # Get the PXE Service point list in a background job
        $Code = {
            Param($UI)
            Get-PXEServicePoints
        }
        $Job = [BackgroundJob]::new($Code, @($UI), @("Function:\Get-PXEServicePoints","Function:\New-PopupMessage"))
        $UI.Jobs += $Job
        $Job.Start()

        # Check if new version is available in a background job
        $Code = {
            Param($UI)
            Check-CurrentVersion -UI $UI
        }
        $Job = [BackgroundJob]::new($Code,@($UI),@("Function:\Check-CurrentVersion","Function:\Show-BalloonTip"))
        $UI.Jobs += $Job
        $Job.Start()
    }
})


# Event: Click the Retrieve Log button
$UI.Retrieve.Add_Click({
   
    # Check that a DP and time period are selected
    If ($UI.PXE.SelectedItem -eq $null)
    {
        New-PopupMessage -Message "Please select a PXE Service point!" -Title "PXE Service Point" -ButtonType Ok -IconType Exclamation
        Return
    }

    If ($UI.TimePeriod.SelectedItem -eq $null)
    {
        New-PopupMessage -Message "Please select a time period!" -Title "Time Period" -ButtonType Ok -IconType Exclamation
        Return
    }

    # Add the selections to the session data
    $UI.SessionData[6] = $UI.PXE.SelectedItem
    $UI.SessionData[7] = $UI.TimePeriod.SelectedItem  
    $UI.SessionData[3] = $null
   
    # Get the PXE log data in a background process
    $Code = {
        Param($UI)
        Get-PXELog
    }
    $Job = [BackgroundJob]::new($Code, @($UI), @("Function:\Get-PXELog","Function:\New-PopupMessage"))
    $UI.Jobs += $Job
    $Job.Start() 
})


# Event: Double-click the datagrid
$UI.DataGrid.Add_MouseDoubleClick({
    
    # Add the SMBIOS GUID to the session data
    $UI.SessionData[9] = $ui.DataGrid.SelectedItem.'SMBIOS GUID'
    
    # Get the list of associated records in SCCM
    Get-AssociatedDevices
})

# Event: Click the exit button
$UI.Btn_Exit.Add_Click({
    
    # Close the window
    $UI.Window.Close()

})

# Event: Click the Settings button
$UI.Btn_Settings.Add_Click({
    
    # Show the Settings window
    Get-Settings

})

# Event: Click the About button
$UI.Btn_About.Add_Click({
    
    # Show the About window
    Display-About

})

# Event: Click the Help button
$UI.Btn_Help.Add_Click({
    
    # Show the Help window
    Display-Help

})

