Attribute VB_Name = "DialogueDatabase"
'===============================================================================
' DialogueDatabase Module
' Handles validation and export for Dialogues
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_DIALOGUES As String = "Dialogues"

' Column indices for Dialogues (1-based)
Private Const COL_DLG_ID As Integer = 1
Private Const COL_DLG_FRAMES As Integer = 2

'-------------------------------------------------------------------------------
' ValidateDialogues - Validates all rows in Dialogues sheet
'-------------------------------------------------------------------------------
Public Sub ValidateDialogues()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_DIALOGUES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_DIALOGUES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_DLG_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_DLG_ID).value)

        If Len(id) = 0 Then GoTo NextDialogue

        ' Validate ID format
        If Not ValidateId(id, "dlg_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: dlg_type_name (e.g., dlg_guard_greeting)"
        End If

        ' Validate frames not empty
        If Len(Trim(ws.Cells(i, COL_DLG_FRAMES).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Frames", _
                "Dialogue must have at least one frame"
        End If

NextDialogue:
    Next i

    ShowValidationResults errors, errorCount, "Dialogues"
End Sub

'-------------------------------------------------------------------------------
' ExportDialogues - Exports Dialogues to JSON
'-------------------------------------------------------------------------------
Public Sub ExportDialogues()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_DIALOGUES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_DIALOGUES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""dialogues"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_DLG_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_DLG_ID).value)

        If Len(id) = 0 Then GoTo NextExportDialogue

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Get frames data and convert to JSON array
        Dim framesData As String
        framesData = Trim(ws.Cells(i, COL_DLG_FRAMES).value)

        Dim framesJson As String
        framesJson = ConvertFramesToJson(framesData)

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""frames"": " & framesJson & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportDialogue:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "dialogues.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " dialogues to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' ConvertFramesToJson - Converts delimited frame string to JSON array
' Format in Excel: text1|||emotion1###text2|||emotion2###text3|||emotion3
' Where ### separates frames and ||| separates text from emotion
'-------------------------------------------------------------------------------
Private Function ConvertFramesToJson(framesData As String) As String
    If Len(framesData) = 0 Then
        ConvertFramesToJson = "[]"
        Exit Function
    End If

    Dim json As String
    json = "[" & vbCrLf

    ' Split by ### to get individual frames
    Dim frames() As String
    frames = Split(framesData, "###")

    Dim frameCount As Integer
    frameCount = 0

    Dim frameIdx As Integer
    For frameIdx = LBound(frames) To UBound(frames)
        Dim frameData As String
        frameData = Trim(frames(frameIdx))

        If Len(frameData) = 0 Then GoTo NextFrame

        ' Split by ||| to get text and emotion
        Dim parts() As String
        parts = Split(frameData, "|||")

        Dim frameText As String
        Dim frameEmotion As String

        frameText = Trim(parts(0))
        If UBound(parts) >= 1 Then
            frameEmotion = Trim(parts(1))
        Else
            frameEmotion = "neutral"
        End If

        If frameCount > 0 Then json = json & "," & vbCrLf

        json = json & "      {" & vbCrLf
        json = json & "        ""text"": """ & EscapeJsonString(frameText) & """," & vbCrLf
        json = json & "        ""emotion"": """ & EscapeJsonString(frameEmotion) & """" & vbCrLf
        json = json & "      }"

        frameCount = frameCount + 1

NextFrame:
    Next frameIdx

    json = json & vbCrLf & "    ]"

    ConvertFramesToJson = json
End Function
