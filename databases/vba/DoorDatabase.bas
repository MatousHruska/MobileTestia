Attribute VB_Name = "DoorDatabase"
'===============================================================================
' DoorDatabase Module
' Handles validation and export for Doors (locked doors, quest doors, etc.)
' Doors can be key-locked, lever-controlled, or quest-gated
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_DOORS As String = "Doors"

' Column indices for Doors (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
Private Const COL_DISPLAY_NAME As Integer = 3
' Key Requirements
Private Const COL_REQUIRED_KEY_ID As Integer = 4
Private Const COL_REQUIRED_KEY_NAME As Integer = 5
' Control
Private Const COL_LEVER_CONTROLLED As Integer = 6
' Quest Requirements
Private Const COL_QUEST_REQUIRED_ID As Integer = 7
Private Const COL_QUEST_REQUIRED_STATE As Integer = 8
' State
Private Const COL_DEFAULT_LOCKED As Integer = 9
' Visuals
Private Const COL_SPRITE_ID As Integer = 10
Private Const COL_OPEN_SOUND_ID As Integer = 11
' Meta
Private Const COL_DESCRIPTION As Integer = 12

' Valid dropdown values
Private validQuestStates() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validQuestStates = Split("not_started,active,completed", ",")
End Sub

'===============================================================================
' DOORS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateDoorsData - Validates all rows in Doors sheet
'-------------------------------------------------------------------------------
Public Sub ValidateDoorsData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_DOORS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_DOORS & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextDoor

        ' Validate ID format
        If Not ValidateId(id, "door_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: door_zone_name (e.g., door_forest_secret)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate display_name not empty
        If Len(Trim(ws.Cells(i, COL_DISPLAY_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Display Name", "Display name is required"
        End If

        ' Validate quest_required_state if specified
        Dim questState As String
        questState = LCase(Trim(ws.Cells(i, COL_QUEST_REQUIRED_STATE).Value))
        If Len(questState) > 0 And Not ValidateDropdown(questState, validQuestStates) Then
            LogValidationError errors, errorCount, i, "Quest Required State", _
                "Invalid state. Valid: not_started, active, completed"
        End If

        ' If quest_required_state is set, quest_required_id should also be set
        Dim questId As String
        questId = Trim(ws.Cells(i, COL_QUEST_REQUIRED_ID).Value)
        If Len(questState) > 0 And Len(questId) = 0 Then
            LogValidationError errors, errorCount, i, "Quest Required", _
                "Quest state specified but no quest ID provided"
        End If

NextDoor:
    Next i

    ShowValidationResults errors, errorCount, "Doors"
End Sub

'-------------------------------------------------------------------------------
' ExportDoorsData - Exports Doors to JSON
'-------------------------------------------------------------------------------
Public Sub ExportDoorsData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_DOORS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_DOORS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""doors"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportDoor

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        json = json & "      ""display_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_DISPLAY_NAME))) & """," & vbCrLf
        ' Key Requirements
        json = json & "      ""required_key_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_REQUIRED_KEY_ID))) & """," & vbCrLf
        json = json & "      ""required_key_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_REQUIRED_KEY_NAME))) & """," & vbCrLf
        ' Control
        json = json & "      ""lever_controlled"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_LEVER_CONTROLLED), False)) & "," & vbCrLf
        ' Quest Requirements
        json = json & "      ""quest_required_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_QUEST_REQUIRED_ID))) & """," & vbCrLf
        json = json & "      ""quest_required_state"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_QUEST_REQUIRED_STATE)))) & """," & vbCrLf
        ' State
        json = json & "      ""default_locked"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_DEFAULT_LOCKED), True)) & "," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""open_sound_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_OPEN_SOUND_ID))) & """," & vbCrLf
        ' Meta
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportDoor:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "doors.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " doors to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupDoorsSheet - Creates headers for Doors sheet
'-------------------------------------------------------------------------------
Public Sub SetupDoorsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_DOORS)

    Dim headers As Variant
    headers = Array("id", "name", "display_name", "required_key_id", "required_key_name", _
                    "lever_controlled", "quest_required_id", "quest_required_state", _
                    "default_locked", "sprite_id", "open_sound_id", "description")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_REQUIRED_KEY_ID), "Item ID of key required to unlock (leave empty if no key)"
    SafeAddComment ws.Cells(1, COL_LEVER_CONTROLLED), "TRUE if only a lever can open this door"
    SafeAddComment ws.Cells(1, COL_QUEST_REQUIRED_STATE), "not_started, active, or completed"
    SafeAddComment ws.Cells(1, COL_DEFAULT_LOCKED), "TRUE = door starts locked"

    ' Auto-fit columns
    ws.Columns("A:L").AutoFit

    MsgBox "Doors sheet headers set up successfully!", vbInformation
End Sub
