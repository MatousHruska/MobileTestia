Attribute VB_Name = "LootableDatabase"
'===============================================================================
' LootableDatabase Module
' Handles validation and export for Lootables (corpses, urns, barrels, etc.)
' Quick-loot containers that can be searched for items and gold
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_LOOTABLES As String = "Lootables"

' Column indices for Lootables (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
Private Const COL_DISPLAY_NAME As Integer = 3
' Loot Settings
Private Const COL_LOOT_TABLE_ID As Integer = 4
Private Const COL_MIN_GOLD As Integer = 5
Private Const COL_MAX_GOLD As Integer = 6
Private Const COL_DROP_CHANCE As Integer = 7
' Respawn
Private Const COL_CAN_RESPAWN As Integer = 8
Private Const COL_RESPAWN_TIME As Integer = 9
' Visuals
Private Const COL_SPRITE_ID As Integer = 10
Private Const COL_INTERACTION_PROMPT As Integer = 11

'===============================================================================
' LOOTABLES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateLootablesData - Validates all rows in Lootables sheet
'-------------------------------------------------------------------------------
Public Sub ValidateLootablesData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOOTABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOOTABLES & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextLootable

        ' Validate ID format
        If Not ValidateId(id, "loot_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: loot_type_name (e.g., loot_corpse_soldier)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate display_name not empty
        If Len(Trim(ws.Cells(i, COL_DISPLAY_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Display Name", "Display name is required"
        End If

        ' Validate sprite_id not empty
        If Len(Trim(ws.Cells(i, COL_SPRITE_ID).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Sprite ID", "Sprite ID is required"
        End If

        ' Validate drop_chance 0-1
        Dim dropChance As Double
        dropChance = GetDefaultNumeric(ws.Cells(i, COL_DROP_CHANCE), 1)
        If dropChance < 0 Or dropChance > 1 Then
            LogValidationError errors, errorCount, i, "Drop Chance", _
                "Must be between 0 and 1 (e.g., 0.75 for 75%)"
        End If

        ' Validate min <= max gold
        Dim minGold As Double, maxGold As Double
        minGold = GetDefaultNumeric(ws.Cells(i, COL_MIN_GOLD), 0)
        maxGold = GetDefaultNumeric(ws.Cells(i, COL_MAX_GOLD), 0)
        If minGold > maxGold Then
            LogValidationError errors, errorCount, i, "Gold Range", _
                "Min gold cannot be greater than max gold"
        End If

        ' Validate respawn_time non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_RESPAWN_TIME), 0) < 0 Then
            LogValidationError errors, errorCount, i, "Respawn Time", "Cannot be negative"
        End If

NextLootable:
    Next i

    ShowValidationResults errors, errorCount, "Lootables"
End Sub

'-------------------------------------------------------------------------------
' ExportLootablesData - Exports Lootables to JSON
'-------------------------------------------------------------------------------
Public Sub ExportLootablesData()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_LOOTABLES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_LOOTABLES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""lootables"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportLootable

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        json = json & "      ""display_name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_DISPLAY_NAME))) & """," & vbCrLf
        ' Loot Settings
        json = json & "      ""loot_table_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LOOT_TABLE_ID))) & """," & vbCrLf
        json = json & "      ""min_gold"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_MIN_GOLD), 0)) & "," & vbCrLf
        json = json & "      ""max_gold"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_MAX_GOLD), 0)) & "," & vbCrLf
        json = json & "      ""drop_chance"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_DROP_CHANCE), 1)) & "," & vbCrLf
        ' Respawn
        json = json & "      ""can_respawn"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_CAN_RESPAWN), False)) & "," & vbCrLf
        json = json & "      ""respawn_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_RESPAWN_TIME), 0)) & "," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""interaction_prompt"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_INTERACTION_PROMPT), "Search")) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportLootable:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "lootables.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " lootables to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupLootablesSheet - Creates headers for Lootables sheet
'-------------------------------------------------------------------------------
Public Sub SetupLootablesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_LOOTABLES)

    Dim headers As Variant
    headers = Array("id", "name", "display_name", "loot_table_id", _
                    "min_gold", "max_gold", "drop_chance", _
                    "can_respawn", "respawn_time", "sprite_id", "interaction_prompt")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_LOOT_TABLE_ID), "LootTable ID for item drops (optional)"
    SafeAddComment ws.Cells(1, COL_DROP_CHANCE), "Chance to have any loot (0.0-1.0, default 1.0)"
    SafeAddComment ws.Cells(1, COL_CAN_RESPAWN), "TRUE = can respawn after looted"
    SafeAddComment ws.Cells(1, COL_RESPAWN_TIME), "Seconds until respawn"
    SafeAddComment ws.Cells(1, COL_SPRITE_ID), "Visual asset (corpse, urn, barrel, etc.)"
    SafeAddComment ws.Cells(1, COL_INTERACTION_PROMPT), "Action text (Search, Loot, Open)"

    ' Auto-fit columns
    ws.Columns("A:K").AutoFit

    If Not g_SilentMode Then
        MsgBox "Lootables sheet headers set up successfully!", vbInformation
    End If
End Sub
