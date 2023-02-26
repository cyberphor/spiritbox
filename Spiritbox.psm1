﻿try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName WindowsFormsIntegration
    $Config = Get-Content config.json | ConvertFrom-Json
    $Icon = New-Object System.Drawing.Icon("$PSScriptRoot\ghost.ico")
} catch {
    Write-Host $_
    exit
}

function Show-SpiritboxLog {
    Get-ChildItem -Filter "spiritbox*.log" | 
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1 |
    Invoke-Item
}

function Write-SpiritboxEventLog {
    Param(
        [Parameter(Mandatory)][ValidateSet("DEBUG","INFORMATIONAL","NOTICE","WARNING","ERROR","CRITICAL","ALERT","EMERGENCY")]$Prefix,
        [Parameter(Mandatory)][string]$Message
    )
    $Date = Get-Date
    $Time = $Date.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") 
    $SpiritboxEventLog = "spiritbox-" + $Date.ToString("yyyy-MM-dd") + ".log"
    $SpiritboxEvent = $Time, $Prefix, $Message | ForEach-Object { "[" + $_ + "]" }
    $SpiritboxEvent -join " " | Out-File -Append -FilePath $SpiritboxEventLog
}

function Show-SpiritboxError {
    Param(
        [string]$Message
    )
    # TODO: add Spiritbox icon and make "Error" the label inside the dialog box
    $Button = [System.Windows.Forms.MessageBoxButtons]::OK
    $Icon = [System.Windows.Forms.MessageBoxIcon]::None
    [System.Windows.Forms.MessageBox]::Show($Message, "Error", $Button, $Icon) | Out-Null
}

filter Test-IPAddress {
    $Address = [string]$input
    try {
        return $Address -match ($PSObject = [ipaddress]$Address)
    } catch {
        return $false
    }
}

filter Submit-SpiritboxReport {
    $Body = $input -join "," # convert ArrayListEnumeratorSimple to a String
    if ($Body -ne $false) {
        # Progress Bar Form
        $Subscribers = $Config.Subscribers
        $ProgressBarForm = New-Object System.Windows.Forms.Form
        $ProgressBarForm.ClientSize = "240,120"
        $ProgressBarForm.Text = "Spiritbox"
        $ProgressBarForm.StartPosition = "CenterScreen"
        $ProgressBarForm.Icon = $Icon

        # Progress Bar
        $SystemDrawingSize = New-Object System.Drawing.Size
        $SystemDrawingSize.Width = 220
        $SystemDrawingSize.Height = 20
        $ProgressBar = New-Object System.Windows.Forms.ProgressBar
        $ProgressBar.Name = "Progress"
        $ProgressBar.Size = $SystemDrawingSize
        $ProgressBar.Left = 10
        $ProgressBar.Top = 10
        $ProgressBar.Style = "Blocks"
        $ProgressBar.Value = 0
        $ProgressBarForm.Controls.Add($ProgressBar)

        # Progress Bar Label
        $ProgressBarLabel = New-Object System.Windows.Forms.Label
        $ProgressBarLabel.Width = 220
        $ProgressBarLabel.Height = 60
        $ProgressBarLabel.Left = 10
        $ProgressBarLabel.Top = 35
        $ProgressBarForm.Controls.Add($ProgressBarLabel)

        # Loop
        $ProgressBarForm.Show() | Out-Null
        $ProgressBarForm.Focus() | Out-Null
        $i = 0
        $Subscribers |
        ForEach-Object {
            $ProgressBarLabel.Text = "Notifying: " + $_.Name
            Write-SpiritboxEventLog -Prefix INFORMATIONAL -Message $ProgressBarLabel.Text
            $ProgressBarForm.Refresh()
            Start-Sleep -Seconds 1
            try {
                $Uri = "http://" + $_.ip + ":" + $_.port
                $SubscriberResponse = Invoke-RestMethod -Method POST -Uri $Uri -ContentType "application/json" -Body $Body
                $Seconds = 1
                Write-SpiritboxEventLog -Prefix INFORMATIONAL -Message $SubscriberResponse
            } catch {
                $SubscriberResponse = $_
                $Seconds = 3
                Write-SpiritboxEventLog -Prefix ERROR -Message $SubscriberResponse
            }
            $i++
            [int]$Percent = ($i / $Subscribers.count) * 100
            $ProgressBar.Value = $Percent
            $ProgressBarLabel.Text = "Response: " + $SubscriberResponse
            $ProgressBarForm.Refresh()
            Start-Sleep -Seconds $Seconds
        }
        # TODO: add Cancel button to interrupt progress
        $ProgressBarForm.Close()
    }
}

function Reset-SpiritboxForm {
    Param(
        [System.Windows.Forms.Form]$Form
    )
    $Form.Controls | 
    Where-Object { 
        ($_ -isnot [System.Windows.Forms.Label]) -and 
        ($_ -isnot [System.Windows.Forms.Button])
    } |
    ForEach-Object {
        if ($_ -is [System.Windows.Forms.DateTimePicker]) { 
            $_.Value = Get-Date 
        } elseif ($_ -is [System.Windows.Forms.ComboBox]) {
            $_.SelectedIndex = 0
        } elseif ($_ -is [System.Windows.Forms.TextBox]) {
            $_.Clear()
        }
    }
    $Form.Refresh()
}

filter New-SpiritboxReport {
    # Report
    $Report = [ordered]@{}
    $ReportHasNoErrors = $true
    $Form = $input.Controls | Where-Object { ($_ -isnot [System.Windows.Forms.Label]) -and ($_ -isnot [System.Windows.Forms.Button]) }

    # combine date and time into an Elastic-friendly @timestamp value
    $Date = $Form | Where-Object { $_.Name -eq "date" } | Select-Object -ExpandProperty Text
    $Time = $Form | Where-Object { $_.Name -eq "time" } | Select-Object -ExpandProperty Text  
    $Timestamp = $Date + "T" + $Time + ".000Z"
    $Report.Add("threat.indicator.last_seen", $Timestamp)

    # add the Location, Organization, and Activity observed to the report
    $Form | Where-Object { $_.Name -in ("geo.name", "organization.name", "threat.tactic.name", "observer.type") } | ForEach-Object { $Report.Add($_.Name, $_.Text) }

    # add the Attacker IP Address observed to the report
    $AttackerIPAddress = $Form | Where-Object { $_.Name -eq "source.ip" }
    if ($AttackerIPAddress.Text | Test-IPAddress) {
        $Report.Add($AttackerIPAddress.Name, $AttackerIPAddress.Text)
    } else {
        $ReportHasNoErrors = $false
        if ($AttackerIPAddress.Text -eq "") {
            $Message = 'No IP address was specified for the "Attacker IP Address" field.'
        } else {
            $Message = "An invalid IP address was specified: " + $AttackerIPAddress.Text
        }
        Write-SpiritboxEventLog -Prefix ERROR -Message $Message
        Show-SpiritboxError -Message $Message
    }
    
    # add the Victim IP Address observed to the report
    $VictimIPAddress = $Form | Where-Object { $_.Name -eq "destination.ip" }
    if ($VictimIPAddress.Text | Test-IPAddress) {
        $Report.Add($VictimIPAddress.Name, $VictimIPAddress.Text)
    } else {
        $ReportHasNoErrors = $false
        if ($VictimIPAddress.Text -eq "") {
            $Message = 'No IP address was specified for the "Victim IP Address" field.'    
        } else {
            $Message = "An invalid IP address was specified: " + $VictimIPAddress.Text
        }
        Write-SpiritboxEventLog -Prefix ERROR -Message $Message
        Show-SpiritboxError -Message $Message
    } 

    # add the Actions Taken to the report
    $Form | Where-Object { $_.Name -eq "threat.response.description" } | ForEach-Object { $Report.Add($_.Name, $_.Text) }

    if ($ReportHasNoErrors) {
        $Report = $Report | ConvertTo-Json -Compress
        Write-SpiritboxEventLog -Prefix INFORMATIONAL -Message $Report
        return $Report
    } else {
        return $false
    }
}

function Show-SpiritboxForm {
    # Form
    $Form = New-Object System.Windows.Forms.Form
    $Form.ClientSize = "400,500" # Width: 400, Height: 500
    $Form.MaximizeBox = $false # disable maximizing
    $Form.FormBorderStyle = "Fixed3D" # disable resizing
    $Form.Text = "Spiritbox"
    $Form.Icon = New-Object System.Drawing.Icon("$PSScriptRoot\ghost.ico")
    $Form.StartPosition = "CenterScreen"

    # Date
    $DateLabel = New-Object System.Windows.Forms.Label
    $DateLabel.Text = "Date"
    $DateLabel.Size = New-Object System.Drawing.Size(120,25)
    $DateLabel.Location = New-Object System.Drawing.Point(10,10)
    $Form.Controls.Add($DateLabel)

    $DateField = New-Object System.Windows.Forms.DateTimePicker
    $DateField.Name = "date"
    $DateField.Size = New-Object System.Drawing.Size(260,25)
    $DateField.Location = New-Object System.Drawing.Point(130,10)
    $DateField.Format = [Windows.Forms.DateTimePickerFormat]::Custom 
    $DateField.CustomFormat = "yyyy-MM-dd"
    $Form.Controls.Add($DateField)

    # Time
    $TimeLabel = New-Object System.Windows.Forms.Label
    $TimeLabel.Text = "Time"
    $TimeLabel.Location = New-Object System.Drawing.Point(10,35)
    $Form.Controls.Add($TimeLabel)

    $TimeField = New-Object System.Windows.Forms.DateTimePicker
    $TimeField.Name = "time" 
    $TimeField.Size = New-Object System.Drawing.Size(260,25)
    $TimeField.Location = New-Object System.Drawing.Point(130,35)
    $TimeField.Format = [Windows.Forms.DateTimePickerFormat]::Custom 
    $TimeField.CustomFormat = "HH:mm:ss"
    $TimeField.ShowUpDown = $true
    $Form.Controls.Add($TimeField)
            
    # Location
    $LocationLabel = New-Object System.Windows.Forms.Label
    $LocationLabel.Text = "Location"
    $LocationLabel.Location = New-Object System.Drawing.Point(10,60)
    $Form.Controls.Add($LocationLabel)

    $LocationField = New-Object System.Windows.Forms.ComboBox
    $LocationField.Name = "geo.name"
    $LocationField.Size = New-Object System.Drawing.Size(260,25)
    $LocationField.Location = New-Object System.Drawing.Point(130,60)
    $Config.Locations | ForEach-Object {[void]$LocationField.Items.Add($_)} # void is used so no output is returned during each add
    $LocationField.SelectedIndex = 0
    $Form.Controls.Add($LocationField)

    # Organization
    $OrganizationLabel = New-Object System.Windows.Forms.Label
    $OrganizationLabel.Text = "Organization"
    $OrganizationLabel.Location = New-Object System.Drawing.Point(10,85)
    $Form.Controls.Add($OrganizationLabel)

    $OrganizationField = New-Object System.Windows.Forms.ComboBox
    $OrganizationField.Name = "organization.name"
    $OrganizationField.Size = New-Object System.Drawing.Size(260,25)
    $OrganizationField.Location = New-Object System.Drawing.Point(130,85)
    $Config.Organizations | ForEach-Object {[void]$OrganizationField.Items.Add($_)} # void is used so no output is returned during each add
    $OrganizationField.SelectedIndex = 0
    $Form.Controls.Add($OrganizationField)

    # Activity
    $ActivityLabel = New-Object System.Windows.Forms.Label
    $ActivityLabel.Text = "Activity"
    $ActivityLabel.Location = New-Object System.Drawing.Point(10,110)
    $Form.Controls.Add($ActivityLabel)

    $ActivityField = New-Object System.Windows.Forms.ComboBox
    $ActivityField.Name = "threat.tactic.name"
    $ActivityField.Size = New-Object System.Drawing.Size(260,25)
    $ActivityField.Location = New-Object System.Drawing.Point(130,110)
    $Config.Activities | ForEach-Object {[void]$ActivityField.Items.Add($_)} # void is used so no output is returned during each add
    $ActivityField.SelectedIndex = 0
    $Form.Controls.Add($ActivityField)

    # Source
    $SourceLabel = New-Object System.Windows.Forms.Label
    $SourceLabel.Text = "Source"
    $SourceLabel.Location = New-Object System.Drawing.Point(10,135)
    $Form.Controls.Add($SourceLabel)

    $SourceField = New-Object System.Windows.Forms.ComboBox
    $SourceField.Name = "observer.type"
    $SourceField.Size = New-Object System.Drawing.Size(260,25)
    $SourceField.Location = New-Object System.Drawing.Point(130,135)
    $Config.Sources | ForEach-Object {[void]$SourceField.Items.Add($_)} # void is used so no output is returned during each add
    $SourceField.SelectedIndex = 0
    $Form.Controls.Add($SourceField)

    # TODO: add DataGridView

    # Attacker IP Address
    $AttackerIPAddressLabel = New-Object System.Windows.Forms.Label
    $AttackerIPAddressLabel.Text = "Attacker IP Address"
    $AttackerIPAddressLabel.Size = New-Object System.Drawing.Size(120,20)
    $AttackerIPAddressLabel.Location = New-Object System.Drawing.Point(10,160)
    $Form.Controls.Add($AttackerIPAddressLabel)

    $AttackerIPAddressField = New-Object System.Windows.Forms.TextBox
    $AttackerIPAddressField.Name = "source.ip"
    $AttackerIPAddressField.Size = New-Object System.Drawing.Size(260,25)
    $AttackerIPAddressField.Location = New-Object System.Drawing.Point(130,160)
    $Form.Controls.Add($AttackerIPAddressField)

    # Victim IP Address
    $VictimIPAddressLabel = New-Object System.Windows.Forms.Label
    $VictimIPAddressLabel.Text = "Victim IP Address"
    $VictimIPAddressLabel.Location = New-Object System.Drawing.Point(10,185)
    $Form.Controls.Add($VictimIPAddressLabel)

    $VictimIPAddressField = New-Object System.Windows.Forms.TextBox
    $VictimIPAddressField.Name = "destination.ip"
    $VictimIPAddressField.Size = New-Object System.Drawing.Size(260,25)
    $VictimIPAddressField.Location = New-Object System.Drawing.Point(130,185)
    $Form.Controls.Add($VictimIPAddressField)

    # Actions Taken
    $ActionsTakenLabel = New-Object System.Windows.Forms.Label
    $ActionsTakenLabel.Text = "Actions Taken"
    $ActionsTakenLabel.Location = New-Object System.Drawing.Point(10,210)
    $Form.Controls.Add($ActionsTakenLabel)

    $ActionsTakenField = New-Object System.Windows.Forms.TextBox
    $ActionsTakenField.Name = "threat.response.description"
    $ActionsTakenField.Size = New-Object System.Drawing.Size(380,200)
    $ActionsTakenField.Location = New-Object System.Drawing.Point(10,235)
    $ActionsTakenField.Multiline = $true
    $ActionsTakenField.AcceptsReturn = $true
    $Form.Controls.Add($ActionsTakenField)

    # Submit
    $SubmitButton = New-Object System.Windows.Forms.Button
    $SubmitButton.Text = "Submit"
    $SubmitButton.Size = New-Object System.Drawing.Size(185,25)
    $SubmitButton.Location = New-Object System.Drawing.Point(10,440)
    $SubmitButton.Add_Click({
        $Form | New-SpiritboxReport | Submit-SpiritboxReport
        Reset-SpiritboxForm -Form $Form
    })
    $Form.Controls.Add($SubmitButton)

    # Reset
    $ResetButton = New-Object System.Windows.Forms.Button
    $ResetButton.Text = "Reset"
    $ResetButton.Size = New-Object System.Drawing.Size(200,25)
    $ResetButton.Location = New-Object System.Drawing.Point(190,440)
    $ResetButton.Add_Click({Reset-SpiritboxForm -Form $Form}) 
    $Form.Controls.Add($ResetButton)

    # show form
    $Form.ShowDialog() | Out-Null # send dialog output (e.g., which button was pressed) to null
}

function Start-Spiritbox {
    # notify icon
    $NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $NotifyIcon.Text = "Spiritbox"
    $NotifyIcon.Icon = $Icon
    $NotifyIcon.ContextMenu = New-Object System.Windows.Forms.ContextMenu

    # new Spiritbox Report menu item
    $NewReport = New-Object System.Windows.Forms.MenuItem
    $NewReport.Enabled = $true
    $NewReport.Text = "New Report"
    $NewReport.Add_Click({Show-SpiritboxForm})
    $NotifyIcon.ContextMenu.MenuItems.AddRange($NewReport)

    # show Spiritbox Log menu item
    $ShowLog = New-Object System.Windows.Forms.MenuItem
    $ShowLog.Enabled = $true
    $ShowLog.Text = "Show Log"
    $ShowLog.Add_Click({Show-SpiritboxLog})
    $NotifyIcon.ContextMenu.MenuItems.AddRange($ShowLog)

    # stop Spiritbox menu item
    $StopSpiritbox = New-Object System.Windows.Forms.MenuItem
    $StopSpiritbox.Text = "Stop Spiritbox"
    $StopSpiritbox.Add_Click({$NotifyIcon.Dispose(); Stop-Process $pid})
    $NotifyIcon.ContextMenu.MenuItems.AddRange($StopSpiritbox)

    # show Spiritbox form and system tray icon
    $NotifyIcon.Visible = $true
    Show-SpiritboxForm
    $ApplicationContext = New-Object System.Windows.Forms.ApplicationContext
    [System.Windows.Forms.Application]::Run($ApplicationContext)
}
