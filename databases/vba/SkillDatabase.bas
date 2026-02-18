Attribute VB_Name = "SkillDatabase"
'===============================================================================
' SkillDatabase Module
' Handles validation and export for Player Talents and Talent Trees
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_TALENTS As String = "Talents"
Private Const SHEET_TALENT_TREES As String = "TalentTrees"

' Column indices for Talents (1-based)
Private Const COL_TAL_ID As Integer = 1
Private Const COL_TAL_NAME As Integer = 2
Private Const COL_TAL_TREE As Integer = 3           ' tree_noble_legacy, etc.
Private Const COL_TAL_ROW As Integer = 4            ' 1-5+ (vertical position)
Private Const COL_TAL_COLUMN As Integer = 5         ' 1-3 (horizontal position)
Private Const COL_TAL_MAX_POINTS As Integer = 6     ' 1-5
Private Const COL_TAL_TYPE As Integer = 7           ' active, passive
Private Const COL_TAL_SKILL_CATEGORY As Integer = 8 ' melee, ranged, magic
Private Const COL_TAL_AUTO_LEARN As Integer = 9     ' true/false - auto-learned at game start
Private Const COL_TAL_WEAPON_DAMAGE_PERCENT As Integer = 10 ' e.g., 150 = 150% weapon damage
Private Const COL_TAL_FLAT_DAMAGE_BONUS As Integer = 11     ' flat damage added before %
Private Const COL_TAL_DAMAGE_TYPE As Integer = 12   ' physical, fire, cold, lightning, arcane
Private Const COL_TAL_LUNGE_FORCE As Integer = 13   ' Lunge force when using skill
Private Const COL_TAL_RECOVERY_TIME As Integer = 14 ' Recovery lockout after skill
Private Const COL_TAL_HIT_RANGE As Integer = 15     ' Attack range in pixels
Private Const COL_TAL_HIT_ARC As Integer = 16       ' Hit arc in degrees (360=all around)
Private Const COL_TAL_PREREQUISITE_IDS As Integer = 17
Private Const COL_TAL_MANA_COST As Integer = 18
Private Const COL_TAL_STAMINA_COST As Integer = 19
Private Const COL_TAL_COOLDOWN As Integer = 20
Private Const COL_TAL_BASE_DAMAGE As Integer = 21   ' For magic skills: base flat damage
Private Const COL_TAL_DAMAGE_PER_RANK As Integer = 22 ' Magic skill damage per rank (1-20)
Private Const COL_TAL_EFFECT_TYPE As Integer = 23   ' damage, heal, buff, debuff, projectile
Private Const COL_TAL_EFFECT_VALUE As Integer = 24
Private Const COL_TAL_EFFECT_PER_POINT As Integer = 25
Private Const COL_TAL_DURATION As Integer = 26
Private Const COL_TAL_STAT_BONUSES As Integer = 27  ' For passive: "strength:2;armor:5"
Private Const COL_TAL_DESCRIPTION As Integer = 28
Private Const COL_TAL_RANK_DESCRIPTIONS As Integer = 29  ' "Rank 1 desc|Rank 2 desc|..."
Private Const COL_TAL_ICON_NAME As Integer = 30
Private Const COL_TAL_REQUIRED_WEAPON_CATEGORY As Integer = 31  ' melee, melee_1h, melee_2h, ranged, magic
Private Const COL_TAL_MIN_CHARGE_TIME As Integer = 32           ' Minimum charge time for full power (projectiles)
Private Const COL_TAL_WEAK_SHOT_DAMAGE_PCT As Integer = 33      ' Damage % for quick/weak shot (e.g., 30)
Private Const COL_TAL_WEAK_SHOT_RANGE_PCT As Integer = 34       ' Range % for quick/weak shot (e.g., 30)
Private Const COL_TAL_CAST_TIME As Integer = 35                 ' Cast time before firing (magic skills)
Private Const COL_TAL_EXPLOSION_RADIUS As Integer = 36          ' AOE explosion radius (magic projectiles)
Private Const COL_TAL_CONTACT_STATUS_EFFECT As Integer = 37     ' Status effect applied on projectile contact
Private Const COL_TAL_PROJECTILE_SPEED As Integer = 38          ' Projectile travel speed
Private Const COL_TAL_MAX_CHARGE_TIME As Integer = 39           ' Maximum charge time for full power (ranged)
Private Const COL_TAL_BASE_RANGE As Integer = 40                ' Base range at minimum charge (ranged)
Private Const COL_TAL_LUNGE_DURATION As Integer = 41            ' Duration of lunge movement (melee)
Private Const COL_TAL_EXPLOSION_FALLOFF As Integer = 42         ' Damage falloff % at explosion edge (magic)
Private Const COL_TAL_CAN_MOVE_WHILE_CASTING As Integer = 43    ' Can player move while casting? (bool)
Private Const COL_TAL_INTERRUPT_ON_DAMAGE As Integer = 44       ' Does taking damage interrupt cast? (bool)
Private Const COL_TAL_VISUAL_TYPE As Integer = 45               ' Visual template override (e.g., melee_single, spell_cast)
Private Const COL_TAL_SHOW_WEAPON As Integer = 46               ' Show weapon during spell casting (true/false)
Private Const COL_TAL_WINDUP_TIME As Integer = 47               ' Seconds before attack hits (0 = use anim length)
Private Const COL_TAL_HIT_EFFECT As Integer = 48                ' VFX effect ID per-skill (empty = template default)
Private Const COL_TAL_HIT_COUNT As Integer = 49                 ' Combo hit count (0 = template default)

' Column indices for TalentTrees (1-based)
Private Const COL_TT_ID As Integer = 1
Private Const COL_TT_NAME As Integer = 2
Private Const COL_TT_DESCRIPTION As Integer = 3
Private Const COL_TT_ICON_NAME As Integer = 4

' Valid dropdown values
Private validTalentTypes() As String
Private validEffectTypes() As String
Private validSkillCategories() As String
Private validDamageTypes() As String
Private validRequiredWeaponCategories() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validTalentTypes = Split("active,passive", ",")
    validEffectTypes = Split("damage,heal,buff,debuff,projectile,magic_projectile,summon,teleport,aoe,self_buff", ",")
    validSkillCategories = Split("melee,ranged,magic", ",")
    validDamageTypes = Split("physical,fire,cold,lightning,poison,arcane,holy,shadow", ",")
    ' Weapon categories: melee matches melee_1h AND melee_2h, specific ones match exactly
    validRequiredWeaponCategories = Split("melee,melee_1h,melee_2h,ranged,magic", ",")
End Sub

'===============================================================================
' TALENT TREES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateTalentTrees - Validates all rows in TalentTrees sheet
'-------------------------------------------------------------------------------
Public Sub ValidateTalentTrees()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TALENT_TREES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TALENT_TREES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TT_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TT_ID).value)

        If Len(id) = 0 Then GoTo NextTree

        ' Validate ID format
        If Not ValidateId(id, "tree_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: tree_name (e.g., tree_noble_legacy)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_TT_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

NextTree:
    Next i

    ShowValidationResults errors, errorCount, "TalentTrees"
End Sub

'-------------------------------------------------------------------------------
' ExportTalentTrees - Exports TalentTrees to JSON
'-------------------------------------------------------------------------------
Public Sub ExportTalentTrees()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TALENT_TREES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TALENT_TREES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""talent_trees"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TT_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TT_ID).value)

        If Len(id) = 0 Then GoTo NextExportTree

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""icon_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TT_ICON_NAME), id)) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportTree:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "talent_trees.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " talent trees to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' TALENTS (formerly Skills)
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateTalents - Validates all rows in Talents sheet
'-------------------------------------------------------------------------------
Public Sub ValidateTalents()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TALENTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TALENTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TAL_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TAL_ID).value)

        If Len(id) = 0 Then GoTo NextTalent

        ' Validate ID format
        If Not ValidateId(id, "tal_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: tal_tree_name (e.g., tal_noble_powerstrike)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_TAL_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate talent type
        Dim talentType As String
        talentType = LCase(Trim(ws.Cells(i, COL_TAL_TYPE).value))
        If Len(talentType) > 0 And Not ValidateDropdown(talentType, validTalentTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: active, passive"
        End If

        ' Validate row 1-10
        Dim talentRow As Double
        talentRow = GetDefaultNumeric(ws.Cells(i, COL_TAL_ROW), 1)
        If talentRow < 1 Or talentRow > 10 Then
            LogValidationError errors, errorCount, i, "Row", "Row must be between 1 and 10"
        End If

        ' Validate column 1-3
        Dim talentCol As Double
        talentCol = GetDefaultNumeric(ws.Cells(i, COL_TAL_COLUMN), 1)
        If talentCol < 1 Or talentCol > 3 Then
            LogValidationError errors, errorCount, i, "Column", "Column must be between 1 and 3"
        End If

        ' Validate max_points 1-5
        Dim maxPoints As Double
        maxPoints = GetDefaultNumeric(ws.Cells(i, COL_TAL_MAX_POINTS), 1)
        If maxPoints < 1 Or maxPoints > 5 Then
            LogValidationError errors, errorCount, i, "Max Points", "Max points must be between 1 and 5"
        End If

        ' Validate costs non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_TAL_MANA_COST)) < 0 Then
            LogValidationError errors, errorCount, i, "Mana Cost", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_TAL_STAMINA_COST)) < 0 Then
            LogValidationError errors, errorCount, i, "Stamina Cost", "Cannot be negative"
        End If

        ' Validate visual_type (if present)
        Dim visualType As String
        visualType = LCase(Trim(ws.Cells(i, COL_TAL_VISUAL_TYPE).value))
        If Len(visualType) > 0 Then
            Dim validVisualTypes() As String
            validVisualTypes = Split("melee_single,melee_combo_2,melee_combo_3,dash_attack,ranged_aim,ranged_attack,spell_cast,spell_instant,throw,self_buff,howl", ",")
            If Not ValidateDropdown(visualType, validVisualTypes) Then
                LogValidationError errors, errorCount, i, "visual_type", _
                    "Invalid visual_type: " & visualType
            End If
        End If

        ' Validate windup_time >= 0
        Dim windupTime As Double
        windupTime = GetDefaultNumeric(ws.Cells(i, COL_TAL_WINDUP_TIME))
        If windupTime < 0 Then
            LogValidationError errors, errorCount, i, "windup_time", "Cannot be negative"
        End If

        ' Validate hit_count 0-10
        Dim hitCount As Double
        hitCount = GetDefaultNumeric(ws.Cells(i, COL_TAL_HIT_COUNT))
        If hitCount < 0 Or hitCount > 10 Then
            LogValidationError errors, errorCount, i, "hit_count", "Must be between 0 and 10"
        End If

        ' Validate required_weapon_category for active talents
        If talentType = "active" Then
            Dim reqWeaponCat As String
            reqWeaponCat = LCase(Trim(ws.Cells(i, COL_TAL_REQUIRED_WEAPON_CATEGORY).value))
            If Len(reqWeaponCat) > 0 And Not ValidateDropdown(reqWeaponCat, validRequiredWeaponCategories) Then
                LogValidationError errors, errorCount, i, "Required Weapon Category", _
                    "Invalid category. Valid: melee, melee_1h, melee_2h, ranged, magic"
            End If
        End If

NextTalent:
    Next i

    ShowValidationResults errors, errorCount, "Talents"
End Sub

'-------------------------------------------------------------------------------
' ValidateSkills - Alias for ValidateTalents (backward compatibility)
'-------------------------------------------------------------------------------
Public Sub ValidateSkills()
    ValidateTalents
End Sub

'-------------------------------------------------------------------------------
' ExportTalents - Exports Talents to JSON
'-------------------------------------------------------------------------------
Public Sub ExportTalents()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TALENTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TALENTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""talents"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_TAL_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_TAL_ID).value)

        If Len(id) = 0 Then GoTo NextExportTalent

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_NAME))) & """," & vbCrLf
        json = json & "      ""tree"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_TREE)))) & """," & vbCrLf
        json = json & "      ""row"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_ROW), 1)) & "," & vbCrLf
        json = json & "      ""column"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_COLUMN), 1)) & "," & vbCrLf
        json = json & "      ""max_points"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_MAX_POINTS), 1)) & "," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_TYPE), "passive"))) & """," & vbCrLf
        json = json & "      ""skill_category"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_SKILL_CATEGORY)))) & """," & vbCrLf
        json = json & "      ""auto_learn"": " & LCase(GetDefaultString(ws.Cells(i, COL_TAL_AUTO_LEARN), "false")) & "," & vbCrLf
        json = json & "      ""weapon_damage_percent"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_WEAPON_DAMAGE_PERCENT))) & "," & vbCrLf
        json = json & "      ""flat_damage_bonus"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_FLAT_DAMAGE_BONUS))) & "," & vbCrLf
        json = json & "      ""damage_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_DAMAGE_TYPE), "physical"))) & """," & vbCrLf
        json = json & "      ""lunge_force"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_LUNGE_FORCE))) & "," & vbCrLf
        json = json & "      ""recovery_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_RECOVERY_TIME))) & "," & vbCrLf
        json = json & "      ""hit_range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_HIT_RANGE), 50)) & "," & vbCrLf
        json = json & "      ""hit_arc"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_HIT_ARC), 360)) & "," & vbCrLf
        json = json & "      ""prerequisite_ids"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_PREREQUISITE_IDS))) & """," & vbCrLf
        json = json & "      ""mana_cost"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_MANA_COST))) & "," & vbCrLf
        json = json & "      ""stamina_cost"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_STAMINA_COST))) & "," & vbCrLf
        json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_COOLDOWN))) & "," & vbCrLf
        json = json & "      ""base_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_BASE_DAMAGE))) & "," & vbCrLf
        json = json & "      ""damage_per_rank"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_DAMAGE_PER_RANK))) & "," & vbCrLf
        json = json & "      ""effect_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_EFFECT_TYPE)))) & """," & vbCrLf
        json = json & "      ""effect_value"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_EFFECT_VALUE))) & "," & vbCrLf
        json = json & "      ""effect_per_point"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_EFFECT_PER_POINT))) & "," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_DURATION))) & "," & vbCrLf
        json = json & "      ""stat_bonuses"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_STAT_BONUSES))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""rank_descriptions"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_RANK_DESCRIPTIONS))) & """," & vbCrLf
        json = json & "      ""icon_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_ICON_NAME), id)) & """," & vbCrLf
        json = json & "      ""required_weapon_category"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TAL_REQUIRED_WEAPON_CATEGORY)))) & """," & vbCrLf
        json = json & "      ""min_charge_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_MIN_CHARGE_TIME))) & "," & vbCrLf
        json = json & "      ""weak_shot_damage_percent"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_WEAK_SHOT_DAMAGE_PCT))) & "," & vbCrLf
        json = json & "      ""weak_shot_range_percent"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_WEAK_SHOT_RANGE_PCT))) & "," & vbCrLf
        json = json & "      ""cast_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_CAST_TIME))) & "," & vbCrLf
        json = json & "      ""explosion_radius"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_EXPLOSION_RADIUS))) & "," & vbCrLf
        json = json & "      ""contact_status_effect"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_CONTACT_STATUS_EFFECT))) & """," & vbCrLf
        json = json & "      ""projectile_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_PROJECTILE_SPEED))) & "," & vbCrLf
        json = json & "      ""max_charge_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_MAX_CHARGE_TIME))) & "," & vbCrLf
        json = json & "      ""base_range"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_BASE_RANGE))) & "," & vbCrLf
        json = json & "      ""lunge_duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_LUNGE_DURATION))) & "," & vbCrLf
        json = json & "      ""explosion_falloff"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_EXPLOSION_FALLOFF))) & "," & vbCrLf
        json = json & "      ""can_move_while_casting"": " & LCase(GetDefaultString(ws.Cells(i, COL_TAL_CAN_MOVE_WHILE_CASTING), "false")) & "," & vbCrLf
        json = json & "      ""interrupt_on_damage"": " & LCase(GetDefaultString(ws.Cells(i, COL_TAL_INTERRUPT_ON_DAMAGE), "true")) & "," & vbCrLf
        json = json & "      ""visual_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_VISUAL_TYPE))) & """," & vbCrLf
        json = json & "      ""show_weapon"": " & LCase(GetDefaultString(ws.Cells(i, COL_TAL_SHOW_WEAPON), "false")) & "," & vbCrLf
        json = json & "      ""windup_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_WINDUP_TIME))) & "," & vbCrLf
        json = json & "      ""hit_effect"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TAL_HIT_EFFECT))) & """," & vbCrLf
        json = json & "      ""hit_count"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_TAL_HIT_COUNT))) & "" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportTalent:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "talents.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " talents to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ExportSkills - Alias for ExportTalents (backward compatibility)
'-------------------------------------------------------------------------------
Public Sub ExportSkills()
    ExportTalents
End Sub

'-------------------------------------------------------------------------------
' SetupTalentTreesSheet - Creates TalentTrees sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupTalentTreesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_TALENT_TREES)
    Dim headers As Variant
    headers = Array("id", "name", "description", "icon_name")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: tree_name (e.g., tree_noble_legacy)"
    SafeAddComment ws.Cells(1, 3), "Short description shown in the talent tree tab"
End Sub

'-------------------------------------------------------------------------------
' SetupTalentsSheet - Creates Talents sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupTalentsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_TALENTS)
    Dim headers As Variant
    headers = Array("id", "name", "tree", "row", "column", "max_points", "type", _
                    "skill_category", "auto_learn", "weapon_damage_percent", "flat_damage_bonus", _
                    "damage_type", "lunge_force", "recovery_time", "hit_range", "hit_arc", _
                    "prerequisite_ids", "mana_cost", "stamina_cost", "cooldown", _
                    "base_damage", "damage_per_rank", "effect_type", "effect_value", _
                    "effect_per_point", "duration", "stat_bonuses", "description", _
                    "rank_descriptions", "icon_name", "required_weapon_category", _
                    "min_charge_time", "weak_shot_damage_percent", "weak_shot_range_percent", _
                    "cast_time", "explosion_radius", "contact_status_effect", "projectile_speed", _
                    "max_charge_time", "base_range", "lunge_duration", "explosion_falloff", _
                    "can_move_while_casting", "interrupt_on_damage", "visual_type", "show_weapon", _
                    "windup_time", "hit_effect", "hit_count")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: tal_tree_name (e.g., tal_noble_powerstrike)"
    SafeAddComment ws.Cells(1, 3), "Reference to TalentTrees id (e.g., tree_noble_legacy)"
    SafeAddComment ws.Cells(1, 4), "Vertical position in tree (1-10). Row 1 = top"
    SafeAddComment ws.Cells(1, 5), "Horizontal position in tree (1-3). 1=left, 2=center, 3=right"
    SafeAddComment ws.Cells(1, 6), "Maximum points investable (1-5, or 1 for active)"
    SafeAddComment ws.Cells(1, 7), "active = appears in skillbook, passive = stat bonus only"
    SafeAddComment ws.Cells(1, 8), "melee, ranged, or magic - determines damage formula"
    SafeAddComment ws.Cells(1, 9), "true/false - if true, skill is auto-learned at game start"
    SafeAddComment ws.Cells(1, 10), "For melee/ranged: % of weapon damage (e.g., 150 = 150%)"
    SafeAddComment ws.Cells(1, 11), "Flat damage added before % calculation"
    SafeAddComment ws.Cells(1, 12), "physical, fire, cold, lightning, poison, arcane, holy, shadow"
    SafeAddComment ws.Cells(1, 13), "Lunge force applied when using skill (e.g., 80)"
    SafeAddComment ws.Cells(1, 14), "Recovery lockout time in seconds (e.g., 0.3)"
    SafeAddComment ws.Cells(1, 15), "Attack range in pixels (default 50)"
    SafeAddComment ws.Cells(1, 16), "Hit arc in degrees (360=all around, 90=forward cone)"
    SafeAddComment ws.Cells(1, 17), "Comma-separated talent IDs. Must be MAXED to unlock"
    SafeAddComment ws.Cells(1, 21), "For magic: base flat damage at rank 1"
    SafeAddComment ws.Cells(1, 22), "For magic: additional damage per rank (1-20)"
    SafeAddComment ws.Cells(1, 27), "For passive: stat:value_per_point pairs (e.g., strength:2;armor:5)"
    SafeAddComment ws.Cells(1, 29), "Pipe-separated descriptions per rank"
    SafeAddComment ws.Cells(1, 31), "Required weapon: melee (any), melee_1h, melee_2h, ranged, magic"
    SafeAddComment ws.Cells(1, 32), "Projectiles: min seconds to charge for full damage (e.g., 0.5)"
    SafeAddComment ws.Cells(1, 33), "Projectiles: damage % for quick shot below min_charge_time (e.g., 30)"
    SafeAddComment ws.Cells(1, 34), "Projectiles: range % for quick shot below min_charge_time (e.g., 30)"
    SafeAddComment ws.Cells(1, 35), "Magic: cast time in seconds before spell fires (e.g., 0.2)"
    SafeAddComment ws.Cells(1, 36), "Magic projectile: AOE explosion radius in pixels (e.g., 60)"
    SafeAddComment ws.Cells(1, 37), "Status effect ID applied on projectile contact (e.g., status_burning)"
    SafeAddComment ws.Cells(1, 38), "Projectile travel speed in pixels/sec (e.g., 350)"
    SafeAddComment ws.Cells(1, 39), "Ranged: max charge time in seconds for full range (default 2.0)"
    SafeAddComment ws.Cells(1, 40), "Ranged: base range at minimum charge in pixels (default 150)"
    SafeAddComment ws.Cells(1, 41), "Melee: lunge movement duration in seconds (default 0.1)"
    SafeAddComment ws.Cells(1, 42), "Magic: damage falloff % at explosion edge (default 30, 0=no falloff)"
    SafeAddComment ws.Cells(1, 43), "Cast: Can player move while casting? (true/false, default false)"
    SafeAddComment ws.Cells(1, 44), "Cast: Does taking damage interrupt cast? (true/false, default true)"
    SafeAddComment ws.Cells(1, 45), "Visual template: melee_single, melee_combo_2, melee_combo_3, dash_attack, ranged_aim, spell_cast, spell_instant, throw, self_buff (empty=auto)"
    SafeAddComment ws.Cells(1, 46), "Show weapon during spell casting (true/false, default false). Use for staff-wielding spells like fireball."
    SafeAddComment ws.Cells(1, 47), "Seconds before attack hits (0 = use animation length). Overrides windup_duration."
    SafeAddComment ws.Cells(1, 48), "VFX effect ID per-skill (e.g., slash_arc, impact_spark). Empty = template default."
    SafeAddComment ws.Cells(1, 49), "Combo hit count (0 = template default, 1-10). Determines melee_single/combo_2/combo_3."
End Sub

'-------------------------------------------------------------------------------
' SetupSkillsSheet - Alias for SetupTalentsSheet (backward compatibility)
'-------------------------------------------------------------------------------
Public Sub SetupSkillsSheet()
    SetupTalentsSheet
End Sub
