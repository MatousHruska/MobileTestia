Attribute VB_Name = "AchievementDatabase"
'===============================================================================
' AchievementDatabase Module
' Handles validation and export for Achievements (persistent player accomplishments)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_ACHIEVEMENTS As String = "Achievements"

' Column indices for Achievements (1-based)
Private Const COL_ACH_ID As Integer = 1
Private Const COL_ACH_NAME As Integer = 2
Private Const COL_ACH_DESCRIPTION As Integer = 3
Private Const COL_ACH_CATEGORY As Integer = 4
Private Const COL_ACH_STAT As Integer = 5
Private Const COL_ACH_TARGET As Integer = 6
Private Const COL_ACH_HIDDEN As Integer = 7
Private Const COL_ACH_ICON As Integer = 8
Private Const COL_ACH_REWARD_TYPE As Integer = 9
Private Const COL_ACH_REWARD_VALUE As Integer = 10
Private Const COL_ACH_SORT_ORDER As Integer = 11

' Valid categories
Private Function GetValidCategories() As Variant
    GetValidCategories = Array("combat", "progression", "quests", "economy", "exploration", "story", "misc")
End Function

' Valid tracking statistics
Private Function GetValidStats() As Variant
    GetValidStats = Array("enemies_killed", "bosses_killed", "deaths", "damage_dealt", "damage_taken", _
                          "critical_hits", "abilities_used", "gold_earned", "gold_spent", "items_looted", _
                          "items_sold", "items_bought", "quests_completed", "levels_gained", _
                          "skill_points_spent", "attribute_points_spent", "zones_discovered", _
                          "chests_opened", "secrets_found", "games_started", "games_completed", _
                          "ng_plus_runs", "saves_created", "highest_level_reached", "fastest_completion", _
                          "total_playtime", "manual")
End Function

' Valid reward types
Private Function GetValidRewardTypes() As Variant
    GetValidRewardTypes = Array("none", "title", "cosmetic", "unlock", "gold", "item")
End Function

'-------------------------------------------------------------------------------
' ValidateAchievements - Validates all rows in Achievements sheet
'-------------------------------------------------------------------------------
Public Sub ValidateAchievements()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ACHIEVEMENTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ACHIEVEMENTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ACH_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ACH_ID).Value)

        If Len(id) = 0 Then GoTo NextAchievement

        ' Validate ID format
        If Not ValidateId(id, "ach_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: ach_category_name (e.g., ach_combat_first_blood)"
        End If

        ' Validate name required
        Dim achName As String
        achName = Trim(ws.Cells(i, COL_ACH_NAME).Value)
        If Len(achName) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Achievement name is required"
        End If

        ' Validate description required
        Dim achDesc As String
        achDesc = Trim(ws.Cells(i, COL_ACH_DESCRIPTION).Value)
        If Len(achDesc) = 0 Then
            LogValidationError errors, errorCount, i, "Description", "Achievement description is required"
        End If

        ' Validate category
        Dim category As String
        category = Trim(ws.Cells(i, COL_ACH_CATEGORY).Value)
        If Len(category) > 0 Then
            Dim validCategories As Variant
            validCategories = GetValidCategories()
            Dim isValidCategory As Boolean
            isValidCategory = False
            Dim j As Integer
            For j = LBound(validCategories) To UBound(validCategories)
                If LCase(category) = LCase(validCategories(j)) Then
                    isValidCategory = True
                    Exit For
                End If
            Next j
            If Not isValidCategory Then
                LogValidationError errors, errorCount, i, "Category", _
                    "Invalid category. Valid: combat, progression, quests, economy, exploration, story, misc"
            End If
        Else
            LogValidationError errors, errorCount, i, "Category", "Category is required"
        End If

        ' Validate stat tracking
        Dim stat As String
        stat = Trim(ws.Cells(i, COL_ACH_STAT).Value)
        If Len(stat) > 0 Then
            Dim validStats As Variant
            validStats = GetValidStats()
            Dim isValidStat As Boolean
            isValidStat = False
            Dim k As Integer
            For k = LBound(validStats) To UBound(validStats)
                If LCase(stat) = LCase(validStats(k)) Then
                    isValidStat = True
                    Exit For
                End If
            Next k
            If Not isValidStat Then
                LogValidationError errors, errorCount, i, "Stat", _
                    "Invalid stat. Common: enemies_killed, quests_completed, highest_level_reached, gold_earned, manual"
            End If
        Else
            LogValidationError errors, errorCount, i, "Stat", "Tracking stat is required (use 'manual' for script-controlled)"
        End If

        ' Validate target positive
        Dim target As Integer
        target = GetDefaultNumeric(ws.Cells(i, COL_ACH_TARGET), 1)
        If target < 1 Then
            LogValidationError errors, errorCount, i, "Target", "Target must be at least 1"
        End If

        ' Validate reward type if specified
        Dim rewardType As String
        rewardType = Trim(ws.Cells(i, COL_ACH_REWARD_TYPE).Value)
        If Len(rewardType) > 0 Then
            Dim validRewards As Variant
            validRewards = GetValidRewardTypes()
            Dim isValidReward As Boolean
            isValidReward = False
            Dim m As Integer
            For m = LBound(validRewards) To UBound(validRewards)
                If LCase(rewardType) = LCase(validRewards(m)) Then
                    isValidReward = True
                    Exit For
                End If
            Next m
            If Not isValidReward Then
                LogValidationError errors, errorCount, i, "Reward Type", _
                    "Invalid reward type. Valid: none, title, cosmetic, unlock, gold, item"
            End If
        End If

NextAchievement:
    Next i

    ShowValidationResults errors, errorCount, "Achievements"
End Sub

'-------------------------------------------------------------------------------
' ExportAchievements - Exports Achievements to JSON
'-------------------------------------------------------------------------------
Public Sub ExportAchievements()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ACHIEVEMENTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ACHIEVEMENTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""achievements"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ACH_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ACH_ID).Value)

        If Len(id) = 0 Then GoTo NextExportAchievement

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ACH_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ACH_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""category"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_ACH_CATEGORY)))) & """," & vbCrLf
        json = json & "      ""stat"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_ACH_STAT)))) & """," & vbCrLf
        json = json & "      ""target"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ACH_TARGET), 1)) & "," & vbCrLf
        json = json & "      ""hidden"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_ACH_HIDDEN), False)) & "," & vbCrLf
        json = json & "      ""icon"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ACH_ICON))) & """," & vbCrLf
        json = json & "      ""reward_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_ACH_REWARD_TYPE), "none"))) & """," & vbCrLf
        json = json & "      ""reward_value"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_ACH_REWARD_VALUE))) & """," & vbCrLf
        json = json & "      ""sort_order"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_ACH_SORT_ORDER), itemCount)) & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportAchievement:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "achievements.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " achievements to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupAchievementsSheet - Creates Achievements sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupAchievementsSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ACHIEVEMENTS)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_ACHIEVEMENTS
    End If

    Dim headers As Variant
    headers = Array("id", "name", "description", "category", "stat", "target", _
                    "hidden", "icon", "reward_type", "reward_value", "sort_order")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: ach_category_name (e.g., ach_combat_first_blood, ach_prog_level10)"
    SafeAddComment ws.Cells(1, 2), "Display name shown to player"
    SafeAddComment ws.Cells(1, 3), "Achievement description"
    SafeAddComment ws.Cells(1, 4), "Category: combat, progression, quests, economy, exploration, story, misc"
    SafeAddComment ws.Cells(1, 5), "Statistic to track: enemies_killed, quests_completed, highest_level_reached, gold_earned, deaths, bosses_killed, manual (for script-controlled)"
    SafeAddComment ws.Cells(1, 6), "Target value to unlock (e.g., 100 for 'kill 100 enemies')"
    SafeAddComment ws.Cells(1, 7), "TRUE/FALSE - Hidden achievements don't show until unlocked"
    SafeAddComment ws.Cells(1, 8), "Icon sprite name (optional)"
    SafeAddComment ws.Cells(1, 9), "Reward type: none, title, cosmetic, unlock, gold, item"
    SafeAddComment ws.Cells(1, 10), "Reward value (item_id, gold amount, unlock_id, etc.)"
    SafeAddComment ws.Cells(1, 11), "Sort order in achievement list (lower = first)"

    If Not g_SilentMode Then
        MsgBox "Achievements sheet created with headers!", vbInformation
    End If
End Sub
