Attribute VB_Name = "QuestDatabase"
'===============================================================================
' QuestDatabase Module
' Handles validation and export for Quests with embedded objectives
' Updated for nested JSON structure with objectives inline
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_QUESTS As String = "Quests"
Private Const SHEET_OBJECTIVES As String = "QuestObjectives"

' Column indices for Quests (1-based) - UPDATED STRUCTURE
Private Const COL_QS_ID As Integer = 1
Private Const COL_QS_NAME As Integer = 2
Private Const COL_QS_DESCRIPTION As Integer = 3
Private Const COL_QS_TYPE As Integer = 4            ' story, side
Private Const COL_QS_MIN_LEVEL As Integer = 5
Private Const COL_QS_GIVER_NPC As Integer = 6
Private Const COL_QS_TURN_IN_NPC As Integer = 7
Private Const COL_QS_PREREQUISITE_QUESTS As Integer = 8
Private Const COL_QS_NEXT_QUEST As Integer = 9
Private Const COL_QS_CAN_ABANDON As Integer = 10
Private Const COL_QS_AUTO_COMPLETE As Integer = 11
Private Const COL_QS_XP_REWARD As Integer = 12
Private Const COL_QS_GOLD_REWARD As Integer = 13
Private Const COL_QS_ITEM_REWARDS As Integer = 14    ' comma-separated item IDs
Private Const COL_QS_START_DIALOGUE As Integer = 15
Private Const COL_QS_COMPLETE_DIALOGUE As Integer = 16

' Column indices for QuestObjectives (linked by quest_id)
Private Const COL_QO_QUEST_ID As Integer = 1         ' Links to quest
Private Const COL_QO_OBJ_ID As Integer = 2           ' Objective ID within quest
Private Const COL_QO_TYPE As Integer = 3             ' Objective type
Private Const COL_QO_TARGET As Integer = 4           ' Target ID (enemy_id, item_id, npc_id, zone_id)
Private Const COL_QO_COUNT As Integer = 5            ' Target count
Private Const COL_QO_DESCRIPTION As Integer = 6      ' Display text
Private Const COL_QO_OPTIONAL As Integer = 7         ' true/false

' Valid dropdown values
Private validQuestTypes() As String
Private validObjectiveTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    ' Only story and side quests (no repeatable/daily)
    validQuestTypes = Split("story,side", ",")

    ' All objective types from spec
    validObjectiveTypes = Split("kill_named,kill_count,gather,delivery,interact,talk,escort,defend,use_ability,defeat_no_kill,reach_location,race", ",")
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
    lastRow = ws.Cells(ws.Rows.Count, COL_QS_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_QS_ID).Value)

        If Len(id) = 0 Then GoTo NextQuest

        ' Validate ID format (story_XX_ or side_XX_)
        If Not (Left(id, 6) = "story_" Or Left(id, 5) = "side_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "ID should start with 'story_' or 'side_' (e.g., story_01_village_threat)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_QS_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate quest type
        Dim questType As String
        questType = LCase(Trim(ws.Cells(i, COL_QS_TYPE).Value))
        If Len(questType) > 0 And Not ValidateDropdown(questType, validQuestTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: story, side"
        End If

        ' Story quests cannot be abandoned
        If questType = "story" And GetDefaultBoolean(ws.Cells(i, COL_QS_CAN_ABANDON), False) Then
            LogValidationError errors, errorCount, i, "Can Abandon", _
                "Story quests cannot be abandoned (set to FALSE)"
        End If

        ' Validate rewards non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_QS_XP_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "XP Reward", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_QS_GOLD_REWARD)) < 0 Then
            LogValidationError errors, errorCount, i, "Gold Reward", "Cannot be negative"
        End If

NextQuest:
    Next i

    ' Validate objectives exist for each quest
    ValidateQuestObjectivesExist ws, errors, errorCount

    ShowValidationResults errors, errorCount, "Quests"
End Sub

'-------------------------------------------------------------------------------
' ValidateQuestObjectivesExist - Check that each quest has at least one objective
'-------------------------------------------------------------------------------
Private Sub ValidateQuestObjectivesExist(wsQuests As Worksheet, ByRef errors() As String, ByRef errorCount As Integer)
    Dim wsObj As Worksheet
    On Error Resume Next
    Set wsObj = ThisWorkbook.Sheets(SHEET_OBJECTIVES)
    On Error GoTo 0

    If wsObj Is Nothing Then
        LogValidationError errors, errorCount, 0, "Objectives", _
            "QuestObjectives sheet not found! Quests need objectives."
        Exit Sub
    End If

    Dim lastRowQuests As Long
    lastRowQuests = wsQuests.Cells(wsQuests.Rows.Count, COL_QS_ID).End(xlUp).Row

    Dim lastRowObj As Long
    lastRowObj = wsObj.Cells(wsObj.Rows.Count, COL_QO_QUEST_ID).End(xlUp).Row

    ' Build dictionary of quest IDs with objectives
    Dim questsWithObj As Object
    Set questsWithObj = CreateObject("Scripting.Dictionary")

    Dim j As Long
    For j = 2 To lastRowObj
        Dim qid As String
        qid = Trim(wsObj.Cells(j, COL_QO_QUEST_ID).Value)
        If Len(qid) > 0 Then
            questsWithObj(qid) = True
        End If
    Next j

    ' Check each quest has objectives
    Dim i As Long
    For i = 2 To lastRowQuests
        Dim id As String
        id = Trim(wsQuests.Cells(i, COL_QS_ID).Value)

        If Len(id) > 0 And Not questsWithObj.Exists(id) Then
            LogValidationError errors, errorCount, i, "Objectives", _
                "Quest '" & id & "' has no objectives in QuestObjectives sheet"
        End If
    Next i
End Sub

'-------------------------------------------------------------------------------
' ValidateQuestObjectives - Validates QuestObjectives sheet
'-------------------------------------------------------------------------------
Public Sub ValidateQuestObjectives()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_OBJECTIVES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_OBJECTIVES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_QO_QUEST_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim questId As String
        questId = Trim(ws.Cells(i, COL_QO_QUEST_ID).Value)

        If Len(questId) = 0 Then GoTo NextObjective

        ' Validate objective ID not empty
        If Len(Trim(ws.Cells(i, COL_QO_OBJ_ID).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Objective ID", "Objective ID is required"
        End If

        ' Validate objective type
        Dim objType As String
        objType = LCase(Trim(ws.Cells(i, COL_QO_TYPE).Value))
        If Len(objType) > 0 And Not ValidateDropdown(objType, validObjectiveTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid objective type. Valid: kill_named, kill_count, gather, delivery, interact, talk, escort, defend, use_ability, defeat_no_kill, reach_location, race"
        End If

        ' Validate target not empty for most types
        If Len(Trim(ws.Cells(i, COL_QO_TARGET).Value)) = 0 Then
            If objType <> "defend" Then ' defend might not need target
                LogValidationError errors, errorCount, i, "Target", "Target ID is required for " & objType & " objectives"
            End If
        End If

        ' Validate count is positive
        Dim cnt As Integer
        cnt = GetDefaultNumeric(ws.Cells(i, COL_QO_COUNT), 1)
        If cnt < 1 Then
            LogValidationError errors, errorCount, i, "Count", "Count must be at least 1"
        End If

NextObjective:
    Next i

    ShowValidationResults errors, errorCount, "Quest Objectives"
End Sub

'-------------------------------------------------------------------------------
' ExportQuests - Exports Quests to JSON with embedded objectives
'-------------------------------------------------------------------------------
Public Sub ExportQuests()
    InitValidLists

    Dim wsQuests As Worksheet
    Dim wsObj As Worksheet

    On Error Resume Next
    Set wsQuests = ThisWorkbook.Sheets(SHEET_QUESTS)
    Set wsObj = ThisWorkbook.Sheets(SHEET_OBJECTIVES)
    On Error GoTo 0

    If wsQuests Is Nothing Then
        MsgBox "Sheet '" & SHEET_QUESTS & "' not found!", vbExclamation
        Exit Sub
    End If

    If wsObj Is Nothing Then
        MsgBox "Sheet '" & SHEET_OBJECTIVES & "' not found!", vbExclamation
        Exit Sub
    End If

    ' Build objectives dictionary (quest_id -> array of objectives)
    Dim objDict As Object
    Set objDict = BuildObjectivesDictionary(wsObj)

    Dim json As String
    json = "{" & vbCrLf & "  ""quests"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = wsQuests.Cells(wsQuests.Rows.Count, COL_QS_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(wsQuests.Cells(i, COL_QS_ID).Value)

        If Len(id) = 0 Then GoTo NextExportQuest

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(wsQuests.Cells(i, COL_QS_TYPE), "side"))) & """," & vbCrLf
        json = json & "      ""min_level"": " & FormatJsonNumber(GetDefaultNumeric(wsQuests.Cells(i, COL_QS_MIN_LEVEL), 1)) & "," & vbCrLf
        json = json & "      ""giver_npc"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_GIVER_NPC))) & """," & vbCrLf
        json = json & "      ""turn_in_npc"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_TURN_IN_NPC))) & """," & vbCrLf
        json = json & "      ""prerequisite_quests"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_PREREQUISITE_QUESTS))) & """," & vbCrLf
        json = json & "      ""next_quest"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_NEXT_QUEST))) & """," & vbCrLf
        json = json & "      ""can_abandon"": " & LCase(CStr(GetDefaultBoolean(wsQuests.Cells(i, COL_QS_CAN_ABANDON), True))) & "," & vbCrLf
        json = json & "      ""auto_complete"": " & LCase(CStr(GetDefaultBoolean(wsQuests.Cells(i, COL_QS_AUTO_COMPLETE), False))) & "," & vbCrLf

        ' Embed objectives array
        json = json & "      ""objectives"": " & GetObjectivesJson(objDict, id) & "," & vbCrLf

        ' Rewards object
        json = json & "      ""rewards"": {" & vbCrLf
        json = json & "        ""experience"": " & FormatJsonNumber(GetDefaultNumeric(wsQuests.Cells(i, COL_QS_XP_REWARD), 0)) & "," & vbCrLf
        json = json & "        ""gold"": " & FormatJsonNumber(GetDefaultNumeric(wsQuests.Cells(i, COL_QS_GOLD_REWARD), 0)) & "," & vbCrLf
        json = json & "        ""items"": " & GetItemRewardsJson(GetDefaultString(wsQuests.Cells(i, COL_QS_ITEM_REWARDS))) & vbCrLf
        json = json & "      }," & vbCrLf

        json = json & "      ""start_dialogue"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_START_DIALOGUE))) & """," & vbCrLf
        json = json & "      ""complete_dialogue"": """ & EscapeJsonString(GetDefaultString(wsQuests.Cells(i, COL_QS_COMPLETE_DIALOGUE))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportQuest:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "quests.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " quests to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' BuildObjectivesDictionary - Creates dictionary mapping quest_id to objectives
'-------------------------------------------------------------------------------
Private Function BuildObjectivesDictionary(wsObj As Worksheet) As Object
    Dim dict As Object
    Set dict = CreateObject("Scripting.Dictionary")

    Dim lastRow As Long
    lastRow = wsObj.Cells(wsObj.Rows.Count, COL_QO_QUEST_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim questId As String
        questId = Trim(wsObj.Cells(i, COL_QO_QUEST_ID).Value)

        If Len(questId) > 0 Then
            Dim objData As String
            objData = ""
            objData = objData & Trim(wsObj.Cells(i, COL_QO_OBJ_ID).Value) & "|"
            objData = objData & LCase(Trim(wsObj.Cells(i, COL_QO_TYPE).Value)) & "|"
            objData = objData & Trim(wsObj.Cells(i, COL_QO_TARGET).Value) & "|"
            objData = objData & FormatJsonNumber(GetDefaultNumeric(wsObj.Cells(i, COL_QO_COUNT), 1)) & "|"
            objData = objData & Trim(wsObj.Cells(i, COL_QO_DESCRIPTION).Value) & "|"
            objData = objData & LCase(GetDefaultString(wsObj.Cells(i, COL_QO_OPTIONAL), "false"))

            If dict.Exists(questId) Then
                dict(questId) = dict(questId) & "~" & objData
            Else
                dict(questId) = objData
            End If
        End If
    Next i

    Set BuildObjectivesDictionary = dict
End Function

'-------------------------------------------------------------------------------
' GetObjectivesJson - Returns JSON array of objectives for a quest
'-------------------------------------------------------------------------------
Private Function GetObjectivesJson(objDict As Object, questId As String) As String
    If Not objDict.Exists(questId) Then
        GetObjectivesJson = "[]"
        Exit Function
    End If

    Dim objectives() As String
    objectives = Split(objDict(questId), "~")

    Dim json As String
    json = "[" & vbCrLf

    Dim i As Integer
    For i = LBound(objectives) To UBound(objectives)
        Dim parts() As String
        parts = Split(objectives(i), "|")

        If UBound(parts) >= 5 Then
            If i > LBound(objectives) Then json = json & "," & vbCrLf

            json = json & "        {" & vbCrLf
            json = json & "          ""id"": """ & EscapeJsonString(parts(0)) & """," & vbCrLf
            json = json & "          ""type"": """ & EscapeJsonString(parts(1)) & """," & vbCrLf
            json = json & "          ""target"": """ & EscapeJsonString(parts(2)) & """," & vbCrLf
            json = json & "          ""count"": " & parts(3) & "," & vbCrLf
            json = json & "          ""description"": """ & EscapeJsonString(parts(4)) & """," & vbCrLf
            json = json & "          ""optional"": " & IIf(parts(5) = "true", "true", "false") & vbCrLf
            json = json & "        }"
        End If
    Next i

    json = json & vbCrLf & "      ]"
    GetObjectivesJson = json
End Function

'-------------------------------------------------------------------------------
' GetItemRewardsJson - Converts comma-separated item IDs to JSON array
'-------------------------------------------------------------------------------
Private Function GetItemRewardsJson(itemsStr As String) As String
    If Len(Trim(itemsStr)) = 0 Then
        GetItemRewardsJson = "[]"
        Exit Function
    End If

    Dim items() As String
    items = Split(itemsStr, ",")

    Dim json As String
    json = "["

    Dim i As Integer
    For i = LBound(items) To UBound(items)
        If i > LBound(items) Then json = json & ", "
        json = json & """" & EscapeJsonString(Trim(items(i))) & """"
    Next i

    json = json & "]"
    GetItemRewardsJson = json
End Function

'===============================================================================
' QUEST OBJECTIVES (Separate export for reference)
'===============================================================================

'-------------------------------------------------------------------------------
' ExportQuestObjectives - Exports objective type reference to JSON
'-------------------------------------------------------------------------------
Public Sub ExportQuestObjectives()
    InitValidLists

    ' Export just the reference documentation
    Dim json As String
    json = "{" & vbCrLf
    json = json & "  ""quest_objectives"": [" & vbCrLf
    json = json & "    {" & vbCrLf
    json = json & "      ""id"": ""objective_type_reference""," & vbCrLf
    json = json & "      ""description"": ""This file documents the available objective types. Objectives are typically defined inline within quests.json, but this file can be used for shared/reusable objective templates.""," & vbCrLf
    json = json & "      ""types"": {" & vbCrLf
    json = json & "        ""kill_named"": ""Kill a specific named enemy (target = enemy_id)""," & vbCrLf
    json = json & "        ""kill_count"": ""Kill X enemies of a type (target = enemy_id or type, count = number)""," & vbCrLf
    json = json & "        ""gather"": ""Collect X items (target = item_id, count = number)""," & vbCrLf
    json = json & "        ""delivery"": ""Bring an item to an NPC (target = npc_id)""," & vbCrLf
    json = json & "        ""interact"": ""Interact with object(s) (target = object_id, count = number)""," & vbCrLf
    json = json & "        ""talk"": ""Talk to an NPC (target = npc_id)""," & vbCrLf
    json = json & "        ""escort"": ""Escort NPC to location (target = npc_id)""," & vbCrLf
    json = json & "        ""defend"": ""Survive waves/time (target = zone_id, count = waves or seconds)""," & vbCrLf
    json = json & "        ""use_ability"": ""Use specific ability X times (target = ability_id, count = number)""," & vbCrLf
    json = json & "        ""defeat_no_kill"": ""Reduce enemy HP without killing (target = enemy_id)""," & vbCrLf
    json = json & "        ""reach_location"": ""Arrive at zone/location (target = zone_id)""," & vbCrLf
    json = json & "        ""race"": ""Reach location within time limit (target = zone_id, count = seconds)""" & vbCrLf
    json = json & "      }" & vbCrLf
    json = json & "    }" & vbCrLf
    json = json & "  ]" & vbCrLf
    json = json & "}" & vbCrLf

    Dim filePath As String
    filePath = GetExportPath() & "quest_objectives.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported quest objective types reference to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
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
    If Not g_SilentMode Then
        MsgBox "All quest databases exported!", vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' ValidateAllQuests - Validates all quest-related sheets
'-------------------------------------------------------------------------------
Public Sub ValidateAllQuests()
    ValidateQuests
    ValidateQuestObjectives
    If Not g_SilentMode Then
        MsgBox "All quest validations complete!", vbInformation, "Validation Complete"
    End If
End Sub
