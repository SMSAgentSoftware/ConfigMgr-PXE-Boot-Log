﻿##############################
### ConfigMgr PXE Boot Log ###
##############################

# Set the source directory
$OS = (Get-CimInstance -ClassName Win32_OperatingSystem -Property OSArchitecture).OSArchitecture
If ($OS -eq "32-bit")
{
    $ProgramFiles = $env:ProgramFiles
}
If ($OS -eq "64-bit")
{
    $ProgramFiles = ${env:ProgramFiles(x86)}
}

$Source = "$ProgramFiles\SMSAgent\ConfigMgr PXE Boot Log"

# Load the required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -Path "$Source\bin\MaterialDesignColors.dll"
Add-Type -Path "$Source\bin\MaterialDesignThemes.Wpf.dll"

# Load in the function library
. "$Source\bin\FunctionLibrary.ps1"

# Do PS version check
If ($PSVersionTable.PSVersion.Major -lt 5)
{
  New-PopupMessage -Message "ConfigMgr PXE Boot Log cannot start because it requires PowerShell 5 or greater. Please upgrade your PowerShell version." -Title "ConfigMgr PXE Boot Log" -ButtonType Ok -IconType Stop
  Break
}

# File hash checks
$XAMLFiles = @(
    "About.xaml"
    "App.xaml"
    "Devices.xaml"
    "Help.xaml"
    "HelpFlowDocument.xaml"
    "Settings.xaml"
)

$PSFiles = @(
    "ClassLibrary.ps1"
    "EventLibrary.ps1"
    "FunctionLibrary.ps1"
)

$Hashes = @{
    "ClassLibrary.ps1" = '1F9C550027197CD5C3DFF2D2C2244BB0B0A31F40B8133164A41AC897754493A9'
    "EventLibrary.ps1" = '23CF1E3CA32A23948DA296D7ED0EC00BAB280A4791933C9C461F96345233B963'
    "FunctionLibrary.ps1" = '5E4A9A5B82DEDB48AAA8ACA5F96724654737251894B014AB33A55BF5E8BD06C1'
    "About.xaml" = '80553FB09E1E6B71D803D633A147FEFDF2F0390EB4DF7ABBC7459E2852B8392E'
    "App.xaml" = '3188DF98290A04FCDF0377BA41361B0884AF786EA0E90D8A48283192DABDF681'
    "Devices.xaml" = '2A01661C76FF449B1A547A7A4F0CEB95FFE60862042107BAAE468CA9B1CD258E'
    "Help.xaml" = 'E52DC0F561D41A74522EBDC7660A77A89606E324BCE74769F27492EAD7797812'
    "HelpFlowDocument.xaml" = 'D220A6BBAE5220168E3BB2EBB4781A76EC5F5D670C3CE4C3A36D928EF4A11F78'
    "Settings.xaml" = 'AFE6F729AE3E237C207759E117861038CFDD8EE4733C54F05506E9EC0DFD37F8'
}

$XAMLFiles | foreach {

    If ((Get-FileHash -Path "$Source\XAML Files\$_").Hash -ne $Hashes.$_)
    {
        New-PopupMessage -Message "One or more installation files failed a hash check. As a security measure, the installation files cannot be altered to prevent running unauthorized code. Please revert the changes or reinstall the application." -Title "ConfigMgr PXE Boot Log" -ButtonType Ok -IconType Stop
        Break
    }
}

$PSFiles | foreach {

    If ((Get-FileHash -Path "$Source\bin\$_").Hash -ne $Hashes.$_)
    {
        New-PopupMessage -Message "One or more installation files failed a hash check. As a security measure, the installation files cannot be altered to prevent running unauthorized code. Please revert the changes or reinstall the application." -Title "ConfigMgr PXE Boot Log" -ButtonType Ok -IconType Stop
        Break
    }
}

# Define the XAML code for the main window
[XML]$Xaml = [System.IO.File]::ReadAllLines("$Source\XAML files\App.xaml") 

# Create a synchronized hash table and add the WPF window and its named elements to it
$Global:UI = [System.Collections.Hashtable]::Synchronized(@{})
$UI.Window = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml))
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
    $UI.$($_.Name) = $UI.Window.FindName($_.Name)
    }

# Set the window icon
$UI.Window.Icon = "$Source\bin\network.ico"

# Load in the code libraries
. "$Source\bin\ClassLibrary.ps1"
. "$Source\bin\EventLibrary.ps1"

# Add the host
$UI.Host = $Host

# Define the possible time periods for searching
$TimePeriods = @(
    "Last hour",
    "Last 6 hours",
    "Last 12 hours",
    "Last 24 hours",
    "Last 7 days",
    "Last 4 weeks"
)

# Create an observable collection to hold common session data that will be used across threads.  WPF control properties are bound to some of these.
$UI.SessionData = New-Object System.Collections.ObjectModel.ObservableCollection[Object]
$UI.SessionData.Add($null)
$UI.SessionData.Add($TimePeriods)
$UI.SessionData.Add("False") # not used
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add($null)
$UI.SessionData.Add("HKCU:\SOFTWARE\SMSAgent\ConfigMgr PXE Boot Log")
$UI.SessionData.Add("False")
$UI.SessionData.Add($null) # not used
$UI.SessionData.Add($null)
$UI.SessionData.Add([double]1.2)
$UI.SessionData.Add($Source)
$UI.SessionData.Add(0)
$UI.SessionData.Add($null)
$UI.Window.DataContext = $UI.SessionData

# SessionData Index reference
#[0] = PXE Combo Items
#[1] = TimePeriod Items
#[2] = DataGrid Content Menu IsEnabled
#[3] = Datagrid ItemsSource
#[4] = SQL Server
#[5] = Database
#[6] = DistributionPoint Selected
#[7] = TimePeriod Select
#[8] = Devices Datagrid ItemsSource
#[9] = Selected Row SMBIOSGUID
#[10] = HKCU Registry location
#[11] = Retrieve button is enabled
#[12] = Version history value
#[13] = Version history datasource
#[14] = Current version
#[15] = Source
#[16] = UTC Offset
#[17] = Convert the log times to current time zone

# Create an array to hold the runspaces
$UI.Jobs = @()

# Start a dispatcher timer to periodically close any completed runspaces that are not yet disposed
$TimerCode = {
    If ($UI.Jobs.Count)
        {
        $UI.Jobs | Foreach {
            If ($_.PSInstance.Runspace.RunspaceStateInfo.State -ne "Closed" -and $_.PSInstance.InvocationStateInfo.State -eq "Completed")
            {
                Try
                {
                    (Get-Runspace -Id $_.PSInstance.Runspace.Id).Dispose()
                }
                Catch{}
            }
        }
    }
}
$DispatcherTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
$DispatcherTimer.Interval = [TimeSpan]::FromSeconds(15) # Every 15 seconds
$DispatcherTimer.Add_Tick($TimerCode)
$DispatcherTimer.Start()

# Register an event that will be called by another thread to open the TechNet page when an update is available
Register-EngineEvent -SourceIdentifier "InvokeUpdate" -Action {Start-Process "https://gallery.technet.microsoft.com/ConfigMgr-PXE-Boot-Log-e11a924b"} | Out-Null

# If code is running in ISE, use ShowDialog() to display...
if ($psISE)
{
    $null = $UI.window.Dispatcher.InvokeAsync{$UI.window.ShowDialog()}.Wait()
}
# ...otherwise run as an application
Else
{
    # Make PowerShell Disappear
    $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncwindow = Add-Type -MemberDefinition $windowcode -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru
    $null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)

    $app = New-Object -TypeName Windows.Application
    $app.Run($UI.Window)

}