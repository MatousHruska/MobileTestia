Attribute VB_Name = "QuestDatabase"
'===============================================================================
' QuestDatabase Module
' Handles validation and export for Quests
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_QUESTS As String = "Quests"
Private Const SHEET_OBJECTIVES As String = "QuestObjectives"

' Column indices for Quests (1-based)
Private Const COL_QS_ID As Integer = 1
Private Const COL_QS_NAME As Integer = 2
Private Const COL_QS_TYPE As Integer = 3           ' main, side, daily, event
Private Const COL_QS_GIVER_NPC As Integer = 4
Private Const COL_QS_MIN_LEVEL As Integer = 5
Private Const COL_QS_PREREQUISITE_QUESTS As Integer = 6
Private Const COL_QS_OBJECTIVE_IDS As Integer = 7
Private Const COL_QS_XP_REWARD As Integer = 8
Private Const COL_QS_GOLD_REWARD As Integer = 9
Private Const COL_QS_ITEM_REWARDS As Integer = 10
Private Const COL_QS_LOOT_TABLE_REWARD As Integer = 11
Private Const COL_QS_DESCRIPTION As Integer = 12
Private Const COL_QS_COMPLETION_TEXT As Integer = 13

' Column indices for QuestObjectives
Private Const COL_QO_ID As Integer = 1
Private Const COL_QO_TYPE As Integer = 2           ' kill, collect, talk, explore, escort
Private Const COL_QO_TARGET_ID As Integer = 3      ' enemy_id, item_id, npc_id, location_id
Private Const COL_QO_COUNT As Integer = 4
Private Const COL_QO_DESCRIPTION As Integer = 5
Private Const COL_QO_OPTIONAL As Integer = 6

' Valid dropdown values
Private validQuestTypes() As String
Private validObjectiveTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validQuestTypes = Split("main,side,daily,event,tutorial", ",")
    validObjectiveTypes = Split("kill,collect,talk,explore,escort,defend,craft,use", ",")
End Sub

'===============================================================================
' QUESTS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateQuests - Validates all rows in Quests sheet
'-------------------------------------------------------------------------------
Public Sub ValidateQuests()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_QUESTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_QUESTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_QS_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_QS_ID).value)

        If Len(id) = 0 Then GoTo NextQuest

        ' Validate ID format
        If Not ValidateId(id, "qst_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: qst_type_name (e.g., qst_main_firstbattle)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_QS_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate quest type
        Dim questType As String
        questType = LCase(Trim(ws.Cells(i, COL_QS_TYPE).value))
        If Len(questType) > 0 And Not ValidateDropdown(questType, validQuestTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: main, side, daily, event, tutorial"
        End If

        ' Validate rewards non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_QS_XP_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "XP Reward", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_QS_GOLD_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "Gold Reward", "Cannot be negative"
        End If

        ' Validate objective_ids not empty (quest must have at least one objective)
        If Len(Trim(ws.Cells(i, COL_QS_OBJECTIVE_IDS).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Objective IDs", _
                "Quest must have at least one objective"
        End If

NextQuest:
    Next i

    ShowValidationResults errors, errorCount, "Quests"
End Sub

'-------------------------------------------------------------------------------
' ExportQuests - Exports Quests to JSON
'-------------------------------------------------------------------------------
Public Sub ExportQuests()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_QUESTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_QUESTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""quests"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_QS_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_QS_ID).value)

        If Len(id) = 0 Then GoTo NextExportQuest

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_QS_TYPE), "side"))) & """," & vbCrLf
        json = json & "      ""giver_npc"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_GIVER_NPC))) & """," & vbCrLf
        json = json & "      ""min_level"": " & GetDefaultNumeric(ws.Cells(i, COL_QS_MIN_LEVEL), 1) & "," & vbCrLf
        json = json & "      ""prerequisite_quests"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_PREREQUISITE_QUESTS))) & """," & vbCrLf
        json = json & "      ""objective_ids"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_OBJECTIVE_IDS))) & """," & vbCrLf
        json = json & "      ""xp_reward"": " & GetDefaultNumeric(ws.Cells(i, COL_QS_XP_REWARD), 100) & "," & vbCrLf
        json = json & "      ""gold_reward"": " & GetDefaultNumeric(ws.Cells(i, COL_QS_GOLD_REWARD), 50) & "," & vbCrLf
        json = json & "      ""item_rewards"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_ITEM_REWARDS))) & """," & vbCrLf
        json = json & "      ""loot_table_reward"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_LOOT_TABLE_REWARD))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""completion_text"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QS_COMPLETION_TEXT))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportQuest:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "quests.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " quests to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' QUEST OBJECTIVES
'===============================================================================

'-------------------------------------------------------------------------------
' ExportQuestObjectives - Exports QuestObjectives to JSON
'-------------------------------------------------------------------------------
Public Sub ExportQuestObjectives()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_OBJECTIVES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_OBJECTIVES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""quest_objectives"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_QO_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_QO_ID).value)

        If Len(id) = 0 Then GoTo NextExportObjective

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_QO_TYPE), "kill"))) & """," & vbCrLf
        json = json & "      ""target_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QO_TARGET_ID))) & """," & vbCrLf
        json = json & "      ""count"": " & GetDefaultNumeric(ws.Cells(i, COL_QO_COUNT), 1) & "," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QO_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""optional"": " & IIf(LCase(GetDefaultString(ws.Cells(i, COL_QO_OPTIONAL))) = "true", "true", "false") & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportObjective:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "quest_objectives.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " quest objectives to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' MASTER EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportAllQuests - Exports all quest-related sheets
'-------------------------------------------------------------------------------
Public Sub ExportAllQuests()
    ExportQuests
    ExportQuestObjectives
    MsgBox "All quest databases exported!", vbInformation, "Export Complete"
End Sub
