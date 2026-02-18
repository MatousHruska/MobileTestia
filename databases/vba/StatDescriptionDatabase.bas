Attribute VB_Name = "StatDescriptionDatabase"
'===============================================================================
' StatDescriptionDatabase Module
' Handles validation and export for Stat Descriptions (UI tooltips)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_STAT_DESCRIPTIONS As String = "StatDescriptions"

' Column indices for StatDescriptions (1-based)
Private Const COL_SD_ID As Integer = 1
Private Const COL_SD_NAME As Integer = 2
Private Const COL_SD_CATEGORY As Integer = 3
Private Const COL_SD_DESCRIPTION As Integer = 4

' Valid categories
Private Function GetValidCategories() As Variant
    GetValidCategories = Array("primary", "resource", "offensive", "defensive", "utility")
End Function

'-------------------------------------------------------------------------------
' ValidateStatDescriptions - Validates all rows in StatDescriptions sheet
'-------------------------------------------------------------------------------
Public Sub ValidateStatDescriptions()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_STAT_DESCRIPTIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_STAT_DESCRIPTIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SD_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SD_ID).Value)

        If Len(id) = 0 Then GoTo NextStatDescription

        ' Validate ID format
        If Not ValidateId(id, "stat_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: stat_name (e.g., stat_strength, stat_attack_power)"
        End If

        ' Validate name required
        Dim statName As String
        statName = Trim(ws.Cells(i, COL_SD_NAME).Value)
        If Len(statName) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Display name is required"
        End If

        ' Validate category
        Dim category As String
        category = Trim(ws.Cells(i, COL_SD_CATEGORY).Value)
        If Len(category) > 0 Then
            Dim validCats As Variant
            validCats = GetValidCategories()
            Dim isValidCat As Boolean
            isValidCat = False
            Dim j As Integer
            For j = LBound(validCats) To UBound(validCats)
                If LCase(category) = LCase(validCats(j)) Then
                    isValidCat = True
                    Exit For
                End If
            Next j
            If Not isValidCat Then
                LogValidationError errors, errorCount, i, "Category", _
                    "Invalid category. Valid: primary, resource, offensive, defensive, utility"
            End If
        End If

        ' Validate description required
        Dim description As String
        description = Trim(ws.Cells(i, COL_SD_DESCRIPTION).Value)
        If Len(description) = 0 Then
            LogValidationError errors, errorCount, i, "Description", "Description is required"
        End If

NextStatDescription:
    Next i

    ShowValidationResults errors, errorCount, "StatDescriptions"
End Sub

'-------------------------------------------------------------------------------
' ExportStatDescriptions - Exports StatDescriptions to JSON
'-------------------------------------------------------------------------------
Public Sub ExportStatDescriptions()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_STAT_DESCRIPTIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_STAT_DESCRIPTIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""stat_descriptions"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SD_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SD_ID).Value)

        If Len(id) = 0 Then GoTo NextExportStatDescription

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SD_NAME))) & """," & vbCrLf
        json = json & "      ""category"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SD_CATEGORY)))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SD_DESCRIPTION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportStatDescription:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "stat_descriptions.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " stat descriptions to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupStatDescriptionsSheet - Creates StatDescriptions sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupStatDescriptionsSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_STAT_DESCRIPTIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_STAT_DESCRIPTIONS
    End If

    Dim headers As Variant
    headers = Array("id", "name", "category", "description")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: stat_name (e.g., stat_strength, stat_attack_power, stat_life_regen)"
    SafeAddComment ws.Cells(1, 2), "Display name shown in UI (e.g., 'Strength', 'Attack Power')"
    SafeAddComment ws.Cells(1, 3), "Category: primary, resource, offensive, defensive, utility"
    SafeAddComment ws.Cells(1, 4), "Description shown when player taps the stat in Stats panel"

    MsgBox "StatDescriptions sheet created with headers!", vbInformation
End Sub
