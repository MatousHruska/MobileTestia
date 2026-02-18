Attribute VB_Name = "LoreEchoDatabase"
'===============================================================================
' LoreEchoDatabase Module
' Handles validation and export for Lore Echoes (audio lore objects)
' Lore echoes are collectible audio/text snippets that reveal story
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_LORE_ECHOES As String = "LoreEchoes"

' Column indices for LoreEchoes (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
' Content
Private Const COL_AUDIO_ID As Integer = 3
Private Const COL_SUBTITLE_TEXT As Integer = 4
Private Const COL_DURATION As Integer = 5
' Behavior
Private Const COL_CAN_REPLAY As Integer = 6
' Visuals
Private Const COL_SPRITE_ID As Integer = 7
Private Const COL_INTERACTION_PROMPT As Integer = 8

'===============================================================================
' LORE ECHOES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateLoreEchoesData - Validates all rows in LoreEchoes sheet
'-------------------------------------------------------------------------------
Public Sub ValidateLoreEchoesData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LORE_ECHOES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LORE_ECHOES & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextEcho

        ' Validate ID format
        If Not ValidateId(id, "echo_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: echo_zone_name (e.g., echo_crypt_builder)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate subtitle_text not empty
        If Len(Trim(ws.Cells(i, COL_SUBTITLE_TEXT).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Subtitle Text", _
                "Subtitle text is required for accessibility"
        End If

        ' Validate duration non-negative
        Dim duration As Double
        duration = GetDefaultNumeric(ws.Cells(i, COL_DURATION), 5)
        If duration < 0 Then
            LogValidationError errors, errorCount, i, "Duration", "Cannot be negative"
        End If

NextEcho:
    Next i

    ShowValidationResults errors, errorCount, "LoreEchoes"
End Sub

'-------------------------------------------------------------------------------
' ExportLoreEchoesData - Exports LoreEchoes to JSON
'-------------------------------------------------------------------------------
Public Sub ExportLoreEchoesData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LORE_ECHOES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LORE_ECHOES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""lore_echoes"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportEcho

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        ' Content
        json = json & "      ""audio_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_AUDIO_ID))) & """," & vbCrLf
        json = json & "      ""subtitle_text"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SUBTITLE_TEXT))) & """," & vbCrLf
        json = json & "      ""duration"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_DURATION), 5)) & "," & vbCrLf
        ' Behavior
        json = json & "      ""can_replay"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_CAN_REPLAY), True)) & "," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""interaction_prompt"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_INTERACTION_PROMPT), "Listen")) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportEcho:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "lore_echoes.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " lore echoes to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupLoreEchoesSheet - Creates headers for LoreEchoes sheet
'-------------------------------------------------------------------------------
Public Sub SetupLoreEchoesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_LORE_ECHOES)

    Dim headers As Variant
    headers = Array("id", "name", "audio_id", "subtitle_text", "duration", _
                    "can_replay", "sprite_id", "interaction_prompt")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_AUDIO_ID), "Future: audio file reference"
    SafeAddComment ws.Cells(1, COL_SUBTITLE_TEXT), "Text shown/spoken (required for accessibility)"
    SafeAddComment ws.Cells(1, COL_DURATION), "Playback duration in seconds"
    SafeAddComment ws.Cells(1, COL_CAN_REPLAY), "TRUE = can listen again after first time"
    SafeAddComment ws.Cells(1, COL_SPRITE_ID), "Visual asset (glowing rune, etc.)"
    SafeAddComment ws.Cells(1, COL_INTERACTION_PROMPT), "Action text (default: Listen)"

    ' Auto-fit columns
    ws.Columns("A:H").AutoFit

    If Not g_SilentMode Then
        MsgBox "LoreEchoes sheet headers set up successfully!", vbInformation
    End If
End Sub
