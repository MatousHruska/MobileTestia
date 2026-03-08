Attribute VB_Name = "ZoneMoodDatabase"
'===============================================================================
' ZoneMoodDatabase Module
' Handles validation and export for ZoneMoods (atmosphere presets for zones)
' Each mood defines ambient color, bloom, and particle settings.
' Zones reference moods via mood_id foreign key.
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_ZONE_MOODS As String = "ZoneMoods"

' Column indices for ZoneMoods (1-based)
Private Const COL_ZM_ID As Integer = 1
Private Const COL_ZM_NAME As Integer = 2
Private Const COL_ZM_AMBIENT_COLOR As Integer = 3
Private Const COL_ZM_BLOOM_ENABLED As Integer = 4
Private Const COL_ZM_BLOOM_INTENSITY As Integer = 5
Private Const COL_ZM_BLOOM_THRESHOLD As Integer = 6
Private Const COL_ZM_PARTICLE_TYPE As Integer = 7
Private Const COL_ZM_PARTICLE_TINT As Integer = 8
Private Const COL_ZM_SHADOW_ANGLE As Integer = 9
Private Const COL_ZM_SHADOW_OPACITY As Integer = 10

' Valid dropdown values
Private validParticleTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validParticleTypes = Split("snow,dust_motes,embers", ",")
End Sub

'===============================================================================
' ZONE MOODS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateZoneMoods - Validates all rows in ZoneMoods sheet
'-------------------------------------------------------------------------------
Public Sub ValidateZoneMoods()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ZONE_MOODS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ZONE_MOODS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ZM_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ZM_ID).Value)

        If Len(id) = 0 Then GoTo NextMood

        ' Validate ID format
        If Not ValidateId(id, "mood_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: mood_type_name (e.g., mood_outdoor_meadow)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_ZM_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate ambient_color format (#RRGGBB)
        Dim ambientColor As String
        ambientColor = Trim(ws.Cells(i, COL_ZM_AMBIENT_COLOR).Value)
        If Len(ambientColor) > 0 Then
            If Left(ambientColor, 1) <> "#" Or Len(ambientColor) <> 7 Then
                LogValidationError errors, errorCount, i, "Ambient Color", _
                    "Must be hex format #RRGGBB (e.g., #BAA890)"
            End If
        End If

        ' Validate bloom_intensity range (0.0 - 2.0)
        Dim bloomIntensity As Double
        bloomIntensity = GetDefaultNumeric(ws.Cells(i, COL_ZM_BLOOM_INTENSITY), 0.8)
        If bloomIntensity < 0 Or bloomIntensity > 2 Then
            LogValidationError errors, errorCount, i, "Bloom Intensity", _
                "Must be between 0.0 and 2.0"
        End If

        ' Validate bloom_threshold range (0.0 - 1.0)
        Dim bloomThreshold As Double
        bloomThreshold = GetDefaultNumeric(ws.Cells(i, COL_ZM_BLOOM_THRESHOLD), 0.7)
        If bloomThreshold < 0 Or bloomThreshold > 1 Then
            LogValidationError errors, errorCount, i, "Bloom Threshold", _
                "Must be between 0.0 and 1.0"
        End If

        ' Validate particle_type (optional enum)
        Dim particleType As String
        particleType = LCase(Trim(ws.Cells(i, COL_ZM_PARTICLE_TYPE).Value))
        If Len(particleType) > 0 And Not ValidateDropdown(particleType, validParticleTypes) Then
            LogValidationError errors, errorCount, i, "Particle Type", _
                "Invalid type. Valid: snow, dust_motes, embers (or leave empty)"
        End If

        ' Validate particle_tint format (#RRGGBB)
        Dim particleTint As String
        particleTint = Trim(ws.Cells(i, COL_ZM_PARTICLE_TINT).Value)
        If Len(particleTint) > 0 Then
            If Left(particleTint, 1) <> "#" Or Len(particleTint) <> 7 Then
                LogValidationError errors, errorCount, i, "Particle Tint", _
                    "Must be hex format #RRGGBB (e.g., #FFE6B3)"
            End If
        End If

        ' Validate shadow_angle range (-3.14 to 3.14)
        Dim shadowAngle As Double
        shadowAngle = GetDefaultNumeric(ws.Cells(i, COL_ZM_SHADOW_ANGLE), 0.5)
        If shadowAngle < -3.14 Or shadowAngle > 3.14 Then
            LogValidationError errors, errorCount, i, "Shadow Angle", _
                "Must be between -3.14 and 3.14 (radians)"
        End If

        ' Validate shadow_opacity range (0.0 to 1.0)
        Dim shadowOpacity As Double
        shadowOpacity = GetDefaultNumeric(ws.Cells(i, COL_ZM_SHADOW_OPACITY), 0.3)
        If shadowOpacity < 0 Or shadowOpacity > 1 Then
            LogValidationError errors, errorCount, i, "Shadow Opacity", _
                "Must be between 0.0 and 1.0"
        End If

NextMood:
    Next i

    ShowValidationResults errors, errorCount, "ZoneMoods"
End Sub

'-------------------------------------------------------------------------------
' ExportZoneMoodsData - Exports ZoneMoods to JSON
'-------------------------------------------------------------------------------
Public Sub ExportZoneMoodsData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ZONE_MOODS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ZONE_MOODS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""zone_moods"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ZM_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ZM_ID).Value)

        If Len(id) = 0 Then GoTo NextExportMood

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Handle boolean fields
        Dim bloomEnabled As String
        bloomEnabled = LCase(Trim(ws.Cells(i, COL_ZM_BLOOM_ENABLED).Value))
        If bloomEnabled = "true" Or bloomEnabled = "1" Or bloomEnabled = "yes" Then
            bloomEnabled = "true"
        Else
            bloomEnabled = "false"
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(Trim(GetDefaultString(ws.Cells(i, COL_ZM_NAME)))) & """," & vbCrLf
        json = json & "      ""ambient_color"": """ & EscapeJsonString(Trim(GetDefaultString(ws.Cells(i, COL_ZM_AMBIENT_COLOR), "#CCBBAA"))) & """," & vbCrLf
        json = json & "      ""bloom_enabled"": " & bloomEnabled & "," & vbCrLf
        json = json & "      ""bloom_intensity"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZM_BLOOM_INTENSITY), 0.8)) & "," & vbCrLf
        json = json & "      ""bloom_threshold"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZM_BLOOM_THRESHOLD), 0.7)) & "," & vbCrLf
        json = json & "      ""particle_type"": """ & EscapeJsonString(Trim(LCase(GetDefaultString(ws.Cells(i, COL_ZM_PARTICLE_TYPE))))) & """," & vbCrLf
        json = json & "      ""particle_tint"": """ & EscapeJsonString(Trim(GetDefaultString(ws.Cells(i, COL_ZM_PARTICLE_TINT), "#FFFFFF"))) & """," & vbCrLf
        json = json & "      ""shadow_angle"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZM_SHADOW_ANGLE), 0.5)) & "," & vbCrLf
        json = json & "      ""shadow_opacity"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZM_SHADOW_OPACITY), 0.3)) & "" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportMood:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "zone_moods.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " zone moods to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupZoneMoodsSheet - Creates ZoneMoods sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupZoneMoodsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_ZONE_MOODS)

    Dim headers As Variant
    headers = Array("id", "name", "ambient_color", "bloom_enabled", "bloom_intensity", _
                    "bloom_threshold", "particle_type", "particle_tint", _
                    "shadow_angle", "shadow_opacity")

    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: mood_type_name (e.g., mood_outdoor_meadow, mood_cave_deep)"
    SafeAddComment ws.Cells(1, 2), "Display name for this mood preset"
    SafeAddComment ws.Cells(1, 3), "Ambient light tint as hex #RRGGBB (e.g., #BAA890 warm sunlight, #181822 dark cave)"
    SafeAddComment ws.Cells(1, 4), "TRUE/FALSE - enable bloom/glow effect"
    SafeAddComment ws.Cells(1, 5), "Bloom strength 0.0-2.0 (0.3=subtle, 1.0=strong)"
    SafeAddComment ws.Cells(1, 6), "Bloom brightness threshold 0.0-1.0 (0.9=only very bright areas glow)"
    SafeAddComment ws.Cells(1, 7), "Particle effect: snow, dust_motes, embers (or leave empty for none)"
    SafeAddComment ws.Cells(1, 8), "Particle color tint as hex #RRGGBB (e.g., #FFE6B3 warm dust)"
    SafeAddComment ws.Cells(1, 9), "Shadow sun angle in radians -3.14 to 3.14 (0.5=default right-ish, default 0.5)"
    SafeAddComment ws.Cells(1, 10), "Shadow opacity 0.0-1.0 (0=invisible, 0.3=subtle, 1.0=solid black, default 0.3)"

    MsgBox "ZoneMoods sheet setup complete!", vbInformation
End Sub
