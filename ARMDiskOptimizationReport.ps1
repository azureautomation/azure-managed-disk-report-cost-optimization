#############################################################################
#                                     			 		                    #
#   This Sample Code is provided for the purpose of illustration only       #
#   and is not intended to be used in a production environment.  THIS       #
#   SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT    #
#   WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT    #
#   LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS     #
#   FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free    #
#   right to use and modify the Sample Code and to reproduce and distribute #
#   the object code form of the Sample Code, provided that You agree:       #
#   (i) to not use Our name, logo, or trademarks to market Your software    #
#   product in which the Sample Code is embedded; (ii) to include a valid   #
#   copyright notice on Your software product in which the Sample Code is   #
#   embedded; and (iii) to indemnify, hold harmless, and defend Us and      #
#   Our suppliers from and against any claims or lawsuits, including        #
#   attorneys' fees, that arise or result from the use or distribution      #
#   of the Sample Code.                                                     #
#                                     			 		                    #
#   Version 1.0                              			 	                #
#   Last Update Date: 6 June 2019                           	            #
#                                     			 		                    #
#############################################################################

<#
.Synopsis
   Azure managed Disk optimization report. The script will identify and Map Azure Managedisk to OS disk. It can also give a recommendation on Drive space based on Sku and sizing. Pricing might not be accurate and can be updated via 
   https://azure.microsoft.com/en-us/pricing/details/managed-disks/. Pricing is shown in US dollars

.DESCRIPTION
   Azure managed Disk optimization report. The script will identify and Map Azure Managedisk to OS disk. It can also give a recommendation on Drive space based on Sku and sizing. Pricing might not be accurate and can be updated via 
   https://azure.microsoft.com/en-us/pricing/details/managed-disks/. Pricing is shown in US dollars. Execution location must be able to connect to MACHINES in Azure using port 5985 "Remote Powershell"

.EXAMPLE
    This Example shows how to execute the command with default parameters
   .\ARMDiskOptimizationReport.ps1 

.EXAMPLE
    This Example shows how to execute the command with a Threshold of 35 . 35 Represent Percent left free for recommendation. Max is 99
   .\ARMDiskOptimizationReport.ps1 -ThreshHold 35 

.EXAMPLE
  This Example shows how to execute report with non-default export path
  .\ARMDiskOptimizationReport.ps1 -Filepath 'C:\temp\Azurediskreport.csv'
   
.EXAMPLE
  This Example shows how to start report without recommendations on OS drives.
  .\ARMDiskOptimizationReport.ps1 -ExcludeOSDrive

.EXAMPLE
 This Example show how to execute command with all parameters. Changes recommendation threshold,Default output path and exclude OS drives
  .\ARMDiskOptimizationReport.ps1 -ThreshHold 35 -Filepath 'C:\temp\Azurediskreport.csv'  -ExcludeOSDrive

.PARAMETER ThreshHold
 Set the percent free required for drives size recommendation. Maximum is 99.

.PARAMETER Filepath
 The parameter changes the default output path, By default report will be located in execution path.
   

.PARAMETER ExcludeOSDrive
 The parameter is a Switch to excluded OS drive from recommendation

#>

#Requires -version 4
#Requires -module AzureRM.profile,AzureRM.Compute

Param([int]$ThreshHold=35,[SWITCH]$ExcludeOSDrive=$false,$FilePath='.\AzureDiskReport.csv')

Write-Host "For updating pricing please see :" -ForegroundColor Green -NoNewline
Write-Host "#https://azure.microsoft.com/en-us/pricing/details/managed-disks/    " -ForegroundColor Yellow 
Write-Host "The pricing also does not include discount rates for and should only be used for demo purposes." -ForegroundColor Green
#Login to ARM with Powershell, support MFA

Add-AzureRmAccount 

$Credentials = Get-Credential -Message "Please Provide credentials for remote Powershell connectivity" 

#region Functions
Function Sel-AzureSubscription
{
$ErrorActionPreference = 'SilentlyContinue'
$Menu = 0; 
$Subs = @(Get-AzureRmSubscription | select Name,ID,TenantId)
Write-Host "Please select the subscription you want to use" -ForegroundColor Green;
$Subs | %{Write-Host "[$($Menu)]" -ForegroundColor Cyan -NoNewline ;Write-host ". $($_.Name)";$Menu++;}
$selection = Read-Host "Please select the Subscription Number - Valid numbers are 0 - $($Subs.count -1)"
        If ($Subs.item($selection) -ne $null)
        {
        Select-AzureRmSubscription -SubscriptionName $subs[$selection].Name
        }
}


Function Get-DiskSku
{Param($StorageType,[int]$Size)
#https://azure.microsoft.com/en-us/pricing/details/managed-disks/
#Premium SSD Managed Disks
If ($StorageType -eq 'Premium_LRS')
{Switch ([int]$Size)
 {
    {$Size -lt 48}    {$Sku = [PSCustomObject]@{Sku = "P4";Sku_Discription =	"32 GiB	`$4.81	120	25 MB/second";Cost = 4.81};break}
    {$Size -lt 96}    {$Sku = [PSCustomObject]@{Sku = "P6";Sku_Discription =	"64 GiB	`$9.29	240	50 MB/second";Cost = 9.29};break}
    {$Size -lt 192}   {$Sku = [PSCustomObject]@{Sku = "P10";Sku_Discription =	"128 GiB	`$17.92	500	100 MB/second";Cost = 17.92};break}
    {$Size -lt 384}   {$Sku = [PSCustomObject]@{Sku = "P15";Sku_Discription =	"256 GiB	`$34.56	1,100	125 MB/second";Cost = 34.56};break}
    {$Size -lt 768}   {$Sku = [PSCustomObject]@{Sku = "P20";Sku_Discription =	"512 GiB	`$66.56	2,300	150 MB/second";Cost = 66.56};break}
    {$Size -lt 1536}  {$Sku = [PSCustomObject]@{Sku = "P30";Sku_Discription =	"1 TiB	`$122.88	5,000	200 MB/second";Cost = 122.88};break}
    {$Size -lt 3072}  {$Sku = [PSCustomObject]@{Sku = "P40";Sku_Discription =	"2 TiB	`$235.52	7,500	250 MB/second";Cost = 235.52};break}
    {$Size -lt 6144}  {$Sku = [PSCustomObject]@{Sku = "P50";Sku_Discription =	"4 TiB	`$450.56	7,500	250 MB/second";Cost = 450.56};break}
    {$Size -lt 12288} {$Sku = [PSCustomObject]@{Sku = "P60";Sku_Discription =	"8 TiB	`$430.08	12,500	480 MB/second";Cost = 430.08};break}
    {$Size -lt 24576} {$Sku = [PSCustomObject]@{Sku = "P70";Sku_Discription =	"16 TiB	`$819.20	15,000	750 MB/second";Cost = 819.20};break}
    {$Size -lt 49152} {$Sku = [PSCustomObject]@{Sku = "P80";Sku_Discription =	"32 TiB  `$1638.40 20,000 750 MB/second";Cost = 1638.40};break}
 }
}

#Standard SSD Managed Disks 
If ($StorageType -eq 'StandardSSD_LRS')
{Switch ([int]$Size)
 {
    {$Size -lt 48}    {$Sku = [PSCustomObject]@{Sku = "E4";Sku_Discription =	"32 GiB	`$2.40	Up to 120	Up to 25 MB/second";Cost = 2.40};break}
    {$Size -lt 96}    {$Sku = [PSCustomObject]@{Sku = "E6";Sku_Discription =	"64 GiB	`$4.80	Up to 240	Up to 50 MB/second";Cost = 4.80};break}
    {$Size -lt 192}   {$Sku = [PSCustomObject]@{Sku = "E10";Sku_Discription =	"128 GiB	`$9.60	Up to 500	Up to 60 MB/second";Cost = 9.60};break}
    {$Size -lt 384}   {$Sku = [PSCustomObject]@{Sku = "E15";Sku_Discription =	"256 GiB	`$19.20	Up to 500	Up to 60 MB/second";Cost = 19.20};break}
    {$Size -lt 768}   {$Sku = [PSCustomObject]@{Sku = "E20";Sku_Discription =	"512 GiB	`$38.40	Up to 500	Up to 60 MB/second";Cost = 38.40};break}
    {$Size -lt 1536}  {$Sku = [PSCustomObject]@{Sku = "E30";Sku_Discription =	"1 TiB	`$76.80	Up to 500	Up to 60 MB/second";Cost = 76.80};break}
    {$Size -lt 3072}  {$Sku = [PSCustomObject]@{Sku = "E40";Sku_Discription =	"2 TiB	`$153.60	Up to 500	Up to 60 MB/second";Cost = 153.60};break}
    {$Size -lt 6144}  {$Sku = [PSCustomObject]@{Sku = "E50";Sku_Discription =	"4 TiB	`$307.20	Up to 500	Up to 60 MB/second";Cost = 307.20};break}
    {$Size -lt 12288} {$Sku = [PSCustomObject]@{Sku = "E60";Sku_Discription =	"8 TiB	`$215.04	Up to 1,300	Up to 300 MB/second";Cost = 215.04};break}
    {$Size -lt 24576} {$Sku = [PSCustomObject]@{Sku = "E70";Sku_Discription =	"16 TiB	`$409.60	Up to 2,000	Up to 500 MB/second";Cost = 409.60};break}
    {$Size -lt 49152} {$Sku = [PSCustomObject]@{Sku = "E80";Sku_Discription =	"32 TiB `$819.20	Up to 2,000	Up to 500 MB/second";Cost = 819.20};break}
 }
}

#Standard HDD Managed Disks
If ($StorageType -eq 'Standard_LRS')
{
Switch ([int]$Size)
 {
    {$Size -lt 48}    {$Sku = [PSCustomObject]@{Sku = "S4"; Sku_Discription =	"32 GiB	`$1.54	Up to 500	Up to 60 MB/Second";Cost = 1.54};break}
    {$Size -lt 96}    {$Sku = [PSCustomObject]@{Sku = "S6"; Sku_Discription =   "64 GiB	`$3.01	Up to 500	Up to 60 MB/Second";Cost = 3.01};break}
    {$Size -lt 192}   {$Sku = [PSCustomObject]@{Sku = "S10";Sku_Discription =	"128 GiB	`$5.89	Up to 500	Up to 60 MB/Second";Cost = 5.89};break}
    {$Size -lt 384}   {$Sku = [PSCustomObject]@{Sku = "S15";Sku_Discription =	"256 GiB	`$11.33	Up to 500	Up to 60 MB/Second";Cost = 11.33};break}
    {$Size -lt 768}   {$Sku = [PSCustomObject]@{Sku = "S20";Sku_Discription =	"512 GiB	`$21.76	Up to 500	Up to 60 MB/Second";Cost = 21.76};break}
    {$Size -lt 1536}  {$Sku = [PSCustomObject]@{Sku = "S30";Sku_Discription =	"1 TiB	`$40.96	Up to 500	Up to 60 MB/Second";Cost = 40.96};break}
    {$Size -lt 3072}  {$Sku = [PSCustomObject]@{Sku = "S40";Sku_Discription =	"2 TiB	`$77.83	Up to 500	Up to 60 MB/Second";Cost = 77.83};break}
    {$Size -lt 6144}  {$Sku = [PSCustomObject]@{Sku = "S50";Sku_Discription =	"4 TiB	`$143.36	Up to 500	Up to 60 MB/Second";Cost = 143.36};break}
    {$Size -lt 12288} {$Sku = [PSCustomObject]@{Sku = "S60";Sku_Discription =	"8 TiB	`$131.08	Up to 1,300	Up to 300 MB/Second";Cost = 131.08};break}
    {$Size -lt 24576} {$Sku = [PSCustomObject]@{Sku = "S70";Sku_Discription =	"16 TiB	`$262.15	Up to 2,000	Up to 500 MB/Second";Cost = 262.15};break}
    {$Size -lt 49152} {$Sku = [PSCustomObject]@{Sku = "S80";Sku_Discription =	"2 TiB  `$524.29 Up to 2,000	Up to 500 MB/Second";Cost = 524.29};break}
 }
}
return $sku
}

#endregion functions

#Select Azure Subscription
Sel-AzureSubscription

#Set Variables
$VMs = Get-AzureRmVM           #Get all Azure ARM VM for select Subscription
$AzureDisks = Get-AzureRmDisk   #Get All Azure Managed Disk

$Disks = @{} #Hash Table for all disks
$VMsResult = @{}

Foreach ($dsk in $AzureDisks)
{
 $dsk_obj = @{
                ResourceGroupName = $dsk.ResourceGroupName
                ManagedBy = ($dsk.ManagedBy -split '/' )[-1]
                SkuName = $dsk.Sku.Name
                SkuTier = $dsk.Sku.Tier
                OsType = $dsk.OsType
                DiskSizeGB = $dsk.DiskSizeGB
                DiskIOPSReadWrite = $dsk.DiskIOPSReadWrite
                DiskMBpsReadWrite = $dsk.DiskMBpsReadWrite
                Name = $dsk.Name
                Location = $dsk.Location
                Lun = '' 
                WinSize = ''
                FreeSpace = ''
                VolumeName = ''
                DeviceID = ''
             }
$Disks."$($dsk.Name)" = $dsk_obj #Update the Hash table
}


Foreach ($Vm in $VMs)
{   
        Write-Host "Checking $($VM.Name)....." -ForegroundColor Cyan -NoNewline
        if ((Test-Connection -ComputerName $Vm.Name -Count 1 -ErrorAction SilentlyContinue).StatusCode -eq 0)
        {
        Write-Host "Success" -ForegroundColor Green 
        Write-Host "Attempting Retrieving Windows Disks......" -ForegroundColor Green

        $CMD = {
                Function Get-WMIDrives
                    {
                    $Drives = @()
                    $Win =@{}
                    $DiskDrive = gwmi -Class Win32_DiskDrive | Select PNPDeviceID,size,InterfaceType,DeviceID,__PATH
                    $DrivetoPartition = gwmi -Class Win32_DiskDriveToDiskPartition | Select Antecedent,Dependent
                    $LogicaltoPartition = gwmi -Class Win32_LogicalDiskToPartition | Select Antecedent,Dependent
                    
                    Get-WmiObject -Class win32_logicaldisk |%{ $Win."$($_.DeviceID)" = [PSCustomObject]@{DeviceID = $_.DeviceID;FreeSpace = $_.FreeSpace;VolumeName = $_.VolumeName;Size = $_.Size}}
                    
                       foreach ($Dsk in $DiskDrive)
                            {
                            $DeviceID =  ( ($DrivetoPartition |?{$_.Antecedent -eq $Dsk.__Path ; $D = $_} | %{ $LogicaltoPartition |?{$_.Antecedent -eq $D.Dependent} | select Dependent} ) -split [char]34)[-2]
                            $Drives += [PSCustomObject]@{
                                                            ComputerName = $env:COMPUTERNAME
                                                            LUN = ($Dsk.PNPDeviceID -split '\\')[-1]
                                                            Size = [Math]::Round($Dsk.Size / 1GB,2)
                                                            DeviceID = $DeviceID 
                                                            FreeSpace = [Math]::Round($Win.$DeviceID.FreeSpace / 1GB,2)
                                                            VolumeName = $Win.$DeviceID.VolumeName
                                                            InterfaceType = $Dsk.InterfaceType
                                                            }
                            }
                    Return $Drives
                    }
         Get-WMIDrives
        }
        $Win_Drives = @(Invoke-Command -ComputerName $VM.Name -Credential $Credentials -ScriptBlock $CMD -ErrorAction SilentlyContinue -ErrorVariable $Conerr)
        
        Foreach ($Rs_dsk in @($Vm.StorageProfile.DataDisks))
        {
                If ($Disks.ContainsKey("$($Rs_dsk.Name)"))
                {
                try{
                $D = ($Win_Drives |?{ $_.InterfaceType -eq 'SCSI'} | ?{[int]$_.Lun -eq [int]($Rs_dsk.Lun)})
                }Catch{}
                
                $Disks."$($Rs_dsk.Name)".Lun = $Rs_dsk.Lun
                $Disks."$($Rs_dsk.Name)".WinSize = $D.Size
                $Disks."$($Rs_dsk.Name)".FreeSpace =  $D.FreeSpace
                $Disks."$($Rs_dsk.Name)".VolumeName = $D.VolumeName
                $Disks."$($Rs_dsk.Name)".DeviceID = $D.DeviceID

                }
        }

        Foreach ($Rs_dsk in @($Vm.StorageProfile.OSDisk))
        {
                If ($Disks.ContainsKey("$($Rs_dsk.Name)"))
                {
                $D = ($Win_Drives |?{ $_.InterfaceType -eq 'IDE' -and $_.VolumeName -ne 'Temporary Storage'} )
                $Disks."$($Rs_dsk.Name)".Lun = $Rs_dsk.Lun
                $Disks."$($Rs_dsk.Name)".WinSize = $D.Size
                $Disks."$($Rs_dsk.Name)".FreeSpace =  $D.FreeSpace
                $Disks."$($Rs_dsk.Name)".VolumeName = $D.VolumeName
                $Disks."$($Rs_dsk.Name)".DeviceID = $D.DeviceID

                }
        }
        }else
        {
        Write-Host "Unable to Ping" -ForegroundColor Yellow 
        }
}


$Report = @()
ForEach ($i in $Disks.Keys)
{
  
    If ($i.OSType.length -lt 2 -xor ($ExcludeOSDrive))
    {
    $Obj = [PSCustomObject]$Disks.$i 
        [int]$UsedSpace = [int]$Obj.DiskSizeGB - [int]$Obj.FreeSpace
        $Current = Get-DiskSku -StorageType $Obj.SkuName -Size $Obj.DiskSizeGB
        $Adj = Get-DiskSku -StorageType $Obj.SkuName -Size ($UsedSpace * "0.$ThreshHold" + $UsedSpace)
            $Obj | Add-Member -MemberType NoteProperty -Name StorageSku -Value $Current.SKu
            $Obj | Add-Member -MemberType NoteProperty -Name SkuDescription -Value $Current.Sku_Discription
            $Obj | Add-Member -MemberType NoteProperty -Name Cost -Value $Current.Cost
            $Obj | Add-Member -MemberType NoteProperty -Name AdjustedSku -Value $Adj.SKu
            $Obj | Add-Member -MemberType NoteProperty -Name Adjusted_SkuDescription -Value $Adj.Sku_Discription
            $Obj | Add-Member -MemberType NoteProperty -Name Adjusted_Cost -Value $Adj.Cost
            $Obj | Add-Member -MemberType NoteProperty -Name Saving -Value ([int]$Current.Cost - [int]$Adj.Cost)
    $Report += $Obj
    }Else
    {
        $Obj = [PSCustomObject]$Disks.$i 
        [int]$UsedSpace = [int]$Obj.DiskSizeGB - [int]$Obj.FreeSpace
        $Current = Get-DiskSku -StorageType $Obj.SkuName -Size $Obj.DiskSizeGB
        
            $Obj | Add-Member -MemberType NoteProperty -Name StorageSku -Value $Current.SKu
            $Obj | Add-Member -MemberType NoteProperty -Name SkuDescription -Value $Current.Sku_Discription
            $Obj | Add-Member -MemberType NoteProperty -Name Cost -Value $Current.Cost
            $Obj | Add-Member -MemberType NoteProperty -Name AdjustedSku -Value $Current.SKu
            $Obj | Add-Member -MemberType NoteProperty -Name Adjusted_SkuDescription -Value $Current.Sku_Discription
            $Obj | Add-Member -MemberType NoteProperty -Name Adjusted_Cost -Value $Current.Cost
            $Obj | Add-Member -MemberType NoteProperty -Name Saving -Value ([int]$Current.Cost - [int]$Current.Cost)
    $Report += $Obj
    }
}

$Report | Export-csv $FilePath -NoClobber -NoTypeInformation









