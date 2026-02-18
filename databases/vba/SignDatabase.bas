Attribute VB_Name = "SignDatabase"
'===============================================================================
' SignDatabase Module
' Handles validation and export for Signs (readable objects)
' Signs display floating dialogue when interacted with
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_SIGNS As String = "Signs"

' Column indices for Signs (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
' Content
Private Const COL_FLOATING_DIALOGUE_ID As Integer = 3
' Visuals
Private Const COL_SPRITE_ID As Integer = 4
Private Const COL_INTERACTION_PROMPT As Integer = 5

'===============================================================================
' SIGNS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateSignsData - Validates all rows in Signs sheet
'-------------------------------------------------------------------------------
Public Sub ValidateSignsData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SIGNS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SIGNS & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextSign

        ' Validate ID format
        If Not ValidateId(id, "sign_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: sign_zone_name (e.g., sign_forest_warning)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate floating_dialogue_id not empty
        If Len(Trim(ws.Cells(i, COL_FLOATING_DIALOGUE_ID).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Floating Dialogue ID", _
                "Floating dialogue ID is required"
        End If

NextSign:
    Next i

    ShowValidationResults errors, errorCount, "Signs"
End Sub

'-------------------------------------------------------------------------------
' ExportSignsData - Exports Signs to JSON
'-------------------------------------------------------------------------------
Public Sub ExportSignsData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SIGNS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SIGNS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""signs"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportSign

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        ' Content
        json = json & "      ""floating_dialogue_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_FLOATING_DIALOGUE_ID))) & """," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""interaction_prompt"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_INTERACTION_PROMPT), "Read")) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportSign:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "signs.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " signs to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupSignsSheet - Creates headers for Signs sheet
'-------------------------------------------------------------------------------
Public Sub SetupSignsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_SIGNS)

    Dim headers As Variant
    headers = Array("id", "name", "floating_dialogue_id", "sprite_id", "interaction_prompt")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_FLOATING_DIALOGUE_ID), "FloatingDialogue ID to display when read"
    SafeAddComment ws.Cells(1, COL_SPRITE_ID), "Visual asset for the sign"
    SafeAddComment ws.Cells(1, COL_INTERACTION_PROMPT), "Action text (default: Read)"

    ' Auto-fit columns
    ws.Columns("A:E").AutoFit

    If Not g_SilentMode Then
        MsgBox "Signs sheet headers set up successfully!", vbInformation
    End If
End Sub
