Attribute VB_Name = "CutsceneDatabase"
'===============================================================================
' CutsceneDatabase Module
' Handles validation and export for Cutscenes
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_CUTSCENES As String = "Cutscenes"

' Column indices for Cutscenes (1-based)
Private Const COL_CUT_ID As Integer = 1
Private Const COL_CUT_NAME As Integer = 2
Private Const COL_CUT_TRIGGER As Integer = 3
Private Const COL_CUT_TRIGGER_TARGET As Integer = 4
Private Const COL_CUT_ONCE_ONLY As Integer = 5
Private Const COL_CUT_ACTIONS As Integer = 6

'-------------------------------------------------------------------------------
' ValidateCutscenes - Validates all rows in Cutscenes sheet
'-------------------------------------------------------------------------------
Public Sub ValidateCutscenes()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CUTSCENES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CUTSCENES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CUT_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CUT_ID).Value)

        If Len(id) = 0 Then GoTo NextCutscene

        ' Validate ID format
        If Not ValidateId(id, "cut_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: cut_name (e.g., cut_intro_village)"
        End If

        ' Validate trigger not empty
        If Len(Trim(ws.Cells(i, COL_CUT_TRIGGER).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Trigger", _
                "Cutscene must have a trigger type"
        End If

        ' Validate actions not empty
        If Len(Trim(ws.Cells(i, COL_CUT_ACTIONS).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Actions", _
                "Cutscene must have at least one action"
        End If

NextCutscene:
    Next i

    ShowValidationResults errors, errorCount, "Cutscenes"
End Sub

'-------------------------------------------------------------------------------
' ExportCutscenes - Exports Cutscenes to JSON
'-------------------------------------------------------------------------------
Public Sub ExportCutscenes()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CUTSCENES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CUTSCENES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""cutscenes"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CUT_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CUT_ID).Value)

        If Len(id) = 0 Then GoTo NextExportCutscene

        If itemCount > 0 Then json = json & "," & vbCrLf

        Dim cutName As String
        Dim trigger As String
        Dim triggerTarget As String
        Dim onceOnly As String
        Dim actionsRaw As String

        cutName = Trim(ws.Cells(i, COL_CUT_NAME).Value)
        trigger = Trim(ws.Cells(i, COL_CUT_TRIGGER).Value)
        triggerTarget = Trim(ws.Cells(i, COL_CUT_TRIGGER_TARGET).Value)
        onceOnly = LCase(Trim(ws.Cells(i, COL_CUT_ONCE_ONLY).Value))
        actionsRaw = Trim(ws.Cells(i, COL_CUT_ACTIONS).Value)

        ' Convert actions string to JSON array
        Dim actionsJson As String
        actionsJson = ConvertActionsToJson(actionsRaw)

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(cutName) & """," & vbCrLf
        json = json & "      ""trigger"": """ & EscapeJsonString(trigger) & """," & vbCrLf

        If Len(triggerTarget) > 0 Then
            json = json & "      ""trigger_target"": """ & EscapeJsonString(triggerTarget) & """," & vbCrLf
        End If

        json = json & "      ""once_only"": " & IIf(onceOnly = "true" Or onceOnly = "yes", "true", "false") & "," & vbCrLf
        json = json & "      ""actions"": " & actionsJson & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportCutscene:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "cutscenes.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " cutscenes to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ConvertActionsToJson - Converts delimited action string to JSON array
' Format: type:param1:param2:param3###type:param1:param2###...
'
' Action formats (: separates params, ### separates actions):
'   dialogue:speaker:text:portrait
'   wait:duration
'   fade_in:duration
'   fade_out:duration
'   move:target:x:y:speed
'   camera_pan:x:y:duration
'   camera_shake:intensity:duration
'   camera_reset:duration
'   set_facing:target:direction
'-------------------------------------------------------------------------------
Private Function ConvertActionsToJson(actionsData As String) As String
    If Len(actionsData) = 0 Then
        ConvertActionsToJson = "[]"
        Exit Function
    End If

    Dim json As String
    json = "[" & vbCrLf

    ' Split by ### to get individual actions
    Dim actions() As String
    actions = Split(actionsData, "###")

    Dim actionCount As Integer
    actionCount = 0

    Dim actionIdx As Integer
    For actionIdx = LBound(actions) To UBound(actions)
        Dim actionData As String
        actionData = Trim(actions(actionIdx))

        If Len(actionData) = 0 Then GoTo NextAction

        ' Split by : to get action type and params
        Dim parts() As String
        parts = Split(actionData, ":")

        If UBound(parts) < 0 Then GoTo NextAction

        Dim actionType As String
        actionType = LCase(Trim(parts(0)))

        If actionCount > 0 Then json = json & "," & vbCrLf

        json = json & "      " & BuildActionJson(actionType, parts)

        actionCount = actionCount + 1

NextAction:
    Next actionIdx

    json = json & vbCrLf & "    ]"

    ConvertActionsToJson = json
End Function

'-------------------------------------------------------------------------------
' BuildActionJson - Builds JSON object for a single action
'-------------------------------------------------------------------------------
Private Function BuildActionJson(actionType As String, parts() As String) As String
    Dim json As String

    Select Case actionType
        Case "dialogue"
            ' dialogue:speaker:text:portrait
            Dim speaker As String: speaker = SafeGetPart(parts, 1)
            Dim dialogueText As String: dialogueText = SafeGetPart(parts, 2)
            Dim portrait As String: portrait = SafeGetPart(parts, 3)

            json = "{""type"": ""dialogue"", ""speaker"": """ & EscapeJsonString(speaker) & """, "
            json = json & """text"": """ & EscapeJsonString(dialogueText) & """"
            If Len(portrait) > 0 Then
                json = json & ", ""portrait"": """ & EscapeJsonString(portrait) & """"
            End If
            json = json & "}"

        Case "wait"
            ' wait:duration
            json = "{""type"": ""wait"", ""duration"": " & SafeGetNumPart(parts, 1, 1) & "}"

        Case "fade_in"
            ' fade_in:duration
            json = "{""type"": ""fade_in"", ""duration"": " & SafeGetNumPart(parts, 1, 0.5) & "}"

        Case "fade_out"
            ' fade_out:duration
            json = "{""type"": ""fade_out"", ""duration"": " & SafeGetNumPart(parts, 1, 0.5) & "}"

        Case "move"
            ' move:target:x:y:speed
            json = "{""type"": ""move"", ""target"": """ & SafeGetPart(parts, 1) & """, "
            json = json & """position"": [" & SafeGetNumPart(parts, 2, 0) & ", " & SafeGetNumPart(parts, 3, 0) & "], "
            json = json & """speed"": " & SafeGetNumPart(parts, 4, 100) & "}"

        Case "camera_pan"
            ' camera_pan:x:y:duration
            json = "{""type"": ""camera_pan"", ""position"": [" & SafeGetNumPart(parts, 1, 0) & ", "
            json = json & SafeGetNumPart(parts, 2, 0) & "], ""duration"": " & SafeGetNumPart(parts, 3, 1) & "}"

        Case "camera_shake"
            ' camera_shake:intensity:duration
            json = "{""type"": ""camera_shake"", ""intensity"": " & SafeGetNumPart(parts, 1, 0.5)
            json = json & ", ""duration"": " & SafeGetNumPart(parts, 2, 0.3) & "}"

        Case "camera_reset"
            ' camera_reset:duration
            json = "{""type"": ""camera_reset"", ""duration"": " & SafeGetNumPart(parts, 1, 0.5) & "}"

        Case "set_facing"
            ' set_facing:target:direction
            json = "{""type"": ""set_facing"", ""target"": """ & SafeGetPart(parts, 1) & """, "
            json = json & """direction"": """ & SafeGetPart(parts, 2) & """}"

        Case "spawn"
            ' spawn:npc_id:x:y
            json = "{""type"": ""spawn"", ""npc_id"": """ & SafeGetPart(parts, 1) & """, "
            json = json & """position"": [" & SafeGetNumPart(parts, 2, 0) & ", " & SafeGetNumPart(parts, 3, 0) & "]}"

        Case "despawn"
            ' despawn:target
            json = "{""type"": ""despawn"", ""target"": """ & SafeGetPart(parts, 1) & """}"

        Case "play_sound"
            ' play_sound:sound_id
            json = "{""type"": ""play_sound"", ""sound"": """ & SafeGetPart(parts, 1) & """}"

        Case Else
            ' Unknown action type - output as generic
            json = "{""type"": """ & EscapeJsonString(actionType) & """}"
    End Select

    BuildActionJson = json
End Function

'-------------------------------------------------------------------------------
' SafeGetPart - Safely get array element or empty string
'-------------------------------------------------------------------------------
Private Function SafeGetPart(parts() As String, idx As Integer) As String
    If idx <= UBound(parts) Then
        SafeGetPart = Trim(parts(idx))
    Else
        SafeGetPart = ""
    End If
End Function

'-------------------------------------------------------------------------------
' SafeGetNumPart - Safely get array element as number or default
'-------------------------------------------------------------------------------
Private Function SafeGetNumPart(parts() As String, idx As Integer, defaultVal As Double) As String
    Dim val As String
    val = SafeGetPart(parts, idx)

    If Len(val) = 0 Then
        SafeGetNumPart = CStr(defaultVal)
    ElseIf IsNumeric(val) Then
        SafeGetNumPart = Replace(CStr(CDbl(val)), ",", ".")
    Else
        SafeGetNumPart = CStr(defaultVal)
    End If
End Function

'-------------------------------------------------------------------------------
' SetupCutscenesSheet - Creates Cutscenes sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupCutscenesSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CUTSCENES)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_CUTSCENES
    End If

    Dim headers As Variant
    headers = Array("id", "name", "trigger", "trigger_target", "once_only", "actions")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: cut_name (e.g., cut_intro_village)"
    SafeAddComment ws.Cells(1, 3), "Trigger types: zone_enter, quest_complete, quest_start, interact, manual"
    SafeAddComment ws.Cells(1, 4), "Zone ID, Quest ID, or NPC ID depending on trigger"
    SafeAddComment ws.Cells(1, 5), "TRUE/FALSE - only play once per save"
    SafeAddComment ws.Cells(1, 6), "Actions separated by ###. Format: type:param1:param2:param3" & vbCrLf & _
                                   "Types: dialogue:speaker:text:portrait, wait:duration, fade_in:duration, fade_out:duration, " & _
                                   "move:target:x:y:speed, camera_pan:x:y:duration, camera_shake:intensity:duration, " & _
                                   "camera_reset:duration, set_facing:target:direction, spawn:npc_id:x:y, despawn:target, play_sound:sound_id"

    ' Add data validation for trigger column (C)
    Dim triggerRange As Range
    Set triggerRange = ws.Range("C2:C1000")
    With triggerRange.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
             Formula1:="zone_enter,quest_complete,quest_start,interact,manual"
        .IgnoreBlank = True
        .InCellDropdown = True
        .ShowError = True
        .ErrorTitle = "Invalid Trigger"
        .ErrorMessage = "Please select a valid trigger type from the dropdown."
    End With

    ' Add data validation for once_only column (E)
    Dim onceOnlyRange As Range
    Set onceOnlyRange = ws.Range("E2:E1000")
    With onceOnlyRange.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
             Formula1:="TRUE,FALSE"
        .IgnoreBlank = True
        .InCellDropdown = True
        .ShowError = True
        .ErrorTitle = "Invalid Value"
        .ErrorMessage = "Please select TRUE or FALSE."
    End With

    MsgBox "Cutscenes sheet created with headers and data validation!", vbInformation
End Sub
