Attribute VB_Name = "PopupMessageDatabase"
'===============================================================================
' PopupMessageDatabase Module
' Handles validation and export for Popup Messages (screen announcements)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_POPUP_MESSAGES As String = "PopupMessages"

' Column indices for PopupMessages (1-based)
Private Const COL_PM_ID As Integer = 1
Private Const COL_PM_TRIGGER_EVENT As Integer = 2
Private Const COL_PM_TRIGGER_FILTER As Integer = 3
Private Const COL_PM_TITLE As Integer = 4
Private Const COL_PM_SUBTITLE As Integer = 5
Private Const COL_PM_ICON As Integer = 6
Private Const COL_PM_DURATION As Integer = 7
Private Const COL_PM_PRIORITY As Integer = 8
Private Const COL_PM_SOUND As Integer = 9

' Valid trigger events
Private Function GetValidTriggerEvents() As Variant
    GetValidTriggerEvents = Array("zone_enter", "zone_exit", "location_enter", "location_exit", _
                                   "quest_start", "quest_complete", "quest_objective", "cutscene_end", _
                                   "manual")
End Function

' Valid icon types
Private Function GetValidIconTypes() As Variant
    GetValidIconTypes = Array("none", "location", "quest", "warning", "info", "combat", "discovery")
End Function

'-------------------------------------------------------------------------------
' ValidatePopupMessages - Validates all rows in PopupMessages sheet
'-------------------------------------------------------------------------------
Public Sub ValidatePopupMessages()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_POPUP_MESSAGES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_POPUP_MESSAGES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_PM_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_PM_ID).Value)

        If Len(id) = 0 Then GoTo NextPopupMessage

        ' Validate ID format
        If Not ValidateId(id, "popup_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: popup_type_name (e.g., popup_quest_survive)"
        End If

        ' Validate trigger_event
        Dim triggerEvent As String
        triggerEvent = Trim(ws.Cells(i, COL_PM_TRIGGER_EVENT).Value)
        If Len(triggerEvent) = 0 Then
            LogValidationError errors, errorCount, i, "Trigger Event", "Trigger event is required"
        Else
            Dim validEvents As Variant
            validEvents = GetValidTriggerEvents()
            Dim isValidEvent As Boolean
            isValidEvent = False
            Dim j As Integer
            For j = LBound(validEvents) To UBound(validEvents)
                If LCase(triggerEvent) = LCase(validEvents(j)) Then
                    isValidEvent = True
                    Exit For
                End If
            Next j
            If Not isValidEvent Then
                LogValidationError errors, errorCount, i, "Trigger Event", _
                    "Invalid trigger event. Valid: zone_enter, location_enter, quest_start, cutscene_end, manual"
            End If
        End If

        ' Validate title or subtitle (at least one required)
        Dim title As String, subtitle As String
        title = Trim(ws.Cells(i, COL_PM_TITLE).Value)
        subtitle = Trim(ws.Cells(i, COL_PM_SUBTITLE).Value)
        If Len(title) = 0 And Len(subtitle) = 0 Then
            LogValidationError errors, errorCount, i, "Title/Subtitle", "At least title or subtitle is required"
        End If

        ' Validate icon type
        Dim iconType As String
        iconType = Trim(ws.Cells(i, COL_PM_ICON).Value)
        If Len(iconType) > 0 Then
            Dim validIcons As Variant
            validIcons = GetValidIconTypes()
            Dim isValidIcon As Boolean
            isValidIcon = False
            Dim k As Integer
            For k = LBound(validIcons) To UBound(validIcons)
                If LCase(iconType) = LCase(validIcons(k)) Then
                    isValidIcon = True
                    Exit For
                End If
            Next k
            If Not isValidIcon Then
                LogValidationError errors, errorCount, i, "Icon", _
                    "Invalid icon type. Valid: none, location, quest, warning, info, combat, discovery"
            End If
        End If

        ' Validate duration positive
        Dim duration As Double
        duration = GetDefaultNumeric(ws.Cells(i, COL_PM_DURATION), 3)
        If duration <= 0 Then
            LogValidationError errors, errorCount, i, "Duration", "Must be greater than 0"
        End If

        ' Validate priority 1-10
        Dim priority As Integer
        priority = GetDefaultNumeric(ws.Cells(i, COL_PM_PRIORITY), 5)
        If priority < 1 Or priority > 10 Then
            LogValidationError errors, errorCount, i, "Priority", "Must be between 1 and 10"
        End If

NextPopupMessage:
    Next i

    ShowValidationResults errors, errorCount, "PopupMessages"
End Sub

'-------------------------------------------------------------------------------
' ExportPopupMessages - Exports PopupMessages to JSON
'-------------------------------------------------------------------------------
Public Sub ExportPopupMessages()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_POPUP_MESSAGES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_POPUP_MESSAGES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""popup_messages"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_PM_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_PM_ID).Value)

        If Len(id) = 0 Then GoTo NextExportPopupMessage

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""trigger_event"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_PM_TRIGGER_EVENT)))) & """," & vbCrLf
        json = json & "      ""trigger_filter"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_PM_TRIGGER_FILTER))) & """," & vbCrLf
        json = json & "      ""title"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_PM_TITLE))) & """," & vbCrLf
        json = json & "      ""subtitle"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_PM_SUBTITLE))) & """," & vbCrLf
        json = json & "      ""icon"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_PM_ICON), "none"))) & """," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_PM_DURATION), 3)) & "," & vbCrLf
        json = json & "      ""priority"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_PM_PRIORITY), 5)) & "," & vbCrLf
        json = json & "      ""sound"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_PM_SOUND))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportPopupMessage:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "popup_messages.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " popup messages to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupPopupMessagesSheet - Creates PopupMessages sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupPopupMessagesSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_POPUP_MESSAGES)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_POPUP_MESSAGES
    End If

    Dim headers As Variant
    headers = Array("id", "trigger_event", "trigger_filter", "title", "subtitle", _
                    "icon", "duration", "priority", "sound")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: popup_type_name (e.g., popup_quest_survive, popup_location_forest)"
    SafeAddComment ws.Cells(1, 2), "zone_enter, zone_exit, location_enter, location_exit, quest_start, quest_complete, quest_objective, cutscene_end, manual"
    SafeAddComment ws.Cells(1, 3), "Filter conditions: zone_id:zone_forest, quest_id:quest_survive, cutscene_id:cs_attack. Use key:value format"
    SafeAddComment ws.Cells(1, 4), "Main title text (e.g., 'Entering', 'New Objective')"
    SafeAddComment ws.Cells(1, 5), "Subtitle text (e.g., zone/location name, objective description)"
    SafeAddComment ws.Cells(1, 6), "Icon type: none, location, quest, warning, info, combat, discovery"
    SafeAddComment ws.Cells(1, 7), "How long to display (seconds)"
    SafeAddComment ws.Cells(1, 8), "1-10 (higher priority can replace lower)"
    SafeAddComment ws.Cells(1, 9), "Sound effect to play (optional)"

    If Not g_SilentMode Then
        MsgBox "PopupMessages sheet created with headers!", vbInformation
    End If
End Sub
