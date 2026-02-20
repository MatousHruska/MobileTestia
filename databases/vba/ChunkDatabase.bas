Attribute VB_Name = "ChunkDatabase"
'===============================================================================
' ChunkDatabase Module
' Handles validation and export for Chunks (chunk-based map loading system)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_CHUNKS As String = "Chunks"

' Column indices for Chunks (1-based)
Private Const COL_CH_ID As Integer = 1
Private Const COL_CH_ZONE_ID As Integer = 2
Private Const COL_CH_GRID_X As Integer = 3
Private Const COL_CH_GRID_Y As Integer = 4
Private Const COL_CH_BIOME_TYPE As Integer = 5
Private Const COL_CH_ENEMY_DENSITY As Integer = 6
Private Const COL_CH_SPAWN_TABLE_ID As Integer = 7
Private Const COL_CH_AMBIENT_OVERRIDE As Integer = 8
Private Const COL_CH_LIGHTING_PRESET As Integer = 9

' Valid dropdown values
Private validBiomeTypes() As String
Private validEnemyDensities() As String
Private validLightingPresets() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validBiomeTypes = Split("grass,forest,cave,dungeon,town,desert,snow,swamp,mountain,beach", ",")
    validEnemyDensities = Split("none,low,medium,high,very_high", ",")
    validLightingPresets = Split("default,dark,bright,dim,magical,sunset,night,underground", ",")
End Sub

'===============================================================================
' CHUNKS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateChunks - Validates all rows in Chunks sheet
'-------------------------------------------------------------------------------
Public Sub ValidateChunks()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CHUNKS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CHUNKS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CH_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CH_ID).Value)

        If Len(id) = 0 Then GoTo NextChunk

        ' Validate ID format (chunk_{zone_id}_{x}_{y})
        If Not ValidateId(id, "chunk_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: chunk_zonename_x_y (e.g., chunk_forest_0_0)"
        End If

        ' Validate zone_id not empty
        Dim zoneId As String
        zoneId = Trim(ws.Cells(i, COL_CH_ZONE_ID).Value)
        If Len(zoneId) = 0 Then
            LogValidationError errors, errorCount, i, "Zone ID", "Zone ID is required"
        ElseIf Left(zoneId, 5) <> "zone_" Then
            LogValidationError errors, errorCount, i, "Zone ID", _
                "Zone ID should start with 'zone_' (e.g., zone_forest)"
        End If

        ' Validate grid coordinates are integers
        Dim gridX As Double, gridY As Double
        gridX = GetDefaultNumeric(ws.Cells(i, COL_CH_GRID_X), 0)
        gridY = GetDefaultNumeric(ws.Cells(i, COL_CH_GRID_Y), 0)

        If gridX <> Int(gridX) Or gridX < 0 Then
            LogValidationError errors, errorCount, i, "Grid X", _
                "Grid X must be a non-negative integer"
        End If

        If gridY <> Int(gridY) Or gridY < 0 Then
            LogValidationError errors, errorCount, i, "Grid Y", _
                "Grid Y must be a non-negative integer"
        End If

        ' Validate biome type
        Dim biomeType As String
        biomeType = LCase(Trim(ws.Cells(i, COL_CH_BIOME_TYPE).Value))
        If Len(biomeType) > 0 And Not ValidateDropdown(biomeType, validBiomeTypes) Then
            LogValidationError errors, errorCount, i, "Biome Type", _
                "Invalid biome type. Valid: grass, forest, cave, dungeon, town, desert, snow, swamp, mountain, beach"
        End If

        ' Validate enemy density
        Dim enemyDensity As String
        enemyDensity = LCase(Trim(ws.Cells(i, COL_CH_ENEMY_DENSITY).Value))
        If Len(enemyDensity) > 0 And Not ValidateDropdown(enemyDensity, validEnemyDensities) Then
            LogValidationError errors, errorCount, i, "Enemy Density", _
                "Invalid density. Valid: none, low, medium, high, very_high"
        End If

        ' Validate lighting preset
        Dim lightingPreset As String
        lightingPreset = LCase(Trim(ws.Cells(i, COL_CH_LIGHTING_PRESET).Value))
        If Len(lightingPreset) > 0 And Not ValidateDropdown(lightingPreset, validLightingPresets) Then
            LogValidationError errors, errorCount, i, "Lighting Preset", _
                "Invalid preset. Valid: default, dark, bright, dim, magical, sunset, night, underground"
        End If

NextChunk:
    Next i

    ShowValidationResults errors, errorCount, "Chunks"
End Sub

'-------------------------------------------------------------------------------
' ExportChunksData - Exports Chunks to JSON
'-------------------------------------------------------------------------------
Public Sub ExportChunksData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CHUNKS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CHUNKS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""chunks"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CH_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CH_ID).Value)

        If Len(id) = 0 Then GoTo NextExportChunk

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""zone_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_ZONE_ID))) & """," & vbCrLf
        json = json & "      ""grid_x"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_GRID_X), 0)) & "," & vbCrLf
        json = json & "      ""grid_y"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_GRID_Y), 0)) & "," & vbCrLf
        json = json & "      ""biome_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CH_BIOME_TYPE), "grass"))) & """," & vbCrLf
        json = json & "      ""enemy_density"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CH_ENEMY_DENSITY), "none"))) & """," & vbCrLf
        json = json & "      ""spawn_table_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_SPAWN_TABLE_ID))) & """," & vbCrLf
        json = json & "      ""ambient_override"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_AMBIENT_OVERRIDE))) & """," & vbCrLf
        json = json & "      ""lighting_preset"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CH_LIGHTING_PRESET), "default"))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportChunk:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "chunks.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " chunks to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupChunksSheet - Creates Chunks sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupChunksSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_CHUNKS)

    Dim headers As Variant
    headers = Array("id", "zone_id", "grid_x", "grid_y", "biome_type", _
                    "enemy_density", "spawn_table_id", "ambient_override", "lighting_preset")

    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: chunk_{zone_id}_{x}_{y} (e.g., chunk_forest_0_0)"
    SafeAddComment ws.Cells(1, 2), "FK to Zones sheet (e.g., zone_forest)"
    SafeAddComment ws.Cells(1, 3), "Chunk X coordinate in zone grid (0-based integer)"
    SafeAddComment ws.Cells(1, 4), "Chunk Y coordinate in zone grid (0-based integer)"
    SafeAddComment ws.Cells(1, 5), "Biome type: grass, forest, cave, dungeon, town, desert, snow, swamp, mountain, beach"
    SafeAddComment ws.Cells(1, 6), "Enemy spawn density: none, low, medium, high, very_high"
    SafeAddComment ws.Cells(1, 7), "Optional FK to spawn tables"
    SafeAddComment ws.Cells(1, 8), "Optional ambient sound override for this chunk"
    SafeAddComment ws.Cells(1, 9), "Lighting preset: default, dark, bright, dim, magical, sunset, night, underground"
End Sub
