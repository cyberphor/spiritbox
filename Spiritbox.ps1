﻿$Config = Get-Content config.json | ConvertFrom-Json

filter Submit-Report {
    $Body = $input -join "," # convert ArrayListEnumeratorSimple to a String
    $Config.Subscribers |
    ForEach-Object {
        $Uri = "http://" + $_.ip + ":" + $_.port
        Invoke-RestMethod -Method POST -Uri $Uri -ContentType "application/json" -Body $Body  | 
        Out-Host
    }
    # TODO: include a Progress Bar dialog box
}

filter New-Report {
    $Report = [ordered]@{}
    $Form = $input.Controls | Where-Object { ($_ -isnot [System.Windows.Forms.Label]) -and ($_ -isnot [System.Windows.Forms.Button]) }

    # combine date and time; add an Elastic-friendly @timestamp value to the report
    $Date = $Form | Where-Object { $_.Name -eq "date" } | Select-Object -ExpandProperty Text
    $Time = $Form | Where-Object { $_.Name -eq "time" } | Select-Object -ExpandProperty Text  
    $Timestamp = $Date + "T" + $Time + ".000Z"
    $Report.Add("@timestamp", $Timestamp)

    # add the Location, Organization, and Activity observed to the report
    $Form | Where-Object { $_.Name -in ("geo.name", "organization.name", "threat.tactic.name") } | ForEach-Object { $Report.Add($_.Name, $_.Text) }

    # add the Attacker IP Address observed to the report
    if ([bool]$AttackerIPAddress.Text -as [ipaddress]) {
        $Report.Add($AttackerIPAddress, $_.Text)
    } else {
        Write-Host "An invalid IP address was specified."
        return
    }
    
    # add the Victim IP Address observed to the report
    if ([bool]$VictimIPAddress.Text -as [ipaddress]) {
        $Report.Add($VictimIPAddress , $_.Text)
    } else {
        Write-Host "An invalid IP address was specified."
        return
    } 

    # add the Actions Taken to the report
    $Form | Where-Object { $_.Name -eq "threat.response.description" } | ForEach-Object { $Report.Add($_.Name, $_.Text) }

    return $Report | ConvertTo-Json
}

function Clear-Form([System.Windows.Forms.Form]$Form) {
    $Form.Controls | 
    Where-Object { ($_ -isnot [System.Windows.Forms.Label]) -and ($_ -isnot [System.Windows.Forms.Button]) } |
    ForEach-Object {
        if ($_ -is [System.Windows.Forms.ComboBox]) {
            $_.Items.Clear() # TODO
        } else {
            $_.Clear()
        }
    }
}

function Show-Form {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
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
    $Config.Locations | ForEach-Object {[void]$LocationField.Items.Add($_)}
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
    $Config.Organizations | ForEach-Object {[void]$OrganizationField.Items.Add($_)}
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
    $Config.Activities | ForEach-Object {[void]$ActivityField.Items.Add($_)}
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
    $Config.Sources | ForEach-Object {[void]$SourceField.Items.Add($_)}
    $SourceField.SelectedIndex = 0
    $Form.Controls.Add($SourceField)

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
    $SubmitButton.Add_Click({$Form | New-Report | Submit-Report})
    $Form.Controls.Add($SubmitButton)

    # Cancel
    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.Size = New-Object System.Drawing.Size(200,25)
    $CancelButton.Location = New-Object System.Drawing.Point(190,440)
    $CancelButton.Add_Click({Clear-Form($Form)}) # TODO
    $Form.Controls.Add($CancelButton)

    $Form.ShowDialog()
}

Show-Form
# TODO: service
# TODO: send to system tray