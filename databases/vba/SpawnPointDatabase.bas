Attribute VB_Name = "SpawnPointDatabase"
'===============================================================================
' SpawnPointDatabase Module
' Handles validation and export for Spawn Points
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_SPAWN_POINTS As String = "SpawnPoints"

' Column indices for SpawnPoints (1-based)
Private Const COL_SP_ID As Integer = 1
Private Const COL_SP_NAME As Integer = 2
Private Const COL_SP_DESCRIPTION As Integer = 3
Private Const COL_SP_ENEMY_POOL As Integer = 4
Private Const COL_SP_MIN_LEVEL As Integer = 5
Private Const COL_SP_MAX_LEVEL As Integer = 6
Private Const COL_SP_CHECK_INTERVAL As Integer = 7
Private Const COL_SP_SPAWN_CHANCE As Integer = 8
Private Const COL_SP_MAX_ACTIVE As Integer = 9
Private Const COL_SP_RESPAWN_DELAY As Integer = 10
Private Const COL_SP_SPAWN_RADIUS As Integer = 11
Private Const COL_SP_SPAWN_GROUP As Integer = 12
Private Const COL_SP_REQUIRE_QUEST_ACTIVE As Integer = 13
Private Const COL_SP_REQUIRE_QUEST_COMPLETED As Integer = 14
Private Const COL_SP_DISABLE_AFTER_QUEST As Integer = 15
Private Const COL_SP_DISABLE_DURING_QUEST As Integer = 16

'-------------------------------------------------------------------------------
' ValidateSpawnPoints - Validates all rows in SpawnPoints sheet
'-------------------------------------------------------------------------------
Public Sub ValidateSpawnPoints()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SPAWN_POINTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SPAWN_POINTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SP_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SP_ID).value)

        If Len(id) = 0 Then GoTo NextSpawnPoint

        ' Validate ID format
        If Not ValidateId(id, "sp_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: sp_zone_description (e.g., sp_meadow_zombies)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_SP_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate enemy_pool format (enemy_id:weight,enemy_id:weight)
        Dim enemyPool As String
        enemyPool = Trim(ws.Cells(i, COL_SP_ENEMY_POOL).value)
        If Len(enemyPool) > 0 Then
            If Not ValidateEnemyPoolFormat(enemyPool) Then
                LogValidationError errors, errorCount, i, "Enemy Pool", _
                    "Invalid format. Use: enemy_id:weight,enemy_id:weight (e.g., ene_zombie_basic:70,ene_ghoul_basic:30)"
            End If
        End If

        ' Validate level range
        Dim minLevel As Integer, maxLevel As Integer
        minLevel = GetDefaultNumeric(ws.Cells(i, COL_SP_MIN_LEVEL), 1)
        maxLevel = GetDefaultNumeric(ws.Cells(i, COL_SP_MAX_LEVEL), 5)
        If minLevel > maxLevel Then
            LogValidationError errors, errorCount, i, "Level Range", "Min level cannot be greater than max level"
        End If

        ' Validate spawn_chance 0-1
        Dim spawnChance As Double
        spawnChance = GetDefaultNumeric(ws.Cells(i, COL_SP_SPAWN_CHANCE), 1)
        If spawnChance < 0 Or spawnChance > 1 Then
            LogValidationError errors, errorCount, i, "Spawn Chance", "Must be between 0.0 and 1.0"
        End If

        ' Validate max_active_enemies > 0
        If GetDefaultNumeric(ws.Cells(i, COL_SP_MAX_ACTIVE), 1) <= 0 Then
            LogValidationError errors, errorCount, i, "Max Active", "Must be greater than 0"
        End If

        ' Validate numeric fields non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_SP_CHECK_INTERVAL)) < 0 Then
            LogValidationError errors, errorCount, i, "Check Interval", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_SP_RESPAWN_DELAY)) < 0 Then
            LogValidationError errors, errorCount, i, "Respawn Delay", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_SP_SPAWN_RADIUS)) < 0 Then
            LogValidationError errors, errorCount, i, "Spawn Radius", "Cannot be negative"
        End If

NextSpawnPoint:
    Next i

    ShowValidationResults errors, errorCount, "SpawnPoints"
End Sub

'-------------------------------------------------------------------------------
' ValidateEnemyPoolFormat - Validates enemy pool string format
'-------------------------------------------------------------------------------
Private Function ValidateEnemyPoolFormat(ByVal poolString As String) As Boolean
    ' Format: enemy_id:weight,enemy_id:weight
    Dim entries() As String
    entries = Split(poolString, ",")

    Dim i As Integer
    For i = 0 To UBound(entries)
        Dim entry As String
        entry = Trim(entries(i))

        If Len(entry) = 0 Then
            ValidateEnemyPoolFormat = False
            Exit Function
        End If

        Dim parts() As String
        parts = Split(entry, ":")

        ' Must have enemy_id and optionally weight
        If UBound(parts) < 0 Then
            ValidateEnemyPoolFormat = False
            Exit Function
        End If

        ' If weight provided, must be numeric
        If UBound(parts) >= 1 Then
            If Not IsNumeric(Trim(parts(1))) Then
                ValidateEnemyPoolFormat = False
                Exit Function
            End If
        End If
    Next i

    ValidateEnemyPoolFormat = True
End Function

'-------------------------------------------------------------------------------
' ExportSpawnPoints - Exports SpawnPoints to JSON
'-------------------------------------------------------------------------------
Public Sub ExportSpawnPoints()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SPAWN_POINTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SPAWN_POINTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""spawn_points"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SP_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SP_ID).value)

        If Len(id) = 0 Then GoTo NextExportSpawnPoint

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""enemy_pool"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_ENEMY_POOL))) & """," & vbCrLf
        json = json & "      ""min_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_MIN_LEVEL), 1)) & "," & vbCrLf
        json = json & "      ""max_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_MAX_LEVEL), 5)) & "," & vbCrLf
        json = json & "      ""check_interval"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_CHECK_INTERVAL), 60)) & "," & vbCrLf
        json = json & "      ""spawn_chance"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_SPAWN_CHANCE), 1)) & "," & vbCrLf
        json = json & "      ""max_active_enemies"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_MAX_ACTIVE), 1)) & "," & vbCrLf
        json = json & "      ""respawn_delay"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_RESPAWN_DELAY))) & "," & vbCrLf
        json = json & "      ""spawn_radius"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SP_SPAWN_RADIUS))) & "," & vbCrLf
        json = json & "      ""spawn_group"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_SPAWN_GROUP))) & """," & vbCrLf
        json = json & "      ""require_quest_active"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_REQUIRE_QUEST_ACTIVE))) & """," & vbCrLf
        json = json & "      ""require_quest_completed"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_REQUIRE_QUEST_COMPLETED))) & """," & vbCrLf
        json = json & "      ""disable_after_quest"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_DISABLE_AFTER_QUEST))) & """," & vbCrLf
        json = json & "      ""disable_during_quest"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SP_DISABLE_DURING_QUEST))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportSpawnPoint:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "spawn_points.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " spawn points to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupSpawnPointsSheet - Creates SpawnPoints sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupSpawnPointsSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SPAWN_POINTS)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.name = SHEET_SPAWN_POINTS
    End If

    Dim headers As Variant
    headers = Array("id", "name", "description", "enemy_pool", "min_level", "max_level", _
                    "check_interval", "spawn_chance", "max_active_enemies", "respawn_delay", _
                    "spawn_radius", "spawn_group", "require_quest_active", "require_quest_completed", _
                    "disable_after_quest", "disable_during_quest")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 4), "Format: enemy_id:weight,enemy_id:weight (e.g., ene_zombie_basic:70,ene_ghoul_basic:30)"
    SafeAddComment ws.Cells(1, 8), "0.0 to 1.0 (1.0 = 100% chance)"
    SafeAddComment ws.Cells(1, 13), "Quest ID - only spawn if this quest is active"
    SafeAddComment ws.Cells(1, 14), "Quest ID - only spawn if this quest is completed"
    SafeAddComment ws.Cells(1, 15), "Quest ID - stop spawning after quest completed"
    SafeAddComment ws.Cells(1, 16), "Quest ID - don't spawn while quest active or completed"

    MsgBox "SpawnPoints sheet created with headers!", vbInformation
End Sub
