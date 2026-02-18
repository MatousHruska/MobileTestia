Attribute VB_Name = "ChestDatabase"
'===============================================================================
' ChestDatabase Module
' Handles validation and export for Chests (Quest and Loot chests)
' Database-driven chest spawning - SpawnPoints reference chest IDs
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_CHESTS As String = "Chests"

' Column indices for Chests (1-based)
' Core
Private Const COL_CH_ID As Integer = 1
Private Const COL_CH_NAME As Integer = 2
Private Const COL_CH_TYPE As Integer = 3
Private Const COL_CH_ZONE_ID As Integer = 4
' Spawn Settings
Private Const COL_CH_SPAWN_CHANCE As Integer = 5
Private Const COL_CH_WOODEN_WEIGHT As Integer = 6
Private Const COL_CH_IRON_WEIGHT As Integer = 7
Private Const COL_CH_GOLDEN_WEIGHT As Integer = 8
' Loot Settings
Private Const COL_CH_LOOT_TABLE_ID As Integer = 9
Private Const COL_CH_MIN_ITEMS As Integer = 10
Private Const COL_CH_MAX_ITEMS As Integer = 11
Private Const COL_CH_GUARANTEED_GOLD As Integer = 12
' Fixed Contents (Quest chests)
Private Const COL_CH_FIXED_GOLD As Integer = 13
Private Const COL_CH_FIXED_ITEMS As Integer = 14
' Respawn
Private Const COL_CH_CAN_RESPAWN As Integer = 15
Private Const COL_CH_RESPAWN_TIME As Integer = 16
' Quest Integration
Private Const COL_CH_QUEST_ID As Integer = 17
Private Const COL_CH_REQUIRED_QUEST_STATE As Integer = 18
' Meta
Private Const COL_CH_DESCRIPTION As Integer = 19

' Valid dropdown values
Private validChestTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validChestTypes = Split("loot,quest", ",")
End Sub

'===============================================================================
' CHESTS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateChests - Validates all rows in Chests sheet
'-------------------------------------------------------------------------------
Public Sub ValidateChests()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CHESTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CHESTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CH_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CH_ID).value)

        If Len(id) = 0 Then GoTo NextChest

        ' Validate ID format
        If Not ValidateId(id, "chest_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: chest_type_zone_name (e.g., chest_loot_forest_01)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_CH_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate chest type
        Dim chestType As String
        chestType = LCase(Trim(ws.Cells(i, COL_CH_TYPE).value))
        If Len(chestType) > 0 And Not ValidateDropdown(chestType, validChestTypes) Then
            LogValidationError errors, errorCount, i, "Chest Type", _
                "Invalid type. Valid: loot, quest"
        End If

        ' Validate spawn_chance 0-1
        Dim spawnChance As Double
        spawnChance = GetDefaultNumeric(ws.Cells(i, COL_CH_SPAWN_CHANCE), 1)
        If spawnChance < 0 Or spawnChance > 1 Then
            LogValidationError errors, errorCount, i, "Spawn Chance", _
                "Must be between 0 and 1 (e.g., 0.75 for 75%)"
        End If

        ' Validate tier weights are non-negative
        Dim woodenWeight As Double, ironWeight As Double, goldenWeight As Double
        woodenWeight = GetDefaultNumeric(ws.Cells(i, COL_CH_WOODEN_WEIGHT), 70)
        ironWeight = GetDefaultNumeric(ws.Cells(i, COL_CH_IRON_WEIGHT), 25)
        goldenWeight = GetDefaultNumeric(ws.Cells(i, COL_CH_GOLDEN_WEIGHT), 5)

        If woodenWeight < 0 Or ironWeight < 0 Or goldenWeight < 0 Then
            LogValidationError errors, errorCount, i, "Tier Weights", _
                "Tier weights cannot be negative"
        End If

        ' At least one tier weight should be > 0
        If woodenWeight = 0 And ironWeight = 0 And goldenWeight = 0 Then
            LogValidationError errors, errorCount, i, "Tier Weights", _
                "At least one tier weight must be greater than 0"
        End If

        ' Validate min <= max items
        Dim minItems As Double, maxItems As Double
        minItems = GetDefaultNumeric(ws.Cells(i, COL_CH_MIN_ITEMS), 0)
        maxItems = GetDefaultNumeric(ws.Cells(i, COL_CH_MAX_ITEMS), 2)
        If minItems > maxItems Then
            LogValidationError errors, errorCount, i, "Min/Max Items", _
                "Min items cannot be greater than max items"
        End If

        ' Validate respawn_time non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_CH_RESPAWN_TIME), 300) < 0 Then
            LogValidationError errors, errorCount, i, "Respawn Time", "Cannot be negative"
        End If

        ' Quest chests should have fixed items or gold
        If chestType = "quest" Then
            Dim fixedGold As Double
            Dim fixedItems As String
            fixedGold = GetDefaultNumeric(ws.Cells(i, COL_CH_FIXED_GOLD), 0)
            fixedItems = Trim(ws.Cells(i, COL_CH_FIXED_ITEMS).value)
            If fixedGold = 0 And Len(fixedItems) = 0 Then
                LogValidationError errors, errorCount, i, "Fixed Contents", _
                    "Quest chests should have fixed_gold or fixed_items defined"
            End If
        End If

        ' Loot chests should have loot_table_id or guaranteed_gold
        If chestType = "loot" Then
            Dim lootTableId As String
            Dim guaranteedGold As Boolean
            lootTableId = Trim(ws.Cells(i, COL_CH_LOOT_TABLE_ID).value)
            guaranteedGold = GetDefaultBoolean(ws.Cells(i, COL_CH_GUARANTEED_GOLD), True)
            If Len(lootTableId) = 0 And Not guaranteedGold Then
                LogValidationError errors, errorCount, i, "Loot Settings", _
                    "Loot chests should have loot_table_id or guaranteed_gold=true"
            End If
        End If

NextChest:
    Next i

    ShowValidationResults errors, errorCount, "Chests"
End Sub

'-------------------------------------------------------------------------------
' ExportChests - Exports Chests to JSON
'-------------------------------------------------------------------------------
Public Sub ExportChests()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CHESTS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CHESTS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""chests"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CH_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CH_ID).value)

        If Len(id) = 0 Then GoTo NextExportChest

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_NAME))) & """," & vbCrLf
        json = json & "      ""chest_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_CH_TYPE), "loot"))) & """," & vbCrLf
        json = json & "      ""zone_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_ZONE_ID))) & """," & vbCrLf
        ' Spawn Settings
        json = json & "      ""spawn_chance"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_SPAWN_CHANCE), 1)) & "," & vbCrLf
        json = json & "      ""wooden_weight"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_WOODEN_WEIGHT), 70)) & "," & vbCrLf
        json = json & "      ""iron_weight"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_IRON_WEIGHT), 25)) & "," & vbCrLf
        json = json & "      ""golden_weight"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_GOLDEN_WEIGHT), 5)) & "," & vbCrLf
        ' Loot Settings
        json = json & "      ""loot_table_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_LOOT_TABLE_ID))) & """," & vbCrLf
        json = json & "      ""min_items"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_MIN_ITEMS), 0)) & "," & vbCrLf
        json = json & "      ""max_items"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_MAX_ITEMS), 2)) & "," & vbCrLf
        json = json & "      ""guaranteed_gold"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_CH_GUARANTEED_GOLD), True)) & "," & vbCrLf
        ' Fixed Contents (Quest)
        json = json & "      ""fixed_gold"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_FIXED_GOLD), 0)) & "," & vbCrLf
        json = json & "      ""fixed_items"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_FIXED_ITEMS))) & """," & vbCrLf
        ' Respawn
        json = json & "      ""can_respawn"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_CH_CAN_RESPAWN), True)) & "," & vbCrLf
        json = json & "      ""respawn_time"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_CH_RESPAWN_TIME), 300)) & "," & vbCrLf
        ' Quest Integration
        json = json & "      ""quest_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_QUEST_ID))) & """," & vbCrLf
        json = json & "      ""required_quest_state"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_CH_REQUIRED_QUEST_STATE))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportChest:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "chests.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " chests to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub


'-------------------------------------------------------------------------------
' SetupChestsSheet - Creates headers for Chests sheet
'-------------------------------------------------------------------------------
Public Sub SetupChestsSheet()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CHESTS)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_CHESTS
    End If

    ' Clear existing headers
    ws.Rows(1).ClearContents

    ' Set headers
    ws.Cells(1, COL_CH_ID).value = "id"
    ws.Cells(1, COL_CH_NAME).value = "name"
    ws.Cells(1, COL_CH_TYPE).value = "chest_type"
    ws.Cells(1, COL_CH_ZONE_ID).value = "zone_id"
    ws.Cells(1, COL_CH_SPAWN_CHANCE).value = "spawn_chance"
    ws.Cells(1, COL_CH_WOODEN_WEIGHT).value = "wooden_weight"
    ws.Cells(1, COL_CH_IRON_WEIGHT).value = "iron_weight"
    ws.Cells(1, COL_CH_GOLDEN_WEIGHT).value = "golden_weight"
    ws.Cells(1, COL_CH_LOOT_TABLE_ID).value = "loot_table_id"
    ws.Cells(1, COL_CH_MIN_ITEMS).value = "min_items"
    ws.Cells(1, COL_CH_MAX_ITEMS).value = "max_items"
    ws.Cells(1, COL_CH_GUARANTEED_GOLD).value = "guaranteed_gold"
    ws.Cells(1, COL_CH_FIXED_GOLD).value = "fixed_gold"
    ws.Cells(1, COL_CH_FIXED_ITEMS).value = "fixed_items"
    ws.Cells(1, COL_CH_CAN_RESPAWN).value = "can_respawn"
    ws.Cells(1, COL_CH_RESPAWN_TIME).value = "respawn_time"
    ws.Cells(1, COL_CH_QUEST_ID).value = "quest_id"
    ws.Cells(1, COL_CH_REQUIRED_QUEST_STATE).value = "required_quest_state"
    ws.Cells(1, COL_CH_DESCRIPTION).value = "description"

    ' Format header row
    With ws.Rows(1)
        .Font.Bold = True
        .Interior.Color = RGB(200, 200, 200)
    End With

    ' Auto-fit columns
    ws.Columns("A:S").AutoFit

    MsgBox "Chests sheet headers set up successfully!", vbInformation
End Sub
