function UCSPending {

 #start of doing work
 <#
 .notes
Possible improvements
1.  Have the script break if vmhost is not in Maintenance mode
2.  Fix percentage issue, it's not accurate, and not really needed.

Written By Caleb Eaton (try-rebooting on github)
 #>
 





$host.PrivateData.ErrorForegroundColor = 'black'
$host.PrivateData.ErrorBackgroundColor = 'Yellow'
################################
#                              #
#                              #
#      PRE CHECK               #
#                              #
################################

if (-not($defaultucs)){
throw "You are not connected to any UCS Domains, please reconnect and try again"
$WarningPreference = "Stop"

}elseif (-not($global:DefaultVIServers)){

throw "You are not connected to any Vcenters, please reconnect and try again"
$WarningPreference = "Stop"

}

################################
#                              #
#                              #
#      Gathering pending       #
#                              #
################################


$PendingReboot = Get-ucslsmaintack | ? {$_.OperState -match "waiting-for-user"} | select UCS, @{name = "Server";expr = { $_.DN.split('-')[2].split('/')[0] }} | sort UCS


$Pending = $PendingReboot | Out-GridView -Title "Select UCS blades to reboot" -OutputMode Multiple| foreach {
    $_.server
}

if ($PendingReboot) {
    $Arguments = @{
        UCS             = $UCS
        Server          = $Pending
    }
    



 #start of work
foreach ($Esxihost in $pending) {
$vmhost= Get-vmhost -name "$Esxihost*"
if (-not($vmhost)){
throw "$ESXihost is not in the vcenter you are connected to, please try again"
$WarningPreference = "Stop"
}
$vmhostcount = $vmhost.count
$vmhostpercentage = 100/$vmhostcount
$percentcomplete += $vmhostpercentage
Write-Progress -Activity "restarting host $($vmhost.name)" -Status "rebooting vmhost $($vmhost.name)" -PercentComplete $percentcomplete

#enter maintenance mode/evacuate
Set-VMhost $vmhost -State maintenance  -Confirm:$false | Out-Null

#previnting script if host is not in MM from going forward.  Leaving code up, for some reason this is stopping the script eventhough the server is in MM
#if ($vmhost.ConnectionState -notlike "Maintenance"){
#throw "$vmhost is not in Maintenace mode, stopping script."
#$WarningPreference = "Stop"
#}
#setting a variable UCSProfile for full name.
$ucsprofile = Get-UcsServiceProfile -Name $ESXihost
#Setting fault suppression for $Ucsprofile
            $Maint= $ucsprofile | Add-UcsFaultSuppressTask -ModifyPresent -Name "ESXiUpgrade" -SuppressPolicyName "defaut-server-maint"
            $Trigger = $Maint | Add-UcsTrigLocalSched -ModifyPresent -AdminState "untriggered" -Descr "" -PolicyOwner "local"
            $SetFault = $Trigger | Add-UcsTrigLocalAbsWindow -ModifyPresent -ConcurCap "unlimited" -Date (Get-Date -Format " MM/dd/yyyy HH:mm" | % {$_ -replace "/", "-"}) -ProcBreak "none" -ProcCap "unlimited" -TimeCap "00:02:00:00.0"

#Select the ACK to reboot
Get-UcsServiceProfile -Name $ESXihost | Get-UcsLsmaintAck | Set-UcsLsmaintAck -AdminState trigger-immediate -force

#wait for maintenance mode/evacuate
do {
    sleep 10
    $ConnectionState = (get-vmhost $vmhost).ConnectionState
}
while ($ConnectionState -eq "Connected")
#reboot vmhost
Restart-VMHost -VMHost $vmhost -Confirm:$false |Out-Null
#wait for not responding state
do {
    sleep 10
    $ConnectionState = (get-vmhost $vmhost).ConnectionState
}
while ($ConnectionState -eq "Maintenance")
#wait for maintenance mode state
do {
    sleep 10
    $ConnectionState = (get-vmhost $vmhost).ConnectionState
}
while ($ConnectionState -eq "NotResponding")
#exit maintenance mode
Set-VMhost $vmhost -State Connected -Confirm:$false | Out-Null
#Turning off Fault Suppression
$ucsprofilename = $ESXihost.name
Get-UcsFaultSuppressTask ESXiUpgrade | ? {$_.dn -like "*$ucsprofilename*"} |Remove-UcsFaultSuppressTask -confirm:$false -force | Out-Null



#wait for connected state
do {
    sleep 10
    $ConnectionState = (get-vmhost $vmhost).ConnectionState
}
while ($ConnectionState -eq "Maintenance")
}

$vmhostpercentage = ""
$percentcomplete = ""

}
#Set variables to null
$ucsprofile = ""
$Maint = ""
$Trigger = ""
$SetFault = ""
$ucsprofilename = ""

}
UCSPending