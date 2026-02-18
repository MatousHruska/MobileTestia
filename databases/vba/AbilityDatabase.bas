Attribute VB_Name = "AbilityDatabase"
'===============================================================================
' AbilityDatabase Module
' Manages Abilities and EnemyAbilities sheets for the combat system
' Part of the Phase 4 Modular AI Combat System
'===============================================================================
Option Explicit

'-------------------------------------------------------------------------------
' ABILITIES SHEET
'-------------------------------------------------------------------------------

'-------------------------------------------------------------------------------
' SetupAbilitiesSheet - Creates the Abilities sheet with proper headers
'-------------------------------------------------------------------------------
Public Sub SetupAbilitiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Abilities")

    Dim headers As Variant
    headers = Array("id", "name", "ability_type", "damage_mult", "damage_type", _
                    "range", "cooldown", "cast_time", "cast_while_moving", "projectile_speed", _
                    "aoe_radius", "movement_type", "movement_distance", _
                    "status_effect_id", "animation", "extra_config", "description", "visual_type")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Ability ID: abi_name (e.g., abi_melee_strike)"
    SafeAddComment ws.Cells(1, 3), "melee, ranged, projectile, dash, buff, debuff"
    SafeAddComment ws.Cells(1, 4), "Damage multiplier (1.0 = base damage)"
    SafeAddComment ws.Cells(1, 5), "physical, fire, cold, lightning, poison, healing"
    SafeAddComment ws.Cells(1, 6), "Effective range in pixels"
    SafeAddComment ws.Cells(1, 7), "Base cooldown in seconds"
    SafeAddComment ws.Cells(1, 8), "Cast time / wind-up before ability executes (0 = instant)"
    SafeAddComment ws.Cells(1, 9), "TRUE = can move while casting, FALSE = must stop (default FALSE)"
    SafeAddComment ws.Cells(1, 10), "For ranged/projectile types (pixels/sec)"
    SafeAddComment ws.Cells(1, 11), "For area effects (0 = single target)"
    SafeAddComment ws.Cells(1, 12), "none, dash_to, dash_away, teleport"
    SafeAddComment ws.Cells(1, 13), "Distance for dash/teleport abilities"
    SafeAddComment ws.Cells(1, 14), "Status effect to apply (from StatusEffects)"
    SafeAddComment ws.Cells(1, 15), "Animation name to play"
    SafeAddComment ws.Cells(1, 16), "JSON config for ability-specific params, e.g. {""falloff_type"": ""linear"", ""center_mult"": 2.0}"
    SafeAddComment ws.Cells(1, 18), "Visual template: melee_single, melee_combo_2, dash_attack, ranged_attack, spell_cast, howl (empty=auto)"
End Sub

'-------------------------------------------------------------------------------
' ExportAbilities - Exports Abilities sheet to JSON
'-------------------------------------------------------------------------------
Public Sub ExportAbilities()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("Abilities")
    On Error GoTo 0

    If ws Is Nothing Then
        Debug.Print "Abilities sheet not found, skipping export"
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    If lastRow < 2 Then
        Debug.Print "Abilities sheet is empty"
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""abilities"": [" & vbCrLf

    Dim row As Long
    Dim first As Boolean
    first = True

    For row = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(row, 1).Value)

        If Len(id) > 0 Then
            If Not first Then json = json & "," & vbCrLf
            first = False

            json = json & "    {" & vbCrLf
            json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
            json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 2))) & """," & vbCrLf
            json = json & "      ""ability_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 3), "melee")) & """," & vbCrLf
            json = json & "      ""damage_mult"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 4), 1)) & "," & vbCrLf
            json = json & "      ""damage_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 5), "physical")) & """," & vbCrLf
            json = json & "      ""range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 6), 24)) & "," & vbCrLf
            json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 7), 1)) & "," & vbCrLf
            json = json & "      ""cast_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 8), 0)) & "," & vbCrLf
            json = json & "      ""cast_while_moving"": " & LCase(CStr(GetDefaultBoolean(ws.Cells(row, 9), False))) & "," & vbCrLf
            json = json & "      ""projectile_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 10), 0)) & "," & vbCrLf
            json = json & "      ""aoe_radius"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 11), 0)) & "," & vbCrLf
            json = json & "      ""movement_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 12), "none")) & """," & vbCrLf
            json = json & "      ""movement_distance"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(row, 13), 0)) & "," & vbCrLf
            json = json & "      ""status_effect_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 14))) & """," & vbCrLf
            json = json & "      ""animation"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 15), "attack")) & """," & vbCrLf

            ' extra_config - parse as JSON object if present
            Dim extraConfig As String
            extraConfig = Trim(ws.Cells(row, 16).Value)
            If Len(extraConfig) > 0 Then
                json = json & "      ""extra_config"": " & extraConfig & "," & vbCrLf
            End If

            json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 17))) & """," & vbCrLf
            json = json & "      ""visual_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 18))) & """" & vbCrLf
            json = json & "    }"
        End If
    Next row

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    WriteJsonFile GetExportPath() & "abilities.json", json
    Debug.Print "Exported Abilities to abilities.json"
End Sub

'-------------------------------------------------------------------------------
' ValidateAbilities - Validates the Abilities sheet
'-------------------------------------------------------------------------------
Public Sub ValidateAbilities()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("Abilities")
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Abilities sheet not found!", vbExclamation
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    ' Valid enum values
    Dim validAbilityTypes() As String
    validAbilityTypes = Split("melee,ranged,projectile,dash,buff,debuff", ",")

    Dim validDamageTypes() As String
    validDamageTypes = Split("physical,fire,cold,lightning,poison,healing", ",")

    Dim validMovementTypes() As String
    validMovementTypes = Split("none,dash_to,dash_away,teleport", ",")

    Dim row As Long
    For row = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(row, 1).Value)

        If Len(id) > 0 Then
            ' Validate ID format
            If Not ValidateId(id, "abi_") Then
                LogValidationError errors, errorCount, row, "A", "Invalid ID format (should be abi_xxx): " & id
            End If

            ' Validate ability_type
            Dim abilityType As String
            abilityType = LCase(Trim(ws.Cells(row, 3).Value))
            If Len(abilityType) > 0 And Not ValidateDropdown(abilityType, validAbilityTypes) Then
                LogValidationError errors, errorCount, row, "C", "Invalid ability_type: " & abilityType
            End If

            ' Validate damage_type
            Dim damageType As String
            damageType = LCase(Trim(ws.Cells(row, 5).Value))
            If Len(damageType) > 0 And Not ValidateDropdown(damageType, validDamageTypes) Then
                LogValidationError errors, errorCount, row, "E", "Invalid damage_type: " & damageType
            End If

            ' Validate movement_type (column 12 after adding cast_while_moving)
            Dim movementType As String
            movementType = LCase(Trim(ws.Cells(row, 12).Value))
            If Len(movementType) > 0 And Not ValidateDropdown(movementType, validMovementTypes) Then
                LogValidationError errors, errorCount, row, "L", "Invalid movement_type: " & movementType
            End If

            ' Validate visual_type (if present)
            Dim visualType As String
            visualType = LCase(Trim(ws.Cells(row, 18).Value))
            If Len(visualType) > 0 Then
                Dim validVisualTypes() As String
                validVisualTypes = Split("melee_single,melee_combo_2,melee_combo_3,dash_attack,ranged_aim,ranged_attack,spell_cast,spell_instant,throw,self_buff,howl", ",")
                If Not ValidateDropdown(visualType, validVisualTypes) Then
                    LogValidationError errors, errorCount, row, "R", "Invalid visual_type: " & visualType
                End If
            End If

            ' Validate numeric ranges
            If GetDefaultNumeric(ws.Cells(row, 4)) < 0 Then
                LogValidationError errors, errorCount, row, "D", "damage_mult cannot be negative"
            End If

            If GetDefaultNumeric(ws.Cells(row, 6)) < 0 Then
                LogValidationError errors, errorCount, row, "F", "range cannot be negative"
            End If

            If GetDefaultNumeric(ws.Cells(row, 7)) < 0 Then
                LogValidationError errors, errorCount, row, "G", "cooldown cannot be negative"
            End If
        End If
    Next row

    ShowValidationResults errors, errorCount, "Abilities"
End Sub

'-------------------------------------------------------------------------------
' ENEMY ABILITIES SHEET
'-------------------------------------------------------------------------------

'-------------------------------------------------------------------------------
' SetupEnemyAbilitiesSheet - Creates the EnemyAbilities sheet with proper headers
'-------------------------------------------------------------------------------
Public Sub SetupEnemyAbilitiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyAbilities")

    Dim headers As Variant
    headers = Array("enemy_id", "ability_id", "priority", "condition", _
                    "cooldown_override", "damage_mult_override", "config_override")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Reference to enemy (ene_xxx)"
    SafeAddComment ws.Cells(1, 2), "Reference to ability (abi_xxx)"
    SafeAddComment ws.Cells(1, 3), "Higher = preferred (100=opener, 50=default)"
    SafeAddComment ws.Cells(1, 4), "When to use: default, opener, target_close, target_far, health_below_X, health_above_X, on_cooldown_X, ally_nearby"
    SafeAddComment ws.Cells(1, 5), "Override base cooldown (optional)"
    SafeAddComment ws.Cells(1, 6), "Override damage multiplier (optional, multiplies with ability's damage_mult)"
    SafeAddComment ws.Cells(1, 7), "JSON to override any ability field, e.g. {""range"": 300, ""cast_time"": 0.1}"
End Sub

'-------------------------------------------------------------------------------
' ExportEnemyAbilities - Exports EnemyAbilities sheet to JSON
'-------------------------------------------------------------------------------
Public Sub ExportEnemyAbilities()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("EnemyAbilities")
    On Error GoTo 0

    If ws Is Nothing Then
        Debug.Print "EnemyAbilities sheet not found, skipping export"
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    If lastRow < 2 Then
        Debug.Print "EnemyAbilities sheet is empty"
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""enemy_abilities"": [" & vbCrLf

    Dim row As Long
    Dim first As Boolean
    first = True

    For row = 2 To lastRow
        Dim enemyId As String
        enemyId = Trim(ws.Cells(row, 1).Value)

        Dim abilityId As String
        abilityId = Trim(ws.Cells(row, 2).Value)

        If Len(enemyId) > 0 And Len(abilityId) > 0 Then
            If Not first Then json = json & "," & vbCrLf
            first = False

            json = json & "    {" & vbCrLf
            json = json & "      ""enemy_id"": """ & EscapeJsonString(enemyId) & """," & vbCrLf
            json = json & "      ""ability_id"": """ & EscapeJsonString(abilityId) & """," & vbCrLf
            json = json & "      ""priority"": " & CStr(GetDefaultNumeric(ws.Cells(row, 3), 50)) & "," & vbCrLf
            json = json & "      ""condition"": """ & EscapeJsonString(GetDefaultString(ws.Cells(row, 4), "default")) & """"

            ' Optional overrides - only include if set
            Dim cooldownOverride As Double
            cooldownOverride = GetDefaultNumeric(ws.Cells(row, 5), -1)
            If cooldownOverride >= 0 Then
                json = json & "," & vbCrLf
                json = json & "      ""cooldown_override"": " & FormatJsonNumber(cooldownOverride)
            End If

            Dim damageMultOverride As Double
            damageMultOverride = GetDefaultNumeric(ws.Cells(row, 6), -1)
            If damageMultOverride >= 0 Then
                json = json & "," & vbCrLf
                json = json & "      ""damage_mult_override"": " & FormatJsonNumber(damageMultOverride)
            End If

            ' config_override - parse as JSON object if present
            Dim configOverride As String
            configOverride = Trim(ws.Cells(row, 7).Value)
            If Len(configOverride) > 0 Then
                json = json & "," & vbCrLf
                json = json & "      ""config_override"": " & configOverride
            End If

            json = json & vbCrLf & "    }"
        End If
    Next row

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    WriteJsonFile GetExportPath() & "enemy_abilities.json", json
    Debug.Print "Exported EnemyAbilities to enemy_abilities.json"
End Sub

'-------------------------------------------------------------------------------
' ValidateEnemyAbilities - Validates the EnemyAbilities sheet
'-------------------------------------------------------------------------------
Public Sub ValidateEnemyAbilities()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("EnemyAbilities")
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "EnemyAbilities sheet not found!", vbExclamation
        Exit Sub
    End If

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    ' Valid condition types
    Dim validConditions() As String
    validConditions = Split("default,opener,target_close,target_far,ally_nearby", ",")

    Dim row As Long
    For row = 2 To lastRow
        Dim enemyId As String
        enemyId = Trim(ws.Cells(row, 1).Value)

        Dim abilityId As String
        abilityId = Trim(ws.Cells(row, 2).Value)

        If Len(enemyId) > 0 Or Len(abilityId) > 0 Then
            ' Validate enemy_id format
            If Not ValidateId(enemyId, "ene_") Then
                LogValidationError errors, errorCount, row, "A", "Invalid enemy_id format: " & enemyId
            End If

            ' Validate ability_id format
            If Not ValidateId(abilityId, "abi_") Then
                LogValidationError errors, errorCount, row, "B", "Invalid ability_id format: " & abilityId
            End If

            ' Validate condition (check basic conditions and patterns)
            Dim condition As String
            condition = LCase(Trim(ws.Cells(row, 4).Value))
            If Len(condition) > 0 Then
                Dim isValid As Boolean
                isValid = ValidateDropdown(condition, validConditions)

                ' Also allow health_below_X, health_above_X, on_cooldown_X patterns
                If Not isValid Then
                    If Left(condition, 13) = "health_below_" Or _
                       Left(condition, 13) = "health_above_" Or _
                       Left(condition, 12) = "on_cooldown_" Then
                        isValid = True
                    End If
                End If

                If Not isValid Then
                    LogValidationError errors, errorCount, row, "D", "Invalid condition: " & condition
                End If
            End If

            ' Validate priority range
            Dim priority As Double
            priority = GetDefaultNumeric(ws.Cells(row, 3), 50)
            If priority < 0 Or priority > 200 Then
                LogValidationError errors, errorCount, row, "C", "priority should be 0-200, got: " & priority
            End If
        End If
    Next row

    ShowValidationResults errors, errorCount, "EnemyAbilities"
End Sub

'-------------------------------------------------------------------------------
' SetupAbilitySheetsOnly - Creates just the ability sheets
'-------------------------------------------------------------------------------
Public Sub SetupAbilitySheetsOnly()
    On Error GoTo AbilityError

    SetupAbilitiesSheet
    SetupEnemyAbilitiesSheet

    MsgBox "Ability sheets created successfully!" & vbCrLf & vbCrLf & _
           "Sheets created: Abilities, EnemyAbilities", _
           vbInformation, "Setup Complete"
    Exit Sub

AbilityError:
    MsgBox "Error creating ability sheets:" & vbCrLf & vbCrLf & _
           "Error " & Err.Number & ": " & Err.Description, vbCritical, "Setup Error"
End Sub
