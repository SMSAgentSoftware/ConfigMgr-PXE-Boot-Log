# ConfigMgr-PXE-Boot-Log
ConfigMgr PXE Boot Log enables you to view PXE boot events on a ConfigMgr PXE Service Point. It can also display any associated records that exist in ConfigMgr for the device that attempted PXE boot. It is intended as a troubleshooting tool to help with systems that fail to PXE boot, and can be useful for ConfigMgr admins, or IT support staff who may not have access to the SMSPXE.log on the distribution point.

## Requirements
* PowerShell 5+
* Minimum .Net Framework 4.5
* Minimum read-only access to the Configuration Manager database (db_datareader role)

## Installer
The MSI installer can be found on the [Technet Gallery](https://gallery.technet.microsoft.com/ConfigMgr-PXE-Boot-Log-e11a924b).

![Screenshot](https://raw.githubusercontent.com/SMSAgentSoftware/ConfigMgr-PXE-Boot-Log/master/PXEBoot.png)

