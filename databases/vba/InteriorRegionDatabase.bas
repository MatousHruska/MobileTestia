Attribute VB_Name = "InteriorRegionDatabase"
'===============================================================================
' InteriorRegionDatabase Module
' Handles validation and export for Interior Regions (roof hiding system)
' Interior regions define areas where roofs hide when player enters
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_INTERIOR_REGIONS As String = "InteriorRegions"

' Column indices (1-based)
Private Const COL_IR_ID As Integer = 1
Private Const COL_IR_ZONE_ID As Integer = 2
Private Const COL_IR_NAME As Integer = 3
Private Const COL_IR_REGION_VALUE As Integer = 4
Private Const COL_IR_PARENT_REGION_VALUE As Integer = 5
Private Const COL_IR_AMBIENT_LIGHT As Integer = 6
Private Const COL_IR_AMBIENT_COLOR As Integer = 7

'-------------------------------------------------------------------------------
' ValidateInteriorRegions - Validates all rows in InteriorRegions sheet
'-------------------------------------------------------------------------------
Public Sub ValidateInteriorRegions()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_INTERIOR_REGIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_INTERIOR_REGIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_IR_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_IR_ID).Value)

        If Len(id) = 0 Then GoTo NextInteriorRegion

        ' Validate ID format
        If Not ValidateId(id, "int_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: int_name (e.g., int_cave_north)"
        End If

        ' Validate zone_id not empty and has correct prefix
        Dim zoneId As String
        zoneId = Trim(ws.Cells(i, COL_IR_ZONE_ID).Value)
        If Len(zoneId) = 0 Then
            LogValidationError errors, errorCount, i, "Zone ID", "Zone ID is required"
        ElseIf Not ValidateId(zoneId, "zone_") Then
            LogValidationError errors, errorCount, i, "Zone ID", _
                "Invalid Zone ID format. Use: zone_name (e.g., zone_ldtk_test)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_IR_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate region_value is a positive integer
        Dim regionValue As String
        regionValue = Trim(ws.Cells(i, COL_IR_REGION_VALUE).Value)
        If Len(regionValue) = 0 Then
            LogValidationError errors, errorCount, i, "Region Value", "Region Value is required (1-8)"
        ElseIf Not IsNumeric(regionValue) Or CInt(regionValue) < 1 Or CInt(regionValue) > 8 Then
            LogValidationError errors, errorCount, i, "Region Value", _
                "Region Value must be 1-8 (matches LDtk IntGrid value)"
        End If

        ' Validate parent_region_value if provided
        Dim parentValue As String
        parentValue = Trim(ws.Cells(i, COL_IR_PARENT_REGION_VALUE).Value)
        If Len(parentValue) > 0 And parentValue <> "0" Then
            If Not IsNumeric(parentValue) Or CInt(parentValue) < 1 Or CInt(parentValue) > 8 Then
                LogValidationError errors, errorCount, i, "Parent Region Value", _
                    "Parent Region Value must be 0 (no parent) or 1-8"
            End If
        End If

        ' Validate ambient_light if provided
        Dim ambientLight As String
        ambientLight = Trim(ws.Cells(i, COL_IR_AMBIENT_LIGHT).Value)
        If Len(ambientLight) > 0 Then
            If Not IsNumeric(ambientLight) Or CDbl(ambientLight) < 0 Or CDbl(ambientLight) > 1 Then
                LogValidationError errors, errorCount, i, "Ambient Light", _
                    "Ambient Light must be 0.0-1.0 (e.g., 0.6)"
            End If
        End If

        ' Validate ambient_color format if provided
        Dim ambientColor As String
        ambientColor = Trim(ws.Cells(i, COL_IR_AMBIENT_COLOR).Value)
        If Len(ambientColor) > 0 Then
            If Left(ambientColor, 1) <> "#" Or Len(ambientColor) <> 7 Then
                LogValidationError errors, errorCount, i, "Ambient Color", _
                    "Ambient Color must be hex format: #RRGGBB (e.g., #1a1a2e)"
            End If
        End If

NextInteriorRegion:
    Next i

    ShowValidationResults errors, errorCount, "Interior Regions"
End Sub

'-------------------------------------------------------------------------------
' ExportInteriorRegionsData - Exports Interior Regions to JSON
'-------------------------------------------------------------------------------
Public Sub ExportInteriorRegionsData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_INTERIOR_REGIONS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_INTERIOR_REGIONS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""interior_regions"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_IR_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_IR_ID).Value)

        If Len(id) = 0 Then GoTo NextExportInteriorRegion

        If itemCount > 0 Then json = json & "," & vbCrLf

        ' Get values with defaults
        Dim regionValue As Integer
        Dim regionValueStr As String
        regionValueStr = Trim(ws.Cells(i, COL_IR_REGION_VALUE).Value)
        If Len(regionValueStr) > 0 And IsNumeric(regionValueStr) Then
            regionValue = CInt(regionValueStr)
        Else
            regionValue = 1
        End If

        Dim parentRegionValue As Integer
        Dim parentValueStr As String
        parentValueStr = Trim(ws.Cells(i, COL_IR_PARENT_REGION_VALUE).Value)
        If Len(parentValueStr) > 0 And IsNumeric(parentValueStr) Then
            parentRegionValue = CInt(parentValueStr)
        Else
            parentRegionValue = 0
        End If

        Dim ambientLight As Double
        Dim ambientLightStr As String
        ambientLightStr = Trim(ws.Cells(i, COL_IR_AMBIENT_LIGHT).Value)
        If Len(ambientLightStr) > 0 And IsNumeric(ambientLightStr) Then
            ambientLight = CDbl(ambientLightStr)
        Else
            ambientLight = 1
        End If

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""zone_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IR_ZONE_ID))) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IR_NAME))) & """," & vbCrLf
        json = json & "      ""region_value"": " & regionValue & "," & vbCrLf
        json = json & "      ""parent_region_value"": " & parentRegionValue & "," & vbCrLf
        json = json & "      ""ambient_light"": " & Replace(CStr(ambientLight), ",", ".") & "," & vbCrLf
        json = json & "      ""ambient_color"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IR_AMBIENT_COLOR), "#1a1a2e")) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportInteriorRegion:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "interior_regions.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " interior regions to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupInteriorRegionsSheet - Creates/updates the InteriorRegions sheet
'-------------------------------------------------------------------------------
Public Sub SetupInteriorRegionsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_INTERIOR_REGIONS)

    Dim headers As Variant
    headers = Array("id", "zone_id", "name", "region_value", "parent_region_value", _
                    "ambient_light", "ambient_color")

    SetupSheetHeaders ws, headers

    ' Add comments to explain columns
    SafeAddComment ws.Cells(1, 1), "Format: int_name (e.g., int_cave_north, int_house_smith)"
    SafeAddComment ws.Cells(1, 2), "Zone this interior belongs to (e.g., zone_ldtk_test)"
    SafeAddComment ws.Cells(1, 3), "Display name (optional, for debugging)"
    SafeAddComment ws.Cells(1, 4), "IntGrid value in LDtk (1-8). Must match interior_regions layer value."
    SafeAddComment ws.Cells(1, 5), "For nested interiors: parent region value (0 = no parent)"
    SafeAddComment ws.Cells(1, 6), "Interior brightness 0.0-1.0 (1.0 = normal, 0.5 = dim)"
    SafeAddComment ws.Cells(1, 7), "Interior tint color in hex #RRGGBB (e.g., #1a1a2e for dark blue)"

    ' Set column widths
    ws.Columns(1).ColumnWidth = 25  ' id
    ws.Columns(2).ColumnWidth = 18  ' zone_id
    ws.Columns(3).ColumnWidth = 25  ' name
    ws.Columns(4).ColumnWidth = 14  ' region_value
    ws.Columns(5).ColumnWidth = 18  ' parent_region_value
    ws.Columns(6).ColumnWidth = 14  ' ambient_light
    ws.Columns(7).ColumnWidth = 14  ' ambient_color

    If Not g_SilentMode Then
        MsgBox "InteriorRegions sheet setup complete!", vbInformation
    End If
End Sub
