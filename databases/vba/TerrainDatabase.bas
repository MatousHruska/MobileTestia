Attribute VB_Name = "TerrainDatabase"
'===============================================================================
' TerrainDatabase Module
' Handles validation and export for TerrainTypes (chunk-based map loading system)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_TERRAIN_TYPES As String = "TerrainTypes"

' Column indices for TerrainTypes (1-based)
Private Const COL_TT_ID As Integer = 1
Private Const COL_TT_NAME As Integer = 2
Private Const COL_TT_PLACEHOLDER_COLOR As Integer = 3
Private Const COL_TT_HAS_COLLISION As Integer = 4
Private Const COL_TT_MOVEMENT_COST As Integer = 5
Private Const COL_TT_FOOTSTEP_SOUND As Integer = 6
Private Const COL_TT_CAN_SPAWN_ON As Integer = 7

'===============================================================================
' TERRAIN TYPES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateTerrainTypes - Validates all rows in TerrainTypes sheet
'-------------------------------------------------------------------------------
Public Sub ValidateTerrainTypes()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TERRAIN_TYPES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TERRAIN_TYPES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TT_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TT_ID).Value)

        If Len(id) = 0 Then GoTo NextTerrainType

        ' Validate ID format (terrain_{name})
        If Not ValidateId(id, "terrain_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: terrain_name (e.g., terrain_grass)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_TT_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate placeholder_color is hex format
        Dim colorVal As String
        colorVal = Trim(ws.Cells(i, COL_TT_PLACEHOLDER_COLOR).Value)
        If Len(colorVal) > 0 Then
            If Left(colorVal, 1) <> "#" Or Len(colorVal) <> 7 Then
                LogValidationError errors, errorCount, i, "Placeholder Color", _
                    "Color must be hex format: #RRGGBB (e.g., #3d6e3d)"
            End If
        End If

        ' Validate movement_cost is positive
        Dim movementCost As Double
        movementCost = GetDefaultNumeric(ws.Cells(i, COL_TT_MOVEMENT_COST), 1)
        If movementCost < 0 Then
            LogValidationError errors, errorCount, i, "Movement Cost", _
                "Movement cost cannot be negative"
        End If

        ' Validate has_collision and can_spawn_on are valid booleans
        Dim hasCollision As String
        hasCollision = LCase(Trim(ws.Cells(i, COL_TT_HAS_COLLISION).Value))
        If Len(hasCollision) > 0 Then
            If hasCollision <> "true" And hasCollision <> "false" And _
               hasCollision <> "1" And hasCollision <> "0" And _
               hasCollision <> "yes" And hasCollision <> "no" Then
                LogValidationError errors, errorCount, i, "Has Collision", _
                    "Must be TRUE or FALSE"
            End If
        End If

        Dim canSpawnOn As String
        canSpawnOn = LCase(Trim(ws.Cells(i, COL_TT_CAN_SPAWN_ON).Value))
        If Len(canSpawnOn) > 0 Then
            If canSpawnOn <> "true" And canSpawnOn <> "false" And _
               canSpawnOn <> "1" And canSpawnOn <> "0" And _
               canSpawnOn <> "yes" And canSpawnOn <> "no" Then
                LogValidationError errors, errorCount, i, "Can Spawn On", _
                    "Must be TRUE or FALSE"
            End If
        End If

NextTerrainType:
    Next i

    ShowValidationResults errors, errorCount, "TerrainTypes"
End Sub

'-------------------------------------------------------------------------------
' ExportTerrainTypesData - Exports TerrainTypes to JSON
'-------------------------------------------------------------------------------
Public Sub ExportTerrainTypesData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TERRAIN_TYPES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TERRAIN_TYPES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""terrain_types"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TT_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TT_ID).Value)

        If Len(id) = 0 Then GoTo NextExportTerrainType

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Handle boolean has_collision field
        Dim hasCollision As String
        hasCollision = LCase(Trim(ws.Cells(i, COL_TT_HAS_COLLISION).Value))
        If hasCollision = "true" Or hasCollision = "1" Or hasCollision = "yes" Then
            hasCollision = "true"
        Else
            hasCollision = "false"
        End If

        ' Handle boolean can_spawn_on field
        Dim canSpawnOn As String
        canSpawnOn = LCase(Trim(ws.Cells(i, COL_TT_CAN_SPAWN_ON).Value))
        If canSpawnOn = "true" Or canSpawnOn = "1" Or canSpawnOn = "yes" Then
            canSpawnOn = "true"
        Else
            canSpawnOn = "false"
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_NAME))) & """," & vbCrLf
        json = json & "      ""placeholder_color"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_PLACEHOLDER_COLOR), "#808080")) & """," & vbCrLf
        json = json & "      ""has_collision"": " & hasCollision & "," & vbCrLf
        json = json & "      ""movement_cost"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TT_MOVEMENT_COST), 1)) & "," & vbCrLf
        json = json & "      ""footstep_sound"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_FOOTSTEP_SOUND))) & """," & vbCrLf
        json = json & "      ""can_spawn_on"": " & canSpawnOn & "" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportTerrainType:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "terrain_types.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " terrain types to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupTerrainTypesSheet - Creates TerrainTypes sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupTerrainTypesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_TERRAIN_TYPES)

    Dim headers As Variant
    headers = Array("id", "name", "placeholder_color", "has_collision", _
                    "movement_cost", "footstep_sound", "can_spawn_on")

    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: terrain_name (e.g., terrain_grass, terrain_wall)"
    SafeAddComment ws.Cells(1, 2), "Display name for the terrain type"
    SafeAddComment ws.Cells(1, 3), "Hex color for map editor placeholder (#RRGGBB, e.g., #3d6e3d)"
    SafeAddComment ws.Cells(1, 4), "TRUE/FALSE - Does this terrain block movement?"
    SafeAddComment ws.Cells(1, 5), "Movement speed multiplier (1.0 = normal, 2.0 = half speed, 0.0 = impassable)"
    SafeAddComment ws.Cells(1, 6), "Sound effect ID for footsteps (e.g., sfx_step_grass)"
    SafeAddComment ws.Cells(1, 7), "TRUE/FALSE - Can enemies spawn on this terrain?"
End Sub
