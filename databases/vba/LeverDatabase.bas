Attribute VB_Name = "LeverDatabase"
'===============================================================================
' LeverDatabase Module
' Handles validation and export for Levers (wall levers, floor switches, etc.)
' Levers can control doors and other mechanisms
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_LEVERS As String = "Levers"

' Column indices for Levers (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
Private Const COL_DISPLAY_NAME As Integer = 3
' Linkage
Private Const COL_LINKED_DOOR_ID As Integer = 4
' Behavior
Private Const COL_ONE_SHOT As Integer = 5
Private Const COL_DEFAULT_ON As Integer = 6
' Visuals
Private Const COL_SPRITE_ID As Integer = 7
Private Const COL_SOUND_ID As Integer = 8
' Meta
Private Const COL_DESCRIPTION As Integer = 9

'===============================================================================
' LEVERS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateLeversData - Validates all rows in Levers sheet
'-------------------------------------------------------------------------------
Public Sub ValidateLeversData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LEVERS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LEVERS & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextLever

        ' Validate ID format
        If Not ValidateId(id, "lever_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: lever_zone_name (e.g., lever_crypt_gate)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' linked_door_id validation would require cross-sheet check
        ' This is done at ValidateAll level in MasterExport

NextLever:
    Next i

    ShowValidationResults errors, errorCount, "Levers"
End Sub

'-------------------------------------------------------------------------------
' ExportLeversData - Exports Levers to JSON
'-------------------------------------------------------------------------------
Public Sub ExportLeversData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LEVERS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LEVERS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""levers"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportLever

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        json = json & "      ""display_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_DISPLAY_NAME))) & """," & vbCrLf
        ' Linkage
        json = json & "      ""linked_door_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LINKED_DOOR_ID))) & """," & vbCrLf
        ' Behavior
        json = json & "      ""one_shot"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_ONE_SHOT), False)) & "," & vbCrLf
        json = json & "      ""default_on"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_DEFAULT_ON), False)) & "," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""sound_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SOUND_ID))) & """," & vbCrLf
        ' Meta
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportLever:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "levers.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " levers to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupLeversSheet - Creates headers for Levers sheet
'-------------------------------------------------------------------------------
Public Sub SetupLeversSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_LEVERS)

    Dim headers As Variant
    headers = Array("id", "name", "display_name", "linked_door_id", _
                    "one_shot", "default_on", "sprite_id", "sound_id", "description")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_LINKED_DOOR_ID), "Door ID that this lever controls"
    SafeAddComment ws.Cells(1, COL_ONE_SHOT), "TRUE = can only activate once"
    SafeAddComment ws.Cells(1, COL_DEFAULT_ON), "TRUE = lever starts in ON position"

    ' Auto-fit columns
    ws.Columns("A:I").AutoFit

    MsgBox "Levers sheet headers set up successfully!", vbInformation
End Sub
