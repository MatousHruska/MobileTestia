Attribute VB_Name = "SkillDatabase"
'===============================================================================
' SkillDatabase Module
' Handles validation and export for Player Skills
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_SKILLS As String = "Skills"
Private Const SHEET_SKILL_TREES As String = "SkillTrees"

' Column indices for Skills (1-based)
Private Const COL_SK_ID As Integer = 1
Private Const COL_SK_NAME As Integer = 2
Private Const COL_SK_TYPE As Integer = 3           ' active, passive, buff
Private Const COL_SK_TREE As Integer = 4           ' combat, magic, utility
Private Const COL_SK_TIER As Integer = 5           ' 1-5 (skill tree tier)
Private Const COL_SK_MAX_LEVEL As Integer = 6
Private Const COL_SK_MANA_COST As Integer = 7
Private Const COL_SK_STAMINA_COST As Integer = 8
Private Const COL_SK_COOLDOWN As Integer = 9
Private Const COL_SK_BASE_DAMAGE As Integer = 10
Private Const COL_SK_DAMAGE_PER_LEVEL As Integer = 11
Private Const COL_SK_EFFECT_TYPE As Integer = 12   ' damage, heal, buff, debuff
Private Const COL_SK_EFFECT_VALUE As Integer = 13
Private Const COL_SK_EFFECT_PER_LEVEL As Integer = 14
Private Const COL_SK_DURATION As Integer = 15
Private Const COL_SK_PREREQUISITE_IDS As Integer = 16
Private Const COL_SK_DESCRIPTION As Integer = 17
Private Const COL_SK_ICON_NAME As Integer = 18

' Valid dropdown values
Private validSkillTypes() As String
Private validSkillTrees() As String
Private validEffectTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validSkillTypes = Split("active,passive,buff,toggle", ",")
    validSkillTrees = Split("combat,magic,utility,class", ",")
    validEffectTypes = Split("damage,heal,buff,debuff,summon,teleport,projectile", ",")
End Sub

'===============================================================================
' SKILLS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateSkills - Validates all rows in Skills sheet
'-------------------------------------------------------------------------------
Public Sub ValidateSkills()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SKILLS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SKILLS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SK_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SK_ID).value)

        If Len(id) = 0 Then GoTo NextSkill

        ' Validate ID format
        If Not ValidateId(id, "skl_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: skl_tree_name (e.g., skl_combat_powerattack)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_SK_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate skill type
        Dim skillType As String
        skillType = LCase(Trim(ws.Cells(i, COL_SK_TYPE).value))
        If Len(skillType) > 0 And Not ValidateDropdown(skillType, validSkillTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: active, passive, buff, toggle"
        End If

        ' Validate skill tree
        Dim skillTree As String
        skillTree = LCase(Trim(ws.Cells(i, COL_SK_TREE).value))
        If Len(skillTree) > 0 And Not ValidateDropdown(skillTree, validSkillTrees) Then
            LogValidationError errors, errorCount, i, "Tree", _
                "Invalid tree. Valid: combat, magic, utility, class"
        End If

        ' Validate tier 1-5
        Dim tier As Double
        tier = GetDefaultNumeric(ws.Cells(i, COL_SK_TIER), 1)
        If tier < 1 Or tier > 5 Then
            LogValidationError errors, errorCount, i, "Tier", "Tier must be between 1 and 5"
        End If

        ' Validate max level > 0
        Dim maxLevel As Double
        maxLevel = GetDefaultNumeric(ws.Cells(i, COL_SK_MAX_LEVEL), 1)
        If maxLevel < 1 Then
            LogValidationError errors, errorCount, i, "Max Level", "Max level must be at least 1"
        End If

        ' Validate costs non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_SK_MANA_COST)) < 0 Then
            LogValidationError errors, errorCount, i, "Mana Cost", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_SK_STAMINA_COST)) < 0 Then
            LogValidationError errors, errorCount, i, "Stamina Cost", "Cannot be negative"
        End If

NextSkill:
    Next i

    ShowValidationResults errors, errorCount, "Skills"
End Sub

'-------------------------------------------------------------------------------
' ExportSkills - Exports Skills to JSON
'-------------------------------------------------------------------------------
Public Sub ExportSkills()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SKILLS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SKILLS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""skills"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SK_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SK_ID).value)

        If Len(id) = 0 Then GoTo NextExportSkill

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SK_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SK_TYPE), "active"))) & """," & vbCrLf
        json = json & "      ""tree"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SK_TREE), "combat"))) & """," & vbCrLf
        json = json & "      ""tier"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_TIER), 1) & "," & vbCrLf
        json = json & "      ""max_level"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_MAX_LEVEL), 5) & "," & vbCrLf
        json = json & "      ""mana_cost"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_MANA_COST)) & "," & vbCrLf
        json = json & "      ""stamina_cost"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_STAMINA_COST)) & "," & vbCrLf
        json = json & "      ""cooldown"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_COOLDOWN)) & "," & vbCrLf
        json = json & "      ""base_damage"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_BASE_DAMAGE)) & "," & vbCrLf
        json = json & "      ""damage_per_level"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_DAMAGE_PER_LEVEL)) & "," & vbCrLf
        json = json & "      ""effect_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SK_EFFECT_TYPE)))) & """," & vbCrLf
        json = json & "      ""effect_value"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_EFFECT_VALUE)) & "," & vbCrLf
        json = json & "      ""effect_per_level"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_EFFECT_PER_LEVEL)) & "," & vbCrLf
        json = json & "      ""duration"": " & GetDefaultNumeric(ws.Cells(i, COL_SK_DURATION)) & "," & vbCrLf
        json = json & "      ""prerequisite_ids"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SK_PREREQUISITE_IDS))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SK_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""icon_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SK_ICON_NAME), id)) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportSkill:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "skills.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " skills to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub
