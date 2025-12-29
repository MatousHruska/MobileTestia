Attribute VB_Name = "EnemyDatabase"
'===============================================================================
' EnemyDatabase Module
' Handles validation and export for Enemies and Enemy Abilities
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_ENEMIES As String = "Enemies"
Private Const SHEET_ABILITIES As String = "EnemyAbilities"
Private Const SHEET_VARIANTS As String = "EnemyVariants"

' Column indices for Enemies (1-based)
Private Const COL_EN_ID As Integer = 1
Private Const COL_EN_NAME As Integer = 2
Private Const COL_EN_TYPE As Integer = 3           ' Normal, Miniboss, Boss
Private Const COL_EN_BASE_HEALTH As Integer = 4
Private Const COL_EN_BASE_DAMAGE As Integer = 5
Private Const COL_EN_ARMOR As Integer = 6
Private Const COL_EN_MOVE_SPEED As Integer = 7
Private Const COL_EN_ATTACK_SPEED As Integer = 8
Private Const COL_EN_ATTACK_RANGE As Integer = 9
Private Const COL_EN_DETECTION_RANGE As Integer = 10
Private Const COL_EN_XP_REWARD As Integer = 11
Private Const COL_EN_LOOT_TABLE_ID As Integer = 12
Private Const COL_EN_ABILITY_IDS As Integer = 13
Private Const COL_EN_BEHAVIOR_PROFILE As Integer = 14  ' Links to behavior_profiles.json
Private Const COL_EN_DESCRIPTION As Integer = 15

' Column indices for EnemyAbilities (expanded for AI system)
Private Const COL_EA_ID As Integer = 1
Private Const COL_EA_NAME As Integer = 2
Private Const COL_EA_DESCRIPTION As Integer = 3
Private Const COL_EA_TYPE As Integer = 4           ' melee, dash_attack, aoe, projectile, pattern, teleport_attack, beam
Private Const COL_EA_DAMAGE_MULT As Integer = 5    ' Multiplier applied to base damage
Private Const COL_EA_DAMAGE_TYPE As Integer = 6    ' physical, fire, cold, chaos, etc
Private Const COL_EA_COOLDOWN As Integer = 7
Private Const COL_EA_RANGE_MIN As Integer = 8      ' Minimum range to use ability
Private Const COL_EA_RANGE_MAX As Integer = 9      ' Maximum range to use ability
Private Const COL_EA_SHAPE As Integer = 10         ' circle, cone, line, cross, ring
Private Const COL_EA_SHAPE_SIZE As Integer = 11    ' Size/radius of shape
Private Const COL_EA_SHAPE_ANGLE As Integer = 12   ' Angle for cones/beams
Private Const COL_EA_WINDUP As Integer = 13        ' Wind-up time before damage
Private Const COL_EA_RECOVERY As Integer = 14      ' Recovery time after attack
Private Const COL_EA_ANIMATION As Integer = 15     ' Animation to play
Private Const COL_EA_PRIORITY As Integer = 16      ' AI priority (higher = preferred)
Private Const COL_EA_CONDITIONS As Integer = 17    ' Conditions like "distance>50" or "health<50%"
Private Const COL_EA_EFFECTS_ON_HIT As Integer = 18 ' Effects: "stun:0.5", "burn:3:5", "knockback:100"
Private Const COL_EA_PROJECTILE_SPEED As Integer = 19 ' For projectile abilities
Private Const COL_EA_DASH_SPEED As Integer = 20    ' For dash abilities

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
Private validAbilityTypes() As String
Private validDamageTypes() As String
Private validAbilityShapes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validEnemyTypes = Split("Normal,Miniboss,Boss", ",")
    validAbilityTypes = Split("melee,dash_attack,aoe,projectile,pattern,teleport_attack,beam", ",")
    validDamageTypes = Split("physical,fire,cold,lightning,poison,chaos,pure", ",")
    validAbilityShapes = Split("circle,cone,line,cross,ring", ",")
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

        If GetDefaultNumeric(ws.Cells(i, COL_EN_XP_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "XP Reward", "Cannot be negative"
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
        json = json & "      ""move_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_MOVE_SPEED), 80)) & "," & vbCrLf
        json = json & "      ""attack_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_ATTACK_SPEED), 1)) & "," & vbCrLf
        json = json & "      ""attack_range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_ATTACK_RANGE), 24)) & "," & vbCrLf
        json = json & "      ""detection_range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_DETECTION_RANGE), 150)) & "," & vbCrLf
        json = json & "      ""xp_reward"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EN_XP_REWARD), 25)) & "," & vbCrLf
        json = json & "      ""loot_table_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_LOOT_TABLE_ID))) & """," & vbCrLf
        json = json & "      ""ability_ids"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_ABILITY_IDS))) & """," & vbCrLf
        json = json & "      ""behavior_profile"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EN_BEHAVIOR_PROFILE), "bhv_basic_melee")) & """" & vbCrLf
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
' ENEMY ABILITIES
'===============================================================================

'-------------------------------------------------------------------------------
' ExportEnemyAbilities - Exports EnemyAbilities to JSON (expanded for AI system)
'-------------------------------------------------------------------------------
Public Sub ExportEnemyAbilities()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ABILITIES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ABILITIES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""enemy_abilities"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_EA_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_EA_ID).value)

        If Len(id) = 0 Then GoTo NextExportAbility

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EA_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EA_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_EA_TYPE), "melee"))) & """," & vbCrLf
        json = json & "      ""damage_mult"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_DAMAGE_MULT), 1)) & "," & vbCrLf
        json = json & "      ""damage_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_EA_DAMAGE_TYPE), "physical"))) & """," & vbCrLf
        json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_COOLDOWN), 0)) & "," & vbCrLf
        json = json & "      ""range_min"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_RANGE_MIN), 0)) & "," & vbCrLf
        json = json & "      ""range_max"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_RANGE_MAX), 30)) & "," & vbCrLf
        json = json & "      ""shape"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_EA_SHAPE), "circle"))) & """," & vbCrLf
        json = json & "      ""shape_size"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_SHAPE_SIZE), 25)) & "," & vbCrLf
        json = json & "      ""shape_angle"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_SHAPE_ANGLE), 0)) & "," & vbCrLf
        json = json & "      ""windup"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_WINDUP), 0.2)) & "," & vbCrLf
        json = json & "      ""recovery"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_RECOVERY), 0.3)) & "," & vbCrLf
        json = json & "      ""animation"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EA_ANIMATION), "attack")) & """," & vbCrLf
        json = json & "      ""priority"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_EA_PRIORITY), 1)) & "," & vbCrLf
        json = json & "      ""conditions"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EA_CONDITIONS))) & """," & vbCrLf
        json = json & "      ""effects_on_hit"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_EA_EFFECTS_ON_HIT))) & """"

        ' Add optional projectile/dash speed if present
        Dim projSpeed As Double
        Dim dashSpeed As Double
        projSpeed = GetDefaultNumeric(ws.Cells(i, COL_EA_PROJECTILE_SPEED), 0)
        dashSpeed = GetDefaultNumeric(ws.Cells(i, COL_EA_DASH_SPEED), 0)

        If projSpeed > 0 Then
            json = json & "," & vbCrLf & "      ""projectile_speed"": " & FormatJsonNumber(projSpeed)
        End If
        If dashSpeed > 0 Then
            json = json & "," & vbCrLf & "      ""dash_speed"": " & FormatJsonNumber(dashSpeed)
        End If

        json = json & vbCrLf & "    }"

        itemCount = itemCount + 1

NextExportAbility:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "enemy_abilities.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " enemy abilities to:" & vbCrLf & filePath, vbInformation, "Export Complete"
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
    ExportEnemyAbilities
    ExportEnemyVariants
    MsgBox "All enemy databases exported!", vbInformation, "Export Complete"
End Sub
