Attribute VB_Name = "FloatingDialogueDatabase"
'===============================================================================
' FloatingDialogueDatabase Module
' Handles validation and export for Floating Dialogues (character barks)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_FLOATING_DIALOGUES As String = "FloatingDialogues"

' Column indices for FloatingDialogues (1-based)
Private Const COL_FLD_ID As Integer = 1
Private Const COL_FLD_TRIGGER_EVENT As Integer = 2
Private Const COL_FLD_TRIGGER_FILTER As Integer = 3
Private Const COL_FLD_TEXT As Integer = 4
Private Const COL_FLD_VOICE_FILE As Integer = 5
Private Const COL_FLD_PROBABILITY As Integer = 6
Private Const COL_FLD_PRIORITY As Integer = 7
Private Const COL_FLD_COOLDOWN_GROUP As Integer = 8
Private Const COL_FLD_COOLDOWN As Integer = 9
Private Const COL_FLD_DURATION As Integer = 10
Private Const COL_FLD_WEIGHT As Integer = 11

' Valid trigger events
Private Function GetValidTriggerEvents() As Variant
    GetValidTriggerEvents = Array("zone_enter", "zone_exit", "item_pickup", "item_equip", _
                                   "potion_use", "skill_use", "enemy_kill", "boss_kill", _
                                   "critical_hit", "near_death", "level_up", "quest_complete", _
                                   "quest_start", "gold_pickup", "chest_open", "shrine_activate", _
                                   "player_idle", "combat_start", "combat_end", "revive")
End Function

'-------------------------------------------------------------------------------
' ValidateFloatingDialogues - Validates all rows in FloatingDialogues sheet
'-------------------------------------------------------------------------------
Public Sub ValidateFloatingDialogues()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_FLOATING_DIALOGUES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_FLOATING_DIALOGUES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_FLD_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_FLD_ID).Value)

        If Len(id) = 0 Then GoTo NextFloatingDialogue

        ' Validate ID format
        If Not ValidateId(id, "fld_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: fld_trigger_name (e.g., fld_zone_evil_lair)"
        End If

        ' Validate trigger_event
        Dim triggerEvent As String
        triggerEvent = Trim(ws.Cells(i, COL_FLD_TRIGGER_EVENT).Value)
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
                    "Invalid trigger event. Valid: zone_enter, item_pickup, potion_use, enemy_kill, etc."
            End If
        End If

        ' Validate text not empty
        If Len(Trim(ws.Cells(i, COL_FLD_TEXT).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Text", "Dialogue text is required"
        End If

        ' Validate probability 0-1
        Dim probability As Double
        probability = GetDefaultNumeric(ws.Cells(i, COL_FLD_PROBABILITY), 1)
        If probability < 0 Or probability > 1 Then
            LogValidationError errors, errorCount, i, "Probability", "Must be between 0.0 and 1.0"
        End If

        ' Validate priority 1-10
        Dim priority As Integer
        priority = GetDefaultNumeric(ws.Cells(i, COL_FLD_PRIORITY), 5)
        If priority < 1 Or priority > 10 Then
            LogValidationError errors, errorCount, i, "Priority", "Must be between 1 and 10"
        End If

        ' Validate cooldown non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_FLD_COOLDOWN)) < 0 Then
            LogValidationError errors, errorCount, i, "Cooldown", "Cannot be negative"
        End If

        ' Validate duration non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_FLD_DURATION)) < 0 Then
            LogValidationError errors, errorCount, i, "Duration", "Cannot be negative"
        End If

        ' Validate weight positive
        If GetDefaultNumeric(ws.Cells(i, COL_FLD_WEIGHT), 1) <= 0 Then
            LogValidationError errors, errorCount, i, "Weight", "Must be greater than 0"
        End If

NextFloatingDialogue:
    Next i

    ShowValidationResults errors, errorCount, "FloatingDialogues"
End Sub

'-------------------------------------------------------------------------------
' ExportFloatingDialogues - Exports FloatingDialogues to JSON
'-------------------------------------------------------------------------------
Public Sub ExportFloatingDialogues()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_FLOATING_DIALOGUES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_FLOATING_DIALOGUES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""floating_dialogues"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_FLD_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_FLD_ID).Value)

        If Len(id) = 0 Then GoTo NextExportFloatingDialogue

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""trigger_event"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_FLD_TRIGGER_EVENT)))) & """," & vbCrLf
        json = json & "      ""trigger_filter"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_FLD_TRIGGER_FILTER))) & """," & vbCrLf
        json = json & "      ""text"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_FLD_TEXT))) & """," & vbCrLf
        json = json & "      ""voice_file"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_FLD_VOICE_FILE))) & """," & vbCrLf
        json = json & "      ""probability"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_FLD_PROBABILITY), 1)) & "," & vbCrLf
        json = json & "      ""priority"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_FLD_PRIORITY), 5)) & "," & vbCrLf
        json = json & "      ""cooldown_group"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_FLD_COOLDOWN_GROUP))) & """," & vbCrLf
        json = json & "      ""cooldown"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_FLD_COOLDOWN), 60)) & "," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_FLD_DURATION), 3)) & "," & vbCrLf
        json = json & "      ""weight"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_FLD_WEIGHT), 1)) & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportFloatingDialogue:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "floating_dialogues.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " floating dialogues to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupFloatingDialoguesSheet - Creates FloatingDialogues sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupFloatingDialoguesSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_FLOATING_DIALOGUES)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_FLOATING_DIALOGUES
    End If

    Dim headers As Variant
    headers = Array("id", "trigger_event", "trigger_filter", "text", "voice_file", _
                    "probability", "priority", "cooldown_group", "cooldown", "duration", "weight")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: fld_trigger_name (e.g., fld_zone_evil_lair, fld_potion_quip)"
    SafeAddComment ws.Cells(1, 2), "zone_enter, zone_exit, item_pickup, item_equip, potion_use, skill_use, enemy_kill, boss_kill, critical_hit, near_death, level_up, quest_complete, quest_start, gold_pickup, chest_open, shrine_activate, player_idle, combat_start, combat_end, revive"
    SafeAddComment ws.Cells(1, 3), "Filter conditions: zone_id:evil_lair, item_rarity:legendary, enemy_type:boss, etc. Use key:value format"
    SafeAddComment ws.Cells(1, 4), "The dialogue text to display"
    SafeAddComment ws.Cells(1, 5), "Future: audio file path for voice line"
    SafeAddComment ws.Cells(1, 6), "0.0 to 1.0 (0.05 = 5% chance to trigger)"
    SafeAddComment ws.Cells(1, 7), "1-10 (higher priority interrupts lower)"
    SafeAddComment ws.Cells(1, 8), "Group name for shared cooldowns (e.g., loot_reaction, combat_quip)"
    SafeAddComment ws.Cells(1, 9), "Seconds before this specific line can repeat"
    SafeAddComment ws.Cells(1, 10), "How long to display (seconds)"
    SafeAddComment ws.Cells(1, 11), "Weight for random selection among matching lines"

    MsgBox "FloatingDialogues sheet created with headers!", vbInformation
End Sub
