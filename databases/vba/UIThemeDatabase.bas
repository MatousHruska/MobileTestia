Attribute VB_Name = "UIThemeDatabase"
'===============================================================================
' UIThemeDatabase Module
' Handles validation and export for UI Theme settings (key-value pairs)
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_UI_THEME As String = "UITheme"

' Column indices for UITheme (1-based)
Private Const COL_UT_KEY As Integer = 1
Private Const COL_UT_VALUE As Integer = 2
Private Const COL_UT_DESCRIPTION As Integer = 3

'-------------------------------------------------------------------------------
' ExportUITheme - Exports UITheme to JSON (key-value pairs)
'-------------------------------------------------------------------------------
Public Sub ExportUITheme()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_UI_THEME)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_UI_THEME & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_UT_KEY).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim keyName As String
        keyName = Trim(ws.Cells(i, COL_UT_KEY).Value)

        If Len(keyName) = 0 Then GoTo NextExportSetting

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Get value - could be numeric or string (for colors)
        Dim cellValue As Variant
        cellValue = ws.Cells(i, COL_UT_VALUE).Value

        ' Check if it's a color string (contains comma) or numeric
        If InStr(CStr(cellValue), ",") > 0 Then
            ' Color value - export as string
            json = json & "  """ & EscapeJsonString(keyName) & """: """ & EscapeJsonString(CStr(cellValue)) & """"
        Else
            ' Numeric value
            json = json & "  """ & EscapeJsonString(keyName) & """: " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_UT_VALUE)))
        End If

        itemCount = itemCount + 1

NextExportSetting:
    Next i

    json = json & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "ui_theme.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " UI theme settings to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' ValidateUITheme - Validates all rows in UITheme sheet
'-------------------------------------------------------------------------------
Public Sub ValidateUITheme()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_UI_THEME)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_UI_THEME & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_UT_KEY).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim keyName As String
        keyName = Trim(ws.Cells(i, COL_UT_KEY).Value)

        If Len(keyName) = 0 Then GoTo NextThemeSetting

        ' Validate key format (snake_case)
        Dim j As Integer
        For j = 1 To Len(keyName)
            Dim c As String
            c = Mid(keyName, j, 1)
            If Not (c Like "[a-z0-9_]") Then
                LogValidationError errors, errorCount, i, "Key", _
                    "Key must be lowercase snake_case (e.g., color_panel_bg)"
                Exit For
            End If
        Next j

        ' Validate value not empty
        If Len(Trim(ws.Cells(i, COL_UT_VALUE).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Value", "Value is required"
        End If

        ' Validate color format if key starts with "color_"
        If Left(keyName, 6) = "color_" Then
            Dim colorVal As String
            colorVal = Trim(ws.Cells(i, COL_UT_VALUE).Value)
            Dim parts() As String
            parts = Split(colorVal, ",")
            If UBound(parts) < 3 Then
                LogValidationError errors, errorCount, i, "Value", _
                    "Color values must be 'r,g,b,a' format (e.g., 0.12,0.12,0.14,0.9)"
            End If
        End If

NextThemeSetting:
    Next i

    ShowValidationResults errors, errorCount, "UITheme"
End Sub

'-------------------------------------------------------------------------------
' SetupUIThemeSheet - Creates UITheme sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupUIThemeSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_UI_THEME)
    Dim headers As Variant
    headers = Array("key", "value", "description")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Setting key name (e.g., color_panel_bg, font_size_header)"
    SafeAddComment ws.Cells(1, 2), "Value: Colors as 'r,g,b,a' (0.0-1.0), sizes as integers"
    SafeAddComment ws.Cells(1, 3), "Description of what this setting controls"
End Sub
