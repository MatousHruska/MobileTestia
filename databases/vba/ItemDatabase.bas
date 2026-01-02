Attribute VB_Name = "ItemDatabase"
'===============================================================================
' ItemDatabase Module
' Handles validation and export for Item Bases, Affixes, and Unique Items
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_ITEM_BASES As String = "ItemBases"
Private Const SHEET_AFFIXES As String = "Affixes"
Private Const SHEET_UNIQUES As String = "UniqueItems"
Private Const SHEET_RARITIES As String = "Rarities"

' Column indices for ItemBases (1-based)
Private Const COL_IB_ID As Integer = 1
Private Const COL_IB_NAME As Integer = 2
Private Const COL_IB_SLOT As Integer = 3
Private Const COL_IB_TYPE As Integer = 4
Private Const COL_IB_WEAPON_DAMAGE As Integer = 5
Private Const COL_IB_PHYSICAL_DAMAGE As Integer = 6
Private Const COL_IB_FIRE_DAMAGE As Integer = 7
Private Const COL_IB_COLD_DAMAGE As Integer = 8
Private Const COL_IB_LIGHTNING_DAMAGE As Integer = 9
Private Const COL_IB_POISON_DAMAGE As Integer = 10
Private Const COL_IB_ATTACK_SPEED As Integer = 11
Private Const COL_IB_BASE_ARMOR As Integer = 12
Private Const COL_IB_REQ_STR As Integer = 13
Private Const COL_IB_REQ_DEX As Integer = 14
Private Const COL_IB_REQ_INT As Integer = 15
Private Const COL_IB_ALLOWED_AFFIX_TAGS As Integer = 16
Private Const COL_IB_DESCRIPTION As Integer = 17
Private Const COL_IB_WEAPON_CATEGORY As Integer = 18

' Column indices for Affixes
Private Const COL_AX_ID As Integer = 1
Private Const COL_AX_NAME As Integer = 2
Private Const COL_AX_TYPE As Integer = 3
Private Const COL_AX_STAT_MODIFIER As Integer = 4
Private Const COL_AX_MIN_VALUE As Integer = 5
Private Const COL_AX_MAX_VALUE As Integer = 6
Private Const COL_AX_SPAWN_WEIGHT As Integer = 7
Private Const COL_AX_ITEM_LEVEL_MIN As Integer = 8
Private Const COL_AX_ITEM_LEVEL_MAX As Integer = 9
Private Const COL_AX_ALLOWED_TAGS As Integer = 10

' Column indices for UniqueItems
Private Const COL_UQ_ID As Integer = 1
Private Const COL_UQ_NAME As Integer = 2
Private Const COL_UQ_BASE_ID As Integer = 3
Private Const COL_UQ_FIXED_STATS As Integer = 4
Private Const COL_UQ_SPECIAL_ABILITY As Integer = 5
Private Const COL_UQ_LORE_TEXT As Integer = 6
Private Const COL_UQ_DROP_WEIGHT As Integer = 7
Private Const COL_UQ_MIN_LEVEL As Integer = 8

' Valid dropdown values
Private validSlots() As String
Private validItemTypes() As String
Private validAffixTypes() As String
Private validStatModifiers() As String
Private validWeaponCategories() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validSlots = Split("Weapon,Head,Chest,Hands,Legs,Feet,Ring,Amulet,Offhand", ",")
    validItemTypes = Split("Sword,Axe,Mace,Dagger,Staff,Wand,Bow,Crossbow,Shield," & _
                           "Helmet,Chest,Gloves,Boots,Leggings,Ring,Amulet,Potion,Scroll", ",")
    validAffixTypes = Split("prefix,suffix", ",")
    validStatModifiers = Split("melee_damage,ranged_damage,magic_damage,fire_damage," & _
                               "cold_damage,lightning_damage,poison_damage," & _
                               "strength,dexterity,intelligence,vitality,energy,luck," & _
                               "armor,magic_resistance,dodge_chance," & _
                               "attack_speed,critical_chance,critical_damage," & _
                               "life,mana,life_regen,mana_regen,movement_speed", ",")
    validWeaponCategories = Split("melee_1h,melee_2h,ranged,magic", ",")
End Sub

'===============================================================================
' ITEM BASES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateItemBases - Validates all rows in ItemBases sheet
'-------------------------------------------------------------------------------
Public Sub ValidateItemBases()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ITEM_BASES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ITEM_BASES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_IB_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow ' Skip header row
        Dim id As String
        id = Trim(ws.Cells(i, COL_IB_ID).value)

        ' Skip empty rows
        If Len(id) = 0 Then GoTo NextItemBase

        ' Validate ID format
        If Not ValidateId(id, "wep_") And Not ValidateId(id, "arm_") And _
           Not ValidateId(id, "acc_") And Not ValidateId(id, "con_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: wep_/arm_/acc_/con_ + type + name (e.g., wep_sword_iron)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_IB_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate slot dropdown
        Dim slot As String
        slot = Trim(ws.Cells(i, COL_IB_SLOT).value)
        If Len(slot) > 0 And Not ValidateDropdown(slot, validSlots) Then
            LogValidationError errors, errorCount, i, "Slot", _
                "Invalid slot. Valid: Weapon,Head,Chest,Hands,Legs,Feet,Ring,Amulet,Offhand"
        End If

        ' Validate numeric fields are non-negative
        If GetDefaultNumeric(ws.Cells(i, COL_IB_WEAPON_DAMAGE)) < 0 Then
            LogValidationError errors, errorCount, i, "Weapon Damage", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_IB_PHYSICAL_DAMAGE)) < 0 Then
            LogValidationError errors, errorCount, i, "Physical Damage", "Cannot be negative"
        End If

        If GetDefaultNumeric(ws.Cells(i, COL_IB_ATTACK_SPEED)) < 0 Then
            LogValidationError errors, errorCount, i, "Attack Speed", "Cannot be negative"
        End If

        ' Validate weapon_category for weapons
        If LCase(Trim(ws.Cells(i, COL_IB_SLOT).value)) = "weapon" Then
            Dim weaponCat As String
            weaponCat = LCase(Trim(ws.Cells(i, COL_IB_WEAPON_CATEGORY).value))
            If Len(weaponCat) > 0 And Not ValidateDropdown(weaponCat, validWeaponCategories) Then
                LogValidationError errors, errorCount, i, "Weapon Category", _
                    "Invalid weapon category. Valid: melee_1h, melee_2h, ranged, magic"
            End If
        End If

NextItemBase:
    Next i

    ShowValidationResults errors, errorCount, "ItemBases"
End Sub

'-------------------------------------------------------------------------------
' ExportItemBases - Exports ItemBases to JSON
'-------------------------------------------------------------------------------
Public Sub ExportItemBases()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_ITEM_BASES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_ITEM_BASES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""item_bases"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_IB_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_IB_ID).value)

        If Len(id) = 0 Then GoTo NextExportItem

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IB_NAME))) & """," & vbCrLf
        json = json & "      ""slot"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IB_SLOT))) & """," & vbCrLf
        json = json & "      ""item_type"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IB_TYPE))) & """," & vbCrLf
        json = json & "      ""weapon_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_WEAPON_DAMAGE))) & "," & vbCrLf
        json = json & "      ""physical_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_PHYSICAL_DAMAGE))) & "," & vbCrLf
        json = json & "      ""fire_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_FIRE_DAMAGE))) & "," & vbCrLf
        json = json & "      ""cold_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_COLD_DAMAGE))) & "," & vbCrLf
        json = json & "      ""lightning_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_LIGHTNING_DAMAGE))) & "," & vbCrLf
        json = json & "      ""poison_damage"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_POISON_DAMAGE))) & "," & vbCrLf
        json = json & "      ""attack_speed"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_ATTACK_SPEED), 1)) & "," & vbCrLf
        json = json & "      ""base_armor"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_BASE_ARMOR))) & "," & vbCrLf
        json = json & "      ""req_str"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_REQ_STR))) & "," & vbCrLf
        json = json & "      ""req_dex"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_REQ_DEX))) & "," & vbCrLf
        json = json & "      ""req_int"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_IB_REQ_INT))) & "," & vbCrLf
        json = json & "      ""allowed_affix_tags"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IB_ALLOWED_AFFIX_TAGS))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_IB_DESCRIPTION))) & """," & vbCrLf
        json = json & "      ""weapon_category"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_IB_WEAPON_CATEGORY)))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportItem:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "item_bases.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " item bases to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' AFFIXES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateAffixes - Validates all rows in Affixes sheet
'-------------------------------------------------------------------------------
Public Sub ValidateAffixes()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_AFFIXES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_AFFIXES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_AX_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_AX_ID).value)

        If Len(id) = 0 Then GoTo NextAffix

        ' Validate ID starts with pre_ or suf_
        If Left(id, 4) <> "pre_" And Left(id, 4) <> "suf_" Then
            LogValidationError errors, errorCount, i, "ID", _
                "Affix ID must start with 'pre_' (prefix) or 'suf_' (suffix)"
        End If

        ' Validate type matches ID prefix
        Dim affixType As String
        affixType = LCase(Trim(ws.Cells(i, COL_AX_TYPE).value))
        If (Left(id, 4) = "pre_" And affixType <> "prefix") Or _
           (Left(id, 4) = "suf_" And affixType <> "suffix") Then
            LogValidationError errors, errorCount, i, "Type", _
                "Type must match ID prefix (pre_ = prefix, suf_ = suffix)"
        End If

        ' Validate stat modifier
        Dim statMod As String
        statMod = LCase(Trim(ws.Cells(i, COL_AX_STAT_MODIFIER).value))
        If Len(statMod) > 0 And Not ValidateDropdown(statMod, validStatModifiers) Then
            LogValidationError errors, errorCount, i, "Stat Modifier", _
                "Invalid stat modifier. Check StatModifiers reference list."
        End If

        ' Validate min <= max
        Dim minVal As Double, maxVal As Double
        minVal = GetDefaultNumeric(ws.Cells(i, COL_AX_MIN_VALUE))
        maxVal = GetDefaultNumeric(ws.Cells(i, COL_AX_MAX_VALUE))
        If minVal > maxVal Then
            LogValidationError errors, errorCount, i, "Min/Max Value", _
                "Min value cannot be greater than max value"
        End If

NextAffix:
    Next i

    ShowValidationResults errors, errorCount, "Affixes"
End Sub

'-------------------------------------------------------------------------------
' ExportAffixes - Exports Affixes to JSON
'-------------------------------------------------------------------------------
Public Sub ExportAffixes()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_AFFIXES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_AFFIXES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""affixes"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_AX_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_AX_ID).value)

        If Len(id) = 0 Then GoTo NextExportAffix

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_AX_NAME))) & """," & vbCrLf
        json = json & "      ""type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_AX_TYPE)))) & """," & vbCrLf
        json = json & "      ""stat_modifier"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_AX_STAT_MODIFIER)))) & """," & vbCrLf
        json = json & "      ""min_value"": " & GetDefaultNumeric(ws.Cells(i, COL_AX_MIN_VALUE)) & "," & vbCrLf
        json = json & "      ""max_value"": " & GetDefaultNumeric(ws.Cells(i, COL_AX_MAX_VALUE)) & "," & vbCrLf
        json = json & "      ""spawn_weight"": " & GetDefaultNumeric(ws.Cells(i, COL_AX_SPAWN_WEIGHT), 100) & "," & vbCrLf
        json = json & "      ""item_level_min"": " & GetDefaultNumeric(ws.Cells(i, COL_AX_ITEM_LEVEL_MIN), 1) & "," & vbCrLf
        json = json & "      ""item_level_max"": " & GetDefaultNumeric(ws.Cells(i, COL_AX_ITEM_LEVEL_MAX), 100) & "," & vbCrLf
        json = json & "      ""allowed_tags"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_AX_ALLOWED_TAGS))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportAffix:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "affixes.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " affixes to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' UNIQUE ITEMS
'===============================================================================

'-------------------------------------------------------------------------------
' ExportUniqueItems - Exports UniqueItems to JSON
'-------------------------------------------------------------------------------
Public Sub ExportUniqueItems()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_UNIQUES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_UNIQUES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""unique_items"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_UQ_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_UQ_ID).value)

        If Len(id) = 0 Then GoTo NextExportUnique

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_UQ_NAME))) & """," & vbCrLf
        json = json & "      ""base_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_UQ_BASE_ID))) & """," & vbCrLf
        json = json & "      ""fixed_stats"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_UQ_FIXED_STATS))) & """," & vbCrLf
        json = json & "      ""special_ability"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_UQ_SPECIAL_ABILITY))) & """," & vbCrLf
        json = json & "      ""lore_text"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_UQ_LORE_TEXT))) & """," & vbCrLf
        json = json & "      ""drop_weight"": " & GetDefaultNumeric(ws.Cells(i, COL_UQ_DROP_WEIGHT), 10) & "," & vbCrLf
        json = json & "      ""min_level"": " & GetDefaultNumeric(ws.Cells(i, COL_UQ_MIN_LEVEL), 1) & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportUnique:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "unique_items.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " unique items to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'===============================================================================
' MASTER EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportAllItems - Exports all item-related sheets
'-------------------------------------------------------------------------------
Public Sub ExportAllItems()
    ExportItemBases
    ExportAffixes
    ExportUniqueItems
    MsgBox "All item databases exported!", vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ValidateAllItems - Validates all item-related sheets
'-------------------------------------------------------------------------------
Public Sub ValidateAllItems()
    ValidateItemBases
    ValidateAffixes
End Sub
