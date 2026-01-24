Attribute VB_Name = "EnemyDatabase"
'===============================================================================
' EnemyDatabase Module
' Handles validation and export for Enemies
'
' Enemy AI uses module_ids system (see EnemyModuleDatabase)
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_ENEMIES As String = "Enemies"
Private Const SHEET_VARIANTS As String = "EnemyVariants"

' Column indices for Enemies (1-based)
Private Const COL_EN_ID As Integer = 1
Private Const COL_EN_NAME As Integer = 2
Private Const COL_EN_TYPE As Integer = 3           ' Normal, Miniboss, Boss
Private Const COL_EN_BASE_HEALTH As Integer = 4
Private Const COL_EN_BASE_DAMAGE As Integer = 5
Private Const COL_EN_ARMOR As Integer = 6
Private Const COL_EN_BASE_SHIELD As Integer = 7    ' Shield absorbs damage before health
Private Const COL_EN_MOVE_SPEED As Integer = 8
Private Const COL_EN_ATTACK_SPEED As Integer = 9
Private Const COL_EN_DETECTION_RANGE As Integer = 10
Private Const COL_EN_XP_REWARD As Integer = 11
Private Const COL_EN_LOOT_TABLE_ID As Integer = 12
Private Const COL_EN_MODULE_IDS As Integer = 13    ' Modular AI module IDs (comma-separated)
Private Const COL_EN_MODULE_CONFIG As Integer = 14 ' Per-enemy module config overrides (JSON)
Private Const COL_EN_NAVIGATION_LAYER As Integer = 15 ' Navigation layer (ground, flying, jumping, ghost)
Private Const COL_EN_DESCRIPTION As Integer = 16

' Column indices for EnemyVariants
Private Const COL_EV_ID As Integer = 1
Private Const COL_EV_NAME As Integer = 2
Private Const COL_EV_HEALTH_MULT As Integer = 3
Private Const COL_EV_DAMAGE_MULT As Integer = 4
Private Const COL_EV_XP_MULT As Integer = 5
Private Const COL_EV_EXTRA_ABILITIES As Integer = 6
Private Const COL_EV_VISUAL_EFFECT As Integer = 7

' Valid dropdown values
Private validEnemyTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validEnemyTypes = Split("Normal,Miniboss,Boss", ",")
End Sub

'===============================================================================
' ENEMIES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateEnemies - Validates all rows in Enemies sheet
'-------------------------------------------------------------------------------
Public Sub ValidateEnemies()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ENEMIES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ENEMIES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_EN_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_EN_ID).value)

        If Len(id) = 0 Then GoTo NextEnemy

        ' Validate ID format
        If Not ValidateId(id, "ene_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: ene_type_name (e.g., ene_zombie_basic)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_EN_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate enemy type
        Dim enemyType As String
        enemyType = Trim(ws.Cells(i, COL_EN_TYPE).value)
        If Len(enemyType) > 0 And Not ValidateDropdown(enemyType, validEnemyTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: Normal, Miniboss, Boss"
        End If

        ' Validate health > 0
        If GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_HEALTH)) <= 0 Then
            LogValidationError errors, errorCount, i, "Base Health", "Must be greater than 0"
        End If

        ' Validate numeric fields non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_DAMAGE)) < 0 Then
            LogValidationError errors, errorCount, i, "Base Damage", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_SHIELD)) < 0 Then
            LogValidationError errors, errorCount, i, "Base Shield", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_EN_XP_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "XP Reward", "Cannot be negative"
        End If

        ' Validate module_config is valid JSON (basic check)
        Dim moduleConfig As String
        moduleConfig = Trim(ws.Cells(i, COL_EN_MODULE_CONFIG).value)
        If Len(moduleConfig) > 0 Then
            If Left(moduleConfig, 1) <> "{" Or Right(moduleConfig, 1) <> "}" Then
                LogValidationError errors, errorCount, i, "Module Config", _
                    "Config must be valid JSON object (start with { and end with })"
            End If
        End If

NextEnemy:
    Next i

    ShowValidationResults errors, errorCount, "Enemies"
End Sub

'-------------------------------------------------------------------------------
' ExportEnemies - Exports Enemies to JSON
'-------------------------------------------------------------------------------
Public Sub ExportEnemies()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ENEMIES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ENEMIES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""enemies"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_EN_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_EN_ID).value)

        If Len(id) = 0 Then GoTo NextExportEnemy

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_TYPE), "Normal")) & """," & vbCrLf
        json = json & "      ""base_health"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_HEALTH), 100)) & "," & vbCrLf
        json = json & "      ""base_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_DAMAGE), 10)) & "," & vbCrLf
        json = json & "      ""armor"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_ARMOR))) & "," & vbCrLf
        json = json & "      ""base_shield"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_BASE_SHIELD))) & "," & vbCrLf
        json = json & "      ""move_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_MOVE_SPEED), 80)) & "," & vbCrLf
        json = json & "      ""attack_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_ATTACK_SPEED), 1)) & "," & vbCrLf
        json = json & "      ""detection_range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_DETECTION_RANGE), 150)) & "," & vbCrLf
        json = json & "      ""xp_reward"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_XP_REWARD), 25)) & "," & vbCrLf
        json = json & "      ""loot_table_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_LOOT_TABLE_ID))) & """," & vbCrLf
        json = json & "      ""module_ids"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_MODULE_IDS))) & """," & vbCrLf

        ' Module config - output as JSON object (empty {} if not specified)
        Dim moduleConfig As String
        moduleConfig = Trim(ws.Cells(i, COL_EN_MODULE_CONFIG).value)
        If Len(moduleConfig) = 0 Then
            json = json & "      ""module_config"": {}," & vbCrLf
        Else
            json = json & "      ""module_config"": " & moduleConfig & "," & vbCrLf
        End If

        ' Navigation layer - default to "ground" if empty
        json = json & "      ""navigation_layer"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_NAVIGATION_LAYER), "ground")) & """," & vbCrLf

        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportEnemy:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "enemies.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " enemies to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' ENEMY VARIANTS
'===============================================================================

'-------------------------------------------------------------------------------
' ExportEnemyVariants - Exports EnemyVariants to JSON
'-------------------------------------------------------------------------------
Public Sub ExportEnemyVariants()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_VARIANTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_VARIANTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""enemy_variants"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_EV_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_EV_ID).value)

        If Len(id) = 0 Then GoTo NextExportVariant

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EV_NAME))) & """," & vbCrLf
        json = json & "      ""health_multiplier"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EV_HEALTH_MULT), 1)) & "," & vbCrLf
        json = json & "      ""damage_multiplier"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EV_DAMAGE_MULT), 1)) & "," & vbCrLf
        json = json & "      ""xp_multiplier"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EV_XP_MULT), 1)) & "," & vbCrLf
        json = json & "      ""extra_abilities"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EV_EXTRA_ABILITIES))) & """," & vbCrLf
        json = json & "      ""visual_effect"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EV_VISUAL_EFFECT))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportVariant:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "enemy_variants.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " enemy variants to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' MASTER EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportAllEnemies - Exports all enemy-related sheets
'-------------------------------------------------------------------------------
Public Sub ExportAllEnemies()
    ExportEnemies
    ExportEnemyVariants
    MsgBox "All enemy databases exported!", vbInformation, "Export Complete"
End Sub

'===============================================================================
' SHEET SETUP
'===============================================================================

'-------------------------------------------------------------------------------
' SetupEnemiesSheet - Creates Enemies sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupEnemiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_ENEMIES)
    Dim headers As Variant
    headers = Array("id", "name", "type", "base_health", "base_damage", "armor", "base_shield", _
                    "move_speed", "attack_speed", "detection_range", _
                    "xp_reward", "loot_table_id", "module_ids", "module_config", "navigation_layer", "description")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: ene_type_name (e.g., ene_zombie_basic)"
    SafeAddComment ws.Cells(1, 3), "Normal, Miniboss, or Boss"
    SafeAddComment ws.Cells(1, 4), "Base health points"
    SafeAddComment ws.Cells(1, 5), "Base damage dealt"
    SafeAddComment ws.Cells(1, 6), "Armor reduces physical damage"
    SafeAddComment ws.Cells(1, 7), "Shield absorbs damage before health (0 = no shield)"
    SafeAddComment ws.Cells(1, 8), "Movement speed (default 80)"
    SafeAddComment ws.Cells(1, 9), "Attacks per second (default 1). Also controls minimum time between attacks."
    SafeAddComment ws.Cells(1, 10), "Range to detect player (default 150)"
    SafeAddComment ws.Cells(1, 12), "Reference to LootTables id"
    SafeAddComment ws.Cells(1, 13), "Comma-separated module IDs for AI (e.g., mod_target_detection,mod_chase,mod_combat)"
    SafeAddComment ws.Cells(1, 14), "Per-enemy module config overrides as JSON. Format: {""mod_idle"": {""can_roam"": false}}"
    SafeAddComment ws.Cells(1, 15), "Navigation layer: ground, flying, jumping, ghost. Determines what terrain the enemy can traverse."
End Sub

'-------------------------------------------------------------------------------
' SetupEnemyVariantsSheet - Creates EnemyVariants sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupEnemyVariantsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_VARIANTS)
    Dim headers As Variant
    headers = Array("id", "name", "health_multiplier", "damage_multiplier", _
                    "xp_multiplier", "extra_abilities", "visual_effect")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: var_name (e.g., var_elite, var_enraged)"
    SafeAddComment ws.Cells(1, 3), "Health multiplier (1.5 = 150% health)"
    SafeAddComment ws.Cells(1, 4), "Damage multiplier (1.5 = 150% damage)"
    SafeAddComment ws.Cells(1, 5), "XP reward multiplier"
    SafeAddComment ws.Cells(1, 6), "Additional ability IDs"
    SafeAddComment ws.Cells(1, 7), "Visual effect to apply (glow, aura, etc)"
End Sub

'-------------------------------------------------------------------------------
' SetupAllEnemySheets - Creates all enemy-related sheets
'-------------------------------------------------------------------------------
Public Sub SetupAllEnemySheets()
    SetupEnemiesSheet
    SetupEnemyVariantsSheet
    MsgBox "All enemy sheets created!", vbInformation, "Setup Complete"
End Sub
