Attribute VB_Name = "LootTableDatabase"
'===============================================================================
' LootTableDatabase Module
' Handles validation and export for Loot Tables
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_LOOT_TABLES As String = "LootTables"

' Column indices for LootTables (1-based)
Private Const COL_LT_ID As Integer = 1
Private Const COL_LT_NAME As Integer = 2
Private Const COL_LT_MIN_DROPS As Integer = 3
Private Const COL_LT_MAX_DROPS As Integer = 4
Private Const COL_LT_NOTHING_WEIGHT As Integer = 5
Private Const COL_LT_COMMON_WEIGHT As Integer = 6
Private Const COL_LT_MAGIC_WEIGHT As Integer = 7
Private Const COL_LT_RARE_WEIGHT As Integer = 8
Private Const COL_LT_UNIQUE_WEIGHT As Integer = 9
Private Const COL_LT_GOLD_MIN As Integer = 10
Private Const COL_LT_GOLD_MAX As Integer = 11
Private Const COL_LT_ITEM_POOL As Integer = 12      ' Comma-separated item base IDs or tags
Private Const COL_LT_GUARANTEED_DROPS As Integer = 13

'===============================================================================
' LOOT TABLES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateLootTables - Validates all rows in LootTables sheet
'-------------------------------------------------------------------------------
Public Sub ValidateLootTables()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOOT_TABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOOT_TABLES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_LT_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_LT_ID).value)

        If Len(id) = 0 Then GoTo NextLootTable

        ' Validate ID format
        If Not ValidateId(id, "loot_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: loot_type_name (e.g., loot_zombie_basic)"
        End If

        ' Validate min <= max drops
        Dim minDrops As Double, maxDrops As Double
        minDrops = GetDefaultNumeric(ws.Cells(i, COL_LT_MIN_DROPS))
        maxDrops = GetDefaultNumeric(ws.Cells(i, COL_LT_MAX_DROPS))
        If minDrops > maxDrops Then
            LogValidationError errors, errorCount, i, "Min/Max Drops", _
                "Min drops cannot be greater than max drops"
        End If

        ' Validate weights are non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_LT_NOTHING_WEIGHT)) < 0 Or _
           GetDefaultNumeric(ws.Cells(i, COL_LT_COMMON_WEIGHT)) < 0 Or _
           GetDefaultNumeric(ws.Cells(i, COL_LT_MAGIC_WEIGHT)) < 0 Or _
           GetDefaultNumeric(ws.Cells(i, COL_LT_RARE_WEIGHT)) < 0 Or _
           GetDefaultNumeric(ws.Cells(i, COL_LT_UNIQUE_WEIGHT)) < 0 Then
            LogValidationError errors, errorCount, i, "Weights", "Weights cannot be negative"
        End If

        ' Validate gold min <= max
        Dim goldMin As Double, goldMax As Double
        goldMin = GetDefaultNumeric(ws.Cells(i, COL_LT_GOLD_MIN))
        goldMax = GetDefaultNumeric(ws.Cells(i, COL_LT_GOLD_MAX))
        If goldMin > goldMax Then
            LogValidationError errors, errorCount, i, "Gold Min/Max", _
                "Gold min cannot be greater than gold max"
        End If

NextLootTable:
    Next i

    ShowValidationResults errors, errorCount, "LootTables"
End Sub

'-------------------------------------------------------------------------------
' ExportLootTables - Exports LootTables to JSON
'-------------------------------------------------------------------------------
Public Sub ExportLootTables()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOOT_TABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOOT_TABLES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""loot_tables"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_LT_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_LT_ID).value)

        If Len(id) = 0 Then GoTo NextExportLoot

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LT_NAME))) & """," & vbCrLf
        json = json & "      ""min_drops"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_MIN_DROPS), 1)) & "," & vbCrLf
        json = json & "      ""max_drops"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_MAX_DROPS), 3)) & "," & vbCrLf
        json = json & "      ""rarity_weights"": {" & vbCrLf
        json = json & "        ""nothing"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_NOTHING_WEIGHT), 50)) & "," & vbCrLf
        json = json & "        ""common"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_COMMON_WEIGHT), 100)) & "," & vbCrLf
        json = json & "        ""magic"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_MAGIC_WEIGHT), 30)) & "," & vbCrLf
        json = json & "        ""rare"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_RARE_WEIGHT), 10)) & "," & vbCrLf
        json = json & "        ""unique"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_UNIQUE_WEIGHT), 1)) & vbCrLf
        json = json & "      }," & vbCrLf
        json = json & "      ""gold_min"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_GOLD_MIN))) & "," & vbCrLf
        json = json & "      ""gold_max"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_LT_GOLD_MAX), 10)) & "," & vbCrLf
        json = json & "      ""item_pool"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LT_ITEM_POOL))) & """," & vbCrLf
        json = json & "      ""guaranteed_drops"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LT_GUARANTEED_DROPS))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportLoot:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "loot_tables.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " loot tables to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub
