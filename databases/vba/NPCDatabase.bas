Attribute VB_Name = "NPCDatabase"
'===============================================================================
' NPCDatabase Module
' Handles validation and export for NPCs and Shop Inventory
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_NPCS As String = "NPCs"
Private Const SHEET_SHOP_INVENTORY As String = "ShopInventory"

' Column indices for NPCs (1-based)
Private Const COL_NPC_ID As Integer = 1
Private Const COL_NPC_NAME As Integer = 2
Private Const COL_NPC_TYPE As Integer = 3
Private Const COL_NPC_LOCATION As Integer = 4
Private Const COL_NPC_SHOP_INVENTORY_ID As Integer = 5
Private Const COL_NPC_DIALOGUE_GREETING As Integer = 6
Private Const COL_NPC_FACTION As Integer = 7
Private Const COL_NPC_SPRITE_ID As Integer = 8
Private Const COL_NPC_MIN_LEVEL As Integer = 9
Private Const COL_NPC_IS_INTERACTABLE As Integer = 10
Private Const COL_NPC_PORTRAIT_ID As Integer = 11
Private Const COL_NPC_DIALOGUE_TALK_ID As Integer = 12
Private Const COL_NPC_SPAWN_CONDITION As Integer = 13

' Column indices for ShopInventory
Private Const COL_SI_ID As Integer = 1
Private Const COL_SI_NAME As Integer = 2
Private Const COL_SI_ITEM_ID As Integer = 3
Private Const COL_SI_ITEM_TYPE As Integer = 4
Private Const COL_SI_STOCK As Integer = 5
Private Const COL_SI_RESTOCK_HOURS As Integer = 6
Private Const COL_SI_PRICE_MULTIPLIER As Integer = 7
Private Const COL_SI_CURRENCY_TYPE As Integer = 8
Private Const COL_SI_MIN_PLAYER_LEVEL As Integer = 9
Private Const COL_SI_MAX_PLAYER_LEVEL As Integer = 10

' Valid dropdown values
Private validNPCTypes() As String
Private validItemTypes() As String
Private validCurrencyTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validNPCTypes = Split("quest_giver,trader,trainer,innkeeper,blacksmith,generic", ",")
    validItemTypes = Split("base,unique,consumable", ",")
    validCurrencyTypes = Split("gold,gems", ",")
End Sub

'===============================================================================
' NPCS
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateNPCs - Validates all rows in NPCs sheet
'-------------------------------------------------------------------------------
Public Sub ValidateNPCs()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NPCS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_NPCS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_NPC_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_NPC_ID).value)

        If Len(id) = 0 Then GoTo NextNPC

        ' Validate ID format
        If Not ValidateId(id, "npc_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: npc_type_name (e.g., npc_guard_captain)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NPC_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate NPC type
        Dim npcType As String
        npcType = LCase(Trim(ws.Cells(i, COL_NPC_TYPE).value))
        If Len(npcType) > 0 And Not ValidateDropdown(npcType, validNPCTypes) Then
            LogValidationError errors, errorCount, i, "Type", _
                "Invalid type. Valid: quest_giver, trader, trainer, innkeeper, blacksmith, generic"
        End If

        ' Validate trader has shop_inventory_id
        If npcType = "trader" Then
            If Len(Trim(ws.Cells(i, COL_NPC_SHOP_INVENTORY_ID).value)) = 0 Then
                LogValidationError errors, errorCount, i, "Shop Inventory ID", _
                    "Traders must have a shop_inventory_id"
            End If
        End If

        ' Validate min_level non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_NPC_MIN_LEVEL)) < 0 Then
            LogValidationError errors, errorCount, i, "Min Level", "Cannot be negative"
        End If

NextNPC:
    Next i

    ShowValidationResults errors, errorCount, "NPCs"
End Sub

'-------------------------------------------------------------------------------
' ExportNPCs - Exports NPCs to JSON
'-------------------------------------------------------------------------------
Public Sub ExportNPCs()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NPCS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_NPCS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""npcs"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_NPC_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_NPC_ID).value)

        If Len(id) = 0 Then GoTo NextExportNPC

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_NPC_TYPE), "generic"))) & """," & vbCrLf
        json = json & "      ""location"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_LOCATION))) & """," & vbCrLf
        json = json & "      ""shop_inventory_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_SHOP_INVENTORY_ID))) & """," & vbCrLf
        json = json & "      ""dialogue_greeting"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_DIALOGUE_GREETING))) & """," & vbCrLf
        json = json & "      ""faction"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_FACTION))) & """," & vbCrLf
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""min_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_NPC_MIN_LEVEL), 1)) & "," & vbCrLf
        json = json & "      ""is_interactable"": " & LCase(CStr(GetDefaultBoolean(ws.Cells(i, COL_NPC_IS_INTERACTABLE), True))) & "," & vbCrLf
        json = json & "      ""portrait_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_PORTRAIT_ID))) & """," & vbCrLf
        json = json & "      ""dialogue_talk_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_DIALOGUE_TALK_ID))) & """," & vbCrLf
        json = json & "      ""spawn_condition"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NPC_SPAWN_CONDITION))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportNPC:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "npcs.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " NPCs to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'===============================================================================
' SHOP INVENTORY
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateShopInventory - Validates all rows in ShopInventory sheet
'-------------------------------------------------------------------------------
Public Sub ValidateShopInventory()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SHOP_INVENTORY)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SHOP_INVENTORY & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SI_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SI_ID).value)

        If Len(id) = 0 Then GoTo NextShopItem

        ' Validate ID format
        If Not ValidateId(id, "shop_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: shop_type_name (e.g., shop_weapons_basic)"
        End If

        ' Validate item_id not empty
        If Len(Trim(ws.Cells(i, COL_SI_ITEM_ID).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Item ID", "Item ID is required"
        End If

        ' Validate item type
        Dim itemType As String
        itemType = LCase(Trim(ws.Cells(i, COL_SI_ITEM_TYPE).value))
        If Len(itemType) > 0 And Not ValidateDropdown(itemType, validItemTypes) Then
            LogValidationError errors, errorCount, i, "Item Type", _
                "Invalid item type. Valid: base, unique, consumable"
        End If

        ' Validate currency type if specified
        Dim currencyType As String
        currencyType = LCase(Trim(ws.Cells(i, COL_SI_CURRENCY_TYPE).value))
        If Len(currencyType) > 0 And Not ValidateDropdown(currencyType, validCurrencyTypes) Then
            LogValidationError errors, errorCount, i, "Currency Type", _
                "Invalid currency type. Valid: gold, gems"
        End If

        ' Validate min <= max level
        Dim minLevel As Double, maxLevel As Double
        minLevel = GetDefaultNumeric(ws.Cells(i, COL_SI_MIN_PLAYER_LEVEL), 1)
        maxLevel = GetDefaultNumeric(ws.Cells(i, COL_SI_MAX_PLAYER_LEVEL), 100)
        If minLevel > maxLevel Then
            LogValidationError errors, errorCount, i, "Min/Max Level", _
                "Min player level cannot be greater than max player level"
        End If

NextShopItem:
    Next i

    ShowValidationResults errors, errorCount, "ShopInventory"
End Sub

'-------------------------------------------------------------------------------
' ExportShopInventory - Exports ShopInventory to JSON
'-------------------------------------------------------------------------------
Public Sub ExportShopInventory()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_SHOP_INVENTORY)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_SHOP_INVENTORY & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""shop_inventory"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_SI_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_SI_ID).value)

        If Len(id) = 0 Then GoTo NextExportShopItem

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SI_NAME))) & """," & vbCrLf
        json = json & "      ""item_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SI_ITEM_ID))) & """," & vbCrLf
        json = json & "      ""item_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SI_ITEM_TYPE), "base"))) & """," & vbCrLf
        json = json & "      ""stock"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SI_STOCK), -1)) & "," & vbCrLf
        json = json & "      ""restock_hours"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SI_RESTOCK_HOURS), 0)) & "," & vbCrLf
        json = json & "      ""price_multiplier"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SI_PRICE_MULTIPLIER), 1.5)) & "," & vbCrLf
        json = json & "      ""currency_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_SI_CURRENCY_TYPE), "gold"))) & """," & vbCrLf
        json = json & "      ""min_player_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SI_MIN_PLAYER_LEVEL), 1)) & "," & vbCrLf
        json = json & "      ""max_player_level"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_SI_MAX_PLAYER_LEVEL), 100)) & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportShopItem:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "shop_inventory.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " shop inventory items to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'===============================================================================
' MASTER EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportAllNPCs - Exports all NPC-related sheets
'-------------------------------------------------------------------------------
Public Sub ExportAllNPCs()
    ExportNPCs
    ExportShopInventory
    If Not g_SilentMode Then
        MsgBox "All NPC databases exported!", vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' ValidateAllNPCs - Validates all NPC-related sheets
'-------------------------------------------------------------------------------
Public Sub ValidateAllNPCs()
    ValidateNPCs
    ValidateShopInventory
End Sub
