Attribute VB_Name = "TriggerAreaDatabase"
'===============================================================================
' TriggerAreaDatabase Module
' Handles validation and export for Trigger Areas (event/cutscene triggers)
' Invisible areas that trigger events when player enters
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_TRIGGER_AREAS As String = "TriggerAreas"

' Column indices for TriggerAreas (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
' Trigger Settings
Private Const COL_TRIGGER_TYPE As Integer = 3
Private Const COL_TARGET_ID As Integer = 4
' Behavior
Private Const COL_ONE_SHOT As Integer = 5
Private Const COL_COOLDOWN As Integer = 6
' Quest Requirements
Private Const COL_REQUIRE_QUEST_ID As Integer = 7
Private Const COL_REQUIRE_QUEST_STATE As Integer = 8

' Valid dropdown values
Private validTriggerTypes() As String
Private validQuestStates() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validTriggerTypes = Split("cutscene,quest,spawn,dialogue", ",")
    validQuestStates = Split("not_started,active,completed", ",")
End Sub

'===============================================================================
' TRIGGER AREAS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateTriggerAreasData - Validates all rows in TriggerAreas sheet
'-------------------------------------------------------------------------------
Public Sub ValidateTriggerAreasData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TRIGGER_AREAS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TRIGGER_AREAS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextTrigger

        ' Validate ID format
        If Not ValidateId(id, "trigger_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: trigger_zone_name (e.g., trigger_forest_ambush)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate trigger_type
        Dim triggerType As String
        triggerType = LCase(Trim(ws.Cells(i, COL_TRIGGER_TYPE).Value))
        If Len(triggerType) = 0 Then
            LogValidationError errors, errorCount, i, "Trigger Type", "Trigger type is required"
        ElseIf Not ValidateDropdown(triggerType, validTriggerTypes) Then
            LogValidationError errors, errorCount, i, "Trigger Type", _
                "Invalid type. Valid: cutscene, quest, spawn, dialogue"
        End If

        ' Validate require_quest_state if specified
        Dim questState As String
        questState = LCase(Trim(ws.Cells(i, COL_REQUIRE_QUEST_STATE).Value))
        If Len(questState) > 0 And Not ValidateDropdown(questState, validQuestStates) Then
            LogValidationError errors, errorCount, i, "Require Quest State", _
                "Invalid state. Valid: not_started, active, completed"
        End If

        ' Validate cooldown non-negative
        Dim cooldown As Double
        cooldown = GetDefaultNumeric(ws.Cells(i, COL_COOLDOWN), 0)
        If cooldown < 0 Then
            LogValidationError errors, errorCount, i, "Cooldown", "Cannot be negative"
        End If

NextTrigger:
    Next i

    ShowValidationResults errors, errorCount, "TriggerAreas"
End Sub

'-------------------------------------------------------------------------------
' ExportTriggerAreasData - Exports TriggerAreas to JSON
'-------------------------------------------------------------------------------
Public Sub ExportTriggerAreasData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_TRIGGER_AREAS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_TRIGGER_AREAS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""trigger_areas"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportTrigger

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        ' Trigger Settings
        json = json & "      ""trigger_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TRIGGER_TYPE)))) & """," & vbCrLf
        json = json & "      ""target_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_TARGET_ID))) & """," & vbCrLf
        ' Behavior
        json = json & "      ""one_shot"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_ONE_SHOT), True)) & "," & vbCrLf
        json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_COOLDOWN), 0)) & "," & vbCrLf
        ' Quest Requirements
        json = json & "      ""require_quest_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_REQUIRE_QUEST_ID))) & """," & vbCrLf
        json = json & "      ""require_quest_state"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_REQUIRE_QUEST_STATE)))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportTrigger:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "trigger_areas.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " trigger areas to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupTriggerAreasSheet - Creates headers for TriggerAreas sheet
'-------------------------------------------------------------------------------
Public Sub SetupTriggerAreasSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_TRIGGER_AREAS)

    Dim headers As Variant
    headers = Array("id", "name", "trigger_type", "target_id", _
                    "one_shot", "cooldown", "require_quest_id", "require_quest_state")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_TRIGGER_TYPE), "cutscene, quest, spawn, or dialogue"
    SafeAddComment ws.Cells(1, COL_TARGET_ID), "Cutscene/Quest/SpawnGroup/Dialogue ID to trigger"
    SafeAddComment ws.Cells(1, COL_ONE_SHOT), "TRUE = only fires once (default)"
    SafeAddComment ws.Cells(1, COL_COOLDOWN), "Seconds before can trigger again (if not one-shot)"
    SafeAddComment ws.Cells(1, COL_REQUIRE_QUEST_ID), "Quest that must match state"
    SafeAddComment ws.Cells(1, COL_REQUIRE_QUEST_STATE), "not_started, active, or completed"

    ' Auto-fit columns
    ws.Columns("A:H").AutoFit

    MsgBox "TriggerAreas sheet headers set up successfully!", vbInformation
End Sub
