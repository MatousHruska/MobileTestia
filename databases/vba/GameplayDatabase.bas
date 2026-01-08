Attribute VB_Name = "GameplayDatabase"
'===============================================================================
' GameplayDatabase Module
' Handles validation and export for Consumables, StatusEffects, Zones, and GameplaySettings
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_CONSUMABLES As String = "Consumables"
Private Const SHEET_STATUS_EFFECTS As String = "StatusEffects"
Private Const SHEET_ZONES As String = "Zones"
Private Const SHEET_GAMEPLAY_SETTINGS As String = "GameplaySettings"

' Column indices for Consumables (1-based)
Private Const COL_CON_ID As Integer = 1
Private Const COL_CON_NAME As Integer = 2
Private Const COL_CON_TYPE As Integer = 3
Private Const COL_CON_EFFECT_TYPE As Integer = 4
Private Const COL_CON_EFFECT_VALUE As Integer = 5
Private Const COL_CON_DURATION As Integer = 6
Private Const COL_CON_COOLDOWN As Integer = 7
Private Const COL_CON_STACK_SIZE As Integer = 8
Private Const COL_CON_PRICE_BASE As Integer = 9
Private Const COL_CON_DESCRIPTION As Integer = 10

' Column indices for StatusEffects
Private Const COL_SE_ID As Integer = 1
Private Const COL_SE_NAME As Integer = 2
Private Const COL_SE_TYPE As Integer = 3
Private Const COL_SE_STAT_AFFECTED As Integer = 4
Private Const COL_SE_VALUE As Integer = 5
Private Const COL_SE_DURATION As Integer = 6
Private Const COL_SE_TICK_INTERVAL As Integer = 7
Private Const COL_SE_VISUAL_EFFECT As Integer = 8
Private Const COL_SE_STACKABLE As Integer = 9
Private Const COL_SE_MAX_STACKS As Integer = 10
Private Const COL_SE_SHOW_IN_HUD As Integer = 11
Private Const COL_SE_ICON_COLOR As Integer = 12
Private Const COL_SE_DESCRIPTION As Integer = 13

' Column indices for Zones
' NOTE: enemy_spawn_list and respawn_time removed - use SpawnPoints database instead
Private Const COL_ZN_ID As Integer = 1
Private Const COL_ZN_NAME As Integer = 2
Private Const COL_ZN_ZONE_TYPE As Integer = 3
Private Const COL_ZN_MIN_LEVEL As Integer = 4
Private Const COL_ZN_MAX_LEVEL As Integer = 5
Private Const COL_ZN_MUSIC_TRACK As Integer = 6
Private Const COL_ZN_AMBIENT_SOUND As Integer = 7
Private Const COL_ZN_IS_SAFE_ZONE As Integer = 8
Private Const COL_ZN_IS_PVP_ENABLED As Integer = 9
Private Const COL_ZN_STATUS_EFFECT_ID As Integer = 10
Private Const COL_ZN_DISCOVERY_POPUP As Integer = 11
Private Const COL_ZN_DESCRIPTION As Integer = 12

' Column indices for GameplaySettings (key-value pairs)
Private Const COL_GS_KEY As Integer = 1
Private Const COL_GS_VALUE As Integer = 2
Private Const COL_GS_DESCRIPTION As Integer = 3

' Valid dropdown values
Private validConsumableTypes() As String
Private validEffectTypes() As String
Private validStatusTypes() As String
Private validZoneTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validConsumableTypes = Split("potion,scroll,food,elixir", ",")
    validEffectTypes = Split("heal_health,heal_mana,buff_stat,cure_status,teleport_town,resurrect", ",")
    validStatusTypes = Split("buff,debuff,debuff_dot,buff_hot,control", ",")
    validZoneTypes = Split("outdoor,dungeon,cave,town,boss_room,camp", ",")
End Sub

'===============================================================================
' CONSUMABLES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateConsumables - Validates all rows in Consumables sheet
'-------------------------------------------------------------------------------
Public Sub ValidateConsumables()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CONSUMABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CONSUMABLES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CON_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CON_ID).value)

        If Len(id) = 0 Then GoTo NextConsumable

        ' Validate ID format
        If Not ValidateId(id, "con_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: con_type_name (e.g., con_potion_health_small)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_CON_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate consumable type
        Dim conType As String
        conType = LCase(Trim(ws.Cells(i, COL_CON_TYPE).value))
        If Len(conType) > 0 And Not ValidateDropdown(conType, validConsumableTypes) Then
            LogValidationError errors, errorCount, i, "Consumable Type", _
                "Invalid type. Valid: potion, scroll, food, elixir"
        End If

        ' Validate effect type
        Dim effectType As String
        effectType = LCase(Trim(ws.Cells(i, COL_CON_EFFECT_TYPE).value))
        If Len(effectType) > 0 And Not ValidateDropdown(effectType, validEffectTypes) Then
            LogValidationError errors, errorCount, i, "Effect Type", _
                "Invalid effect type. Valid: heal_health, heal_mana, buff_stat, cure_status, teleport_town, resurrect"
        End If

        ' Validate numeric fields non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_CON_DURATION)) < 0 Then
            LogValidationError errors, errorCount, i, "Duration", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_CON_COOLDOWN)) < 0 Then
            LogValidationError errors, errorCount, i, "Cooldown", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_CON_STACK_SIZE)) < 0 Then
            LogValidationError errors, errorCount, i, "Stack Size", "Cannot be negative"
        End If

NextConsumable:
    Next i

    ShowValidationResults errors, errorCount, "Consumables"
End Sub

'-------------------------------------------------------------------------------
' ExportConsumables - Exports Consumables to JSON
'-------------------------------------------------------------------------------
Public Sub ExportConsumables()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CONSUMABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CONSUMABLES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""consumables"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CON_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CON_ID).value)

        If Len(id) = 0 Then GoTo NextExportConsumable

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CON_NAME))) & """," & vbCrLf
        json = json & "      ""consumable_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CON_TYPE), "potion"))) & """," & vbCrLf
        json = json & "      ""effect_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CON_EFFECT_TYPE), "heal_health"))) & """," & vbCrLf
        json = json & "      ""effect_value"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CON_EFFECT_VALUE))) & "," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CON_DURATION))) & "," & vbCrLf
        json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CON_COOLDOWN))) & "," & vbCrLf
        json = json & "      ""stack_size"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CON_STACK_SIZE), 20)) & "," & vbCrLf
        json = json & "      ""price_base"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CON_PRICE_BASE), 10)) & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportConsumable:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "consumables.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " consumables to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' STATUS EFFECTS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateStatusEffects - Validates all rows in StatusEffects sheet
'-------------------------------------------------------------------------------
Public Sub ValidateStatusEffects()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_STATUS_EFFECTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_STATUS_EFFECTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SE_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SE_ID).value)

        If Len(id) = 0 Then GoTo NextStatusEffect

        ' Validate ID format
        If Not ValidateId(id, "status_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: status_name (e.g., status_poison)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_SE_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate status type
        Dim statusType As String
        statusType = LCase(Trim(ws.Cells(i, COL_SE_TYPE).value))
        If Len(statusType) > 0 And Not ValidateDropdown(statusType, validStatusTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: buff, debuff, debuff_dot, buff_hot, control"
        End If

        ' Validate duration >= 0
        If GetDefaultNumeric(ws.Cells(i, COL_SE_DURATION)) < 0 Then
            LogValidationError errors, errorCount, i, "Duration", "Cannot be negative"
        End If

        ' Validate tick_interval >= 0
        If GetDefaultNumeric(ws.Cells(i, COL_SE_TICK_INTERVAL)) < 0 Then
            LogValidationError errors, errorCount, i, "Tick Interval", "Cannot be negative"
        End If

NextStatusEffect:
    Next i

    ShowValidationResults errors, errorCount, "StatusEffects"
End Sub

'-------------------------------------------------------------------------------
' ExportStatusEffects - Exports StatusEffects to JSON
'-------------------------------------------------------------------------------
Public Sub ExportStatusEffects()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_STATUS_EFFECTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_STATUS_EFFECTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""status_effects"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SE_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SE_ID).value)

        If Len(id) = 0 Then GoTo NextExportStatusEffect

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Handle boolean stackable field
        Dim stackable As String
        stackable = LCase(Trim(ws.Cells(i, COL_SE_STACKABLE).value))
        If stackable = "true" Or stackable = "1" Or stackable = "yes" Then
            stackable = "true"
        Else
            stackable = "false"
        End If

        ' Handle boolean show_in_hud field (default true)
        Dim showInHud As String
        showInHud = LCase(Trim(ws.Cells(i, COL_SE_SHOW_IN_HUD).value))
        If showInHud = "false" Or showInHud = "0" Or showInHud = "no" Then
            showInHud = "false"
        Else
            showInHud = "true"
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SE_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SE_TYPE), "buff"))) & """," & vbCrLf
        json = json & "      ""stat_affected"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SE_STAT_AFFECTED), "health"))) & """," & vbCrLf
        json = json & "      ""value"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SE_VALUE))) & "," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SE_DURATION))) & "," & vbCrLf
        json = json & "      ""tick_interval"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SE_TICK_INTERVAL), 1)) & "," & vbCrLf
        json = json & "      ""visual_effect"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SE_VISUAL_EFFECT))) & """," & vbCrLf
        json = json & "      ""stackable"": " & stackable & "," & vbCrLf
        json = json & "      ""max_stacks"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SE_MAX_STACKS), 1)) & "," & vbCrLf
        json = json & "      ""show_in_hud"": " & showInHud & "," & vbCrLf
        json = json & "      ""icon_color"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SE_ICON_COLOR))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportStatusEffect:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "status_effects.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " status effects to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' ZONES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateZones - Validates all rows in Zones sheet
'-------------------------------------------------------------------------------
Public Sub ValidateZones()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ZONES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ZONES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ZN_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ZN_ID).value)

        If Len(id) = 0 Then GoTo NextZone

        ' Validate ID format
        If Not ValidateId(id, "zone_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: zone_name (e.g., zone_dark_forest)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_ZN_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate zone type
        Dim zoneType As String
        zoneType = LCase(Trim(ws.Cells(i, COL_ZN_ZONE_TYPE).value))
        If Len(zoneType) > 0 And Not ValidateDropdown(zoneType, validZoneTypes) Then
            LogValidationError errors, errorCount, i, "Zone Type", _
                "Invalid type. Valid: outdoor, dungeon, cave, town, boss_room, camp"
        End If

        ' Validate min <= max level
        Dim minLevel As Double, maxLevel As Double
        minLevel = GetDefaultNumeric(ws.Cells(i, COL_ZN_MIN_LEVEL), 1)
        maxLevel = GetDefaultNumeric(ws.Cells(i, COL_ZN_MAX_LEVEL), 100)
        If minLevel > maxLevel Then
            LogValidationError errors, errorCount, i, "Min/Max Level", _
                "Min level cannot be greater than max level"
        End If

NextZone:
    Next i

    ShowValidationResults errors, errorCount, "Zones"
End Sub

'-------------------------------------------------------------------------------
' ExportZones - Exports Zones to JSON
'-------------------------------------------------------------------------------
Public Sub ExportZones()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ZONES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ZONES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""zones"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ZN_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ZN_ID).value)

        If Len(id) = 0 Then GoTo NextExportZone

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Handle boolean fields
        Dim isSafeZone As String
        isSafeZone = LCase(Trim(ws.Cells(i, COL_ZN_IS_SAFE_ZONE).value))
        If isSafeZone = "true" Or isSafeZone = "1" Or isSafeZone = "yes" Then
            isSafeZone = "true"
        Else
            isSafeZone = "false"
        End If

        Dim isPvpEnabled As String
        isPvpEnabled = LCase(Trim(ws.Cells(i, COL_ZN_IS_PVP_ENABLED).value))
        If isPvpEnabled = "true" Or isPvpEnabled = "1" Or isPvpEnabled = "yes" Then
            isPvpEnabled = "true"
        Else
            isPvpEnabled = "false"
        End If

        Dim discoveryPopup As String
        discoveryPopup = LCase(Trim(ws.Cells(i, COL_ZN_DISCOVERY_POPUP).value))
        If discoveryPopup = "true" Or discoveryPopup = "1" Or discoveryPopup = "yes" Then
            discoveryPopup = "true"
        Else
            discoveryPopup = "false"
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ZN_NAME))) & """," & vbCrLf
        json = json & "      ""zone_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_ZN_ZONE_TYPE), "outdoor"))) & """," & vbCrLf
        json = json & "      ""min_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZN_MIN_LEVEL), 1)) & "," & vbCrLf
        json = json & "      ""max_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ZN_MAX_LEVEL), 100)) & "," & vbCrLf
        json = json & "      ""music_track"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ZN_MUSIC_TRACK))) & """," & vbCrLf
        json = json & "      ""ambient_sound"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ZN_AMBIENT_SOUND))) & """," & vbCrLf
        json = json & "      ""is_safe_zone"": " & isSafeZone & "," & vbCrLf
        json = json & "      ""is_pvp_enabled"": " & isPvpEnabled & "," & vbCrLf
        json = json & "      ""status_effect_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ZN_STATUS_EFFECT_ID))) & """," & vbCrLf
        json = json & "      ""discovery_popup"": " & discoveryPopup & "," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ZN_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportZone:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "zones.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " zones to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' MASTER EXPORT
'===============================================================================

'===============================================================================
' GAMEPLAY SETTINGS
'===============================================================================

'-------------------------------------------------------------------------------
' ExportGameplaySettings - Exports GameplaySettings to JSON (key-value pairs)
'-------------------------------------------------------------------------------
Public Sub ExportGameplaySettings()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_GAMEPLAY_SETTINGS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_GAMEPLAY_SETTINGS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_GS_KEY).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim keyName As String
        keyName = Trim(ws.Cells(i, COL_GS_KEY).value)

        If Len(keyName) = 0 Then GoTo NextExportSetting

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Export as number (all gameplay settings are numeric)
        json = json & "  """ & EscapeJsonString(keyName) & """: " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_GS_VALUE)))

        itemCount = itemCount + 1

NextExportSetting:
    Next i

    json = json & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "gameplay_settings.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " gameplay settings to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupGameplaySettingsSheet - Creates GameplaySettings sheet with headers
' This sheet contains ALL base numeric values for the game:
' - Primary stat starting values (base_vitality, base_strength, etc.)
' - Stat conversion constants (health_per_vitality, mana_per_energy, etc.)
' - Flat base values (health_base_flat, crit_chance_base, etc.)
' - Regeneration rates (base_life_regen, base_mana_regen, etc.)
' - Movement/combat defaults (base_move_speed, base_lunge_force, etc.)
' - Skill defaults for multiplier system (base_hit_range, base_projectile_speed, etc.)
' - Combat constants (armor_constant, etc.)
'-------------------------------------------------------------------------------
Public Sub SetupGameplaySettingsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_GAMEPLAY_SETTINGS)
    Dim headers As Variant
    headers = Array("key", "value", "description")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Setting key name (e.g., armor_constant, base_vitality, health_per_vitality)"
    SafeAddComment ws.Cells(1, 2), "Numeric value for the setting"
    SafeAddComment ws.Cells(1, 3), "Description of what this setting controls"
End Sub

'-------------------------------------------------------------------------------
' SetupZonesSheet - Creates Zones sheet with headers
' NOTE: enemy_spawn_list and respawn_time removed - use SpawnPoints database instead
'-------------------------------------------------------------------------------
Public Sub SetupZonesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_ZONES)

    Dim headers As Variant
    headers = Array("id", "name", "zone_type", "min_level", "max_level", _
                    "music_track", "ambient_sound", "is_safe_zone", "is_pvp_enabled", _
                    "status_effect_id", "discovery_popup", "description")

    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: zone_name (e.g., zone_meadow, zone_dark_forest)"
    SafeAddComment ws.Cells(1, 2), "Display name shown to player"
    SafeAddComment ws.Cells(1, 3), "outdoor, dungeon, cave, town, boss_room, camp"
    SafeAddComment ws.Cells(1, 4), "Minimum recommended player level"
    SafeAddComment ws.Cells(1, 5), "Maximum recommended player level"
    SafeAddComment ws.Cells(1, 6), "Music track to play in this zone"
    SafeAddComment ws.Cells(1, 7), "Ambient sound to play in this zone"
    SafeAddComment ws.Cells(1, 8), "TRUE/FALSE - combat disabled in safe zones"
    SafeAddComment ws.Cells(1, 9), "TRUE/FALSE - PvP combat allowed"
    SafeAddComment ws.Cells(1, 10), "Status effect applied while in zone (e.g., status_cold)"
    SafeAddComment ws.Cells(1, 11), "TRUE/FALSE - show discovery popup on first visit"
    SafeAddComment ws.Cells(1, 12), "Flavor text description of the zone"

    MsgBox "Zones sheet setup complete!" & vbCrLf & vbCrLf & _
           "NOTE: Enemy spawns are now configured in the SpawnPoints sheet.", vbInformation
End Sub

'-------------------------------------------------------------------------------
' ExportAllGameplay - Exports all gameplay-related sheets
'-------------------------------------------------------------------------------
Public Sub ExportAllGameplay()
    ExportConsumables
    ExportStatusEffects
    ExportZones
    ExportGameplaySettings
    MsgBox "All gameplay databases exported!", vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ValidateAllGameplay - Validates all gameplay-related sheets
'-------------------------------------------------------------------------------
Public Sub ValidateAllGameplay()
    ValidateConsumables
    ValidateStatusEffects
    ValidateZones
End Sub
