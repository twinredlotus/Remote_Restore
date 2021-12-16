#Get launch parameters
Param (
    [Parameter(Mandatory = $False)]
    [ValidateNotNull()]
    [string]$Computer,
    [string]$Study
)
$Computer = 'Server'
$Study = 'Study'

$Date = Get-Date -UFormat %Y%m%d
$Time = (Get-Date).AddMinutes(5).ToString("HH:mm:ss")
$Time = $Time.replace(':', ' ')

#Declare enviornment variables
$env:PGPASSFILE = (Get-ItemProperty -Path HKLM:\SOFTWARE\Password\PostgreSQL).PgpassPath

#Declare global variables
$DEV = Get-Service | Where-Object { $_.Name -like "*DEV" } | Select-Object -ExpandProperty Name
$UAT = Get-Service | Where-Object { $_.Name -like "*UAT" } | Select-Object -ExpandProperty Name
$PROD = Get-Service | Where-Object { $_.Name -like "*PROD" } | Select-Object -ExpandProperty Name

#Postgresql
If (Test-Path 'C:\Program Files\PostgreSQL') {
    $psqlExe = 'C:\Program Files\PostgreSQL\9.5\bin\psql.exe'
    $pgDir = 'C:\Program Files\PostgreSQL\9.5\bin'
    $pgversion = 9
}
Else {
    $psqlExe = 'C:\Program Files (x86)\PostgreSQL\8.4\bin\psql.exe'
    $pgDir = 'C:\Program Files (x86)\PostgreSQL\8.4\bin'
    $pgversion = 8.4
}

Function Expand-Archive($File, $Destination) {
    $Shell = New-Object -Com Shell.Application
    $Zip = $Shell.NameSpace($File)
    ForEach ($Item in $Zip.Items()) {
        $Shell.Namespace($Destination).CopyHere($Item)
    }
}

Function Compress-Archive($File, $Destination) {
    [Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
    [System.AppDomain]::CurrentDomain.GetAssemblies()
    $CompressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    $IncludeBaseDir = $False
    [System.IO.Compression.ZipFile]::CreateFromDirectory($File, $Destination, $CompressionLevel, $IncludeBaseDir)
}
#Create powersehll accesible drive
New-PSDrive -Name "Y" -PSProvider "FileSystem" -Root "\\$Computer\c$\OC\backup"

#Start Main Procedure
#Using DEV Instance to perform restore task
Stop-Service -Name $DEV
Copy-Item -Path "Y:\*$Study`_PROD_$Date*" -Destination "C:\OC\Restore\REMOTE_RESTORE.zip" 
Expand-Archive "C:\OC\Restore\REMOTE_RESTORE.zip" -Destination "C:\OC\Restore" 
Copy-Item -Path "C:\OC\Restore\REMOTE_RESTORE\*.data" -Destination "C:\OC\Tomcat_DEV\REMOTE_RESTORE.data"
$Database = "remote_restore"
$Restore = "C:\oc\Restore\REMOTE_RESTORE\*.sql"
& $psqlExe -U postgres -c "DROP DATABASE $Database;"
& $psqlExe -U postgres -c "CREATE DATABASE $Database WITH ENCODING='UTF8' OWNER=owner;"
& $psqlExe -U postgres -d $Database -f $Restore

#Edit datainfo.properties file to run reports shortly after the webserver comes back up. 
$DataFile = "C:\OC\Tomcat_DEV\remote_restore.data\datainfo.properties"
$Temp = Get-Content -Path $DataFile`.FullName | Select-String 'report_run_time = 12 15 00' -SimpleMatch
(Get-Content -Path $DataFiles`.FullName) -Replace [regex]::Escape($Temp), "report_run_time = $Time" | Set-Content -Path $DataFiles`.FullName
Copy-Item -Path "C:\OC\Tomcat_DEV\remote_restore.data\datainfo.properties" -Destination "C:\OC\Tomcat_DEV\webapps\REMOTE_RESTORE\WEB-INF\classes\datainfo.properties"
Start-Service -Name $DEV

#Add to fileserver
Compress-Archive "C:\remote_restore.data\reports" -Destination "C:\remote_restore.data\$Study_$Data`_Reports.zip"
Copy-Item -Path "C:\remote_restore.data\$Study_$Data`_Reports.zip" -Destination "\\fileserver\N\_IAM\WVEDC_Reports"

#Cleanup
Remove-PSDrive -Name "Y"
Remove-Item -Path "C:\OC\Restore\REMOTE_RESTORE.zip", "C:\OC\Restore\REMOTE_RESTORE", "C:\remote_restore.data\$Study_$Data`_Reports.zip"