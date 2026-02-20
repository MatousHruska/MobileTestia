Attribute VB_Name = "LocationDatabase"
'===============================================================================
' LocationDatabase Module
' Handles validation and export for Locations (sub-areas within Zones)
' Locations can override Zone settings for safety, effects, music, etc.
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_LOCATIONS As String = "Locations"

' Column indices (1-based)
Private Const COL_LOC_ID As Integer = 1
Private Const COL_LOC_ZONE_ID As Integer = 2
Private Const COL_LOC_NAME As Integer = 3
Private Const COL_LOC_LOCATION_TYPE As Integer = 4
Private Const COL_LOC_IS_SAFE_ZONE As Integer = 5
Private Const COL_LOC_IS_PVP_ENABLED As Integer = 6
Private Const COL_LOC_STATUS_EFFECT_ID As Integer = 7
Private Const COL_LOC_MUSIC_TRACK As Integer = 8
Private Const COL_LOC_AMBIENT_SOUND As Integer = 9
Private Const COL_LOC_DISCOVERY_POPUP As Integer = 10
Private Const COL_LOC_DESCRIPTION As Integer = 11

' Valid dropdown values
Private validLocationTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validLocationTypes = Split("town,camp,poi,dungeon_entrance,quest_area,danger_zone,sanctuary,boss_arena,secret_area", ",")
End Sub

'-------------------------------------------------------------------------------
' GetValidLocationTypes - Returns valid location types for external use
'-------------------------------------------------------------------------------
Public Function GetValidLocationTypes() As String
    GetValidLocationTypes = "town,camp,poi,dungeon_entrance,quest_area,danger_zone,sanctuary,boss_arena,secret_area"
End Function

'-------------------------------------------------------------------------------
' ValidateLocations - Validates all rows in Locations sheet
'-------------------------------------------------------------------------------
Public Sub ValidateLocations()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOCATIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOCATIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_LOC_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_LOC_ID).value)

        If Len(id) = 0 Then GoTo NextLocation

        ' Validate ID format
        If Not ValidateId(id, "loc_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: loc_name (e.g., loc_northshire_abbey)"
        End If

        ' Validate zone_id not empty and has correct prefix
        Dim zoneId As String
        zoneId = Trim(ws.Cells(i, COL_LOC_ZONE_ID).value)
        If Len(zoneId) = 0 Then
            LogValidationError errors, errorCount, i, "Zone ID", "Zone ID is required"
        ElseIf Not ValidateId(zoneId, "zone_") Then
            LogValidationError errors, errorCount, i, "Zone ID", _
                "Invalid Zone ID format. Use: zone_name (e.g., zone_meadow)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_LOC_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate location type
        Dim locType As String
        locType = LCase(Trim(ws.Cells(i, COL_LOC_LOCATION_TYPE).value))
        If Len(locType) > 0 And Not ValidateDropdown(locType, validLocationTypes) Then
            LogValidationError errors, errorCount, i, "Location Type", _
                "Invalid type. Valid: town, camp, poi, dungeon_entrance, quest_area, danger_zone, sanctuary, boss_arena, secret_area"
        End If

        ' Validate status_effect_id format if provided
        Dim statusEffectId As String
        statusEffectId = Trim(ws.Cells(i, COL_LOC_STATUS_EFFECT_ID).value)
        If Len(statusEffectId) > 0 And Not ValidateId(statusEffectId, "status_") Then
            LogValidationError errors, errorCount, i, "Status Effect ID", _
                "Invalid Status Effect ID format. Use: status_name (e.g., status_blizzard)"
        End If

NextLocation:
    Next i

    ShowValidationResults errors, errorCount, "Locations"
End Sub

'-------------------------------------------------------------------------------
' ExportLocations - Exports Locations to JSON
'-------------------------------------------------------------------------------
Public Sub ExportLocations()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOCATIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOCATIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""locations"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_LOC_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_LOC_ID).value)

        If Len(id) = 0 Then GoTo NextExportLocation

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Handle boolean fields - empty means "inherit from zone" (null in JSON)
        Dim isSafeZone As String
        Dim isSafeZoneVal As String
        isSafeZoneVal = LCase(Trim(ws.Cells(i, COL_LOC_IS_SAFE_ZONE).value))
        If Len(isSafeZoneVal) = 0 Then
            isSafeZone = "null"
        ElseIf isSafeZoneVal = "true" Or isSafeZoneVal = "1" Or isSafeZoneVal = "yes" Then
            isSafeZone = "true"
        Else
            isSafeZone = "false"
        End If

        Dim isPvpEnabled As String
        Dim isPvpEnabledVal As String
        isPvpEnabledVal = LCase(Trim(ws.Cells(i, COL_LOC_IS_PVP_ENABLED).value))
        If Len(isPvpEnabledVal) = 0 Then
            isPvpEnabled = "null"
        ElseIf isPvpEnabledVal = "true" Or isPvpEnabledVal = "1" Or isPvpEnabledVal = "yes" Then
            isPvpEnabled = "true"
        Else
            isPvpEnabled = "false"
        End If

        Dim discoveryPopup As String
        Dim discoveryPopupVal As String
        discoveryPopupVal = LCase(Trim(ws.Cells(i, COL_LOC_DISCOVERY_POPUP).value))
        If discoveryPopupVal = "true" Or discoveryPopupVal = "1" Or discoveryPopupVal = "yes" Then
            discoveryPopup = "true"
        Else
            discoveryPopup = "false"
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""zone_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_ZONE_ID))) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_NAME))) & """," & vbCrLf
        json = json & "      ""location_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_LOC_LOCATION_TYPE), "poi"))) & """," & vbCrLf
        json = json & "      ""is_safe_zone"": " & isSafeZone & "," & vbCrLf
        json = json & "      ""is_pvp_enabled"": " & isPvpEnabled & "," & vbCrLf
        json = json & "      ""status_effect_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_STATUS_EFFECT_ID))) & """," & vbCrLf
        json = json & "      ""music_track"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_MUSIC_TRACK))) & """," & vbCrLf
        json = json & "      ""ambient_sound"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_AMBIENT_SOUND))) & """," & vbCrLf
        json = json & "      ""discovery_popup"": " & discoveryPopup & "," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOC_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportLocation:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "locations.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " locations to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupLocationsSheet - Creates/updates the Locations sheet with headers and comments
'-------------------------------------------------------------------------------
Public Sub SetupLocationsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_LOCATIONS)

    Dim headers As Variant
    headers = Array("id", "zone_id", "name", "location_type", "is_safe_zone", "is_pvp_enabled", _
                    "status_effect_id", "music_track", "ambient_sound", "discovery_popup", "description")

    SetupSheetHeaders ws, headers

    ' Add comments to explain columns
    SafeAddComment ws.Cells(1, 1), "Format: loc_name (e.g., loc_northshire_abbey, loc_bandit_camp)"
    SafeAddComment ws.Cells(1, 2), "Parent zone ID (e.g., zone_meadow). Location inherits zone settings unless overridden."
    SafeAddComment ws.Cells(1, 3), "Display name shown to player"
    SafeAddComment ws.Cells(1, 4), "town, camp, poi, dungeon_entrance, quest_area, danger_zone, sanctuary, boss_arena, secret_area"
    SafeAddComment ws.Cells(1, 5), "true/false - Overrides zone setting. Leave empty to inherit from zone."
    SafeAddComment ws.Cells(1, 6), "true/false - Overrides zone setting. Leave empty to inherit from zone."
    SafeAddComment ws.Cells(1, 7), "Status effect applied while in location (e.g., status_blizzard). Overrides zone effect."
    SafeAddComment ws.Cells(1, 8), "Music track to play. Overrides zone music. Leave empty to inherit."
    SafeAddComment ws.Cells(1, 9), "Ambient sound to play. Overrides zone ambient. Leave empty to inherit."
    SafeAddComment ws.Cells(1, 10), "true/false - Show 'Discovered: Location Name' popup on first visit"
    SafeAddComment ws.Cells(1, 11), "Flavor text description of the location"

    ' Set column widths
    ws.Columns(1).ColumnWidth = 25  ' id
    ws.Columns(2).ColumnWidth = 18  ' zone_id
    ws.Columns(3).ColumnWidth = 25  ' name
    ws.Columns(4).ColumnWidth = 18  ' location_type
    ws.Columns(5).ColumnWidth = 12  ' is_safe_zone
    ws.Columns(6).ColumnWidth = 14  ' is_pvp_enabled
    ws.Columns(7).ColumnWidth = 20  ' status_effect_id
    ws.Columns(8).ColumnWidth = 18  ' music_track
    ws.Columns(9).ColumnWidth = 18  ' ambient_sound
    ws.Columns(10).ColumnWidth = 14 ' discovery_popup
    ws.Columns(11).ColumnWidth = 40 ' description

    MsgBox "Locations sheet setup complete!", vbInformation
End Sub
