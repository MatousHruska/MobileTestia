Attribute VB_Name = "MasterExport"
'===============================================================================
' MasterExport Module
' Master export and validation functions for all databases
'===============================================================================
Option Explicit

'-------------------------------------------------------------------------------
' ExportAll - Exports all database tables to JSON
'-------------------------------------------------------------------------------
Public Sub ExportAll()
    Dim startTime As Double
    startTime = Timer

    ' Items
    On Error Resume Next
    ExportItemBases
    ExportAffixes
    ExportUniqueItems

    ' Enemies
    ExportEnemies
    ExportEnemyAbilities
    ExportEnemyVariants

    ' Loot
    ExportLootTables

    ' Skills
    ExportSkills

    ' Quests
    ExportQuests
    ExportQuestObjectives

    On Error GoTo 0

    Dim elapsed As Double
    elapsed = Timer - startTime

    MsgBox "All databases exported successfully!" & vbCrLf & vbCrLf & _
           "Time: " & Format(elapsed, "0.00") & " seconds" & vbCrLf & _
           "Output: " & GetExportPath(), vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ValidateAll - Validates all database tables
'-------------------------------------------------------------------------------
Public Sub ValidateAll()
    Dim startTime As Double
    startTime = Timer

    On Error Resume Next
    ValidateItemBases
    ValidateAffixes
    ValidateEnemies
    ValidateLootTables
    ValidateSkills
    ValidateQuests
    On Error GoTo 0

    Dim elapsed As Double
    elapsed = Timer - startTime

    MsgBox "All validations complete!" & vbCrLf & vbCrLf & _
           "Time: " & Format(elapsed, "0.00") & " seconds", vbInformation, "Validation Complete"
End Sub

'-------------------------------------------------------------------------------
' SetupWorkbook - Creates all required sheets with headers
'-------------------------------------------------------------------------------
Public Sub SetupWorkbook()
    Dim response As VbMsgBoxResult
    response = MsgBox("This will create/reset all database sheets with proper headers." & vbCrLf & _
                      "Existing data will NOT be deleted, but headers may be updated." & vbCrLf & vbCrLf & _
                      "Continue?", vbYesNo + vbQuestion, "Setup Workbook")

    If response <> vbYes Then Exit Sub

    ' Create/setup each sheet
    SetupItemBasesSheet
    SetupAffixesSheet
    SetupUniqueItemsSheet
    SetupEnemiesSheet
    SetupEnemyAbilitiesSheet
    SetupEnemyVariantsSheet
    SetupLootTablesSheet
    SetupSkillsSheet
    SetupQuestsSheet
    SetupQuestObjectivesSheet
    SetupStatModifiersSheet
    SetupRaritiesSheet

    MsgBox "Workbook setup complete!" & vbCrLf & vbCrLf & _
           "All sheets have been created with proper headers." & vbCrLf & _
           "Don't forget to add Data Validation (dropdowns) to relevant columns!", _
           vbInformation, "Setup Complete"
End Sub

'-------------------------------------------------------------------------------
' Helper: Create or get sheet
'-------------------------------------------------------------------------------
Private Function GetOrCreateSheet(ByVal sheetName As String) As Worksheet
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(sheetName)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = sheetName
    End If

    Set GetOrCreateSheet = ws
End Function

'-------------------------------------------------------------------------------
' Helper: Set headers for a sheet
'-------------------------------------------------------------------------------
Private Sub SetHeaders(ByVal ws As Worksheet, ByRef headers() As String)
    Dim col As Integer
    For col = LBound(headers) To UBound(headers)
        ws.Cells(1, col).value = headers(col)
        ws.Cells(1, col).Font.Bold = True
        ws.Cells(1, col).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter
End Sub

'-------------------------------------------------------------------------------
' Setup individual sheets
'-------------------------------------------------------------------------------
Private Sub SetupItemBasesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("ItemBases")
    Dim headers() As String
    headers = Split("id,name,slot,item_type,base_damage,attack_speed,base_armor,req_str,req_dex,req_int,allowed_affix_tags,description", ",")
    ReDim Preserve headers(1 To 12)
    Dim i As Integer
    For i = 1 To 12
        headers(i) = Split("id,name,slot,item_type,base_damage,attack_speed,base_armor,req_str,req_dex,req_int,allowed_affix_tags,description", ",")(i - 1)
    Next i
    SetHeaders ws, headers
End Sub

Private Sub SetupAffixesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Affixes")
    Dim h(1 To 10) As String
    h(1) = "id": h(2) = "name": h(3) = "type": h(4) = "stat_modifier"
    h(5) = "min_value": h(6) = "max_value": h(7) = "spawn_weight"
    h(8) = "item_level_min": h(9) = "item_level_max": h(10) = "allowed_tags"
    SetHeaders ws, h
End Sub

Private Sub SetupUniqueItemsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("UniqueItems")
    Dim h(1 To 8) As String
    h(1) = "id": h(2) = "name": h(3) = "base_id": h(4) = "fixed_stats"
    h(5) = "special_ability": h(6) = "lore_text": h(7) = "drop_weight": h(8) = "min_level"
    SetHeaders ws, h
End Sub

Private Sub SetupEnemiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Enemies")
    Dim h(1 To 14) As String
    h(1) = "id": h(2) = "name": h(3) = "type": h(4) = "base_health"
    h(5) = "base_damage": h(6) = "armor": h(7) = "move_speed": h(8) = "attack_speed"
    h(9) = "attack_range": h(10) = "detection_range": h(11) = "xp_reward"
    h(12) = "loot_table_id": h(13) = "ability_ids": h(14) = "description"
    SetHeaders ws, h
End Sub

Private Sub SetupEnemyAbilitiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyAbilities")
    Dim h(1 To 8) As String
    h(1) = "id": h(2) = "name": h(3) = "type": h(4) = "damage"
    h(5) = "damage_type": h(6) = "cooldown": h(7) = "range": h(8) = "description"
    SetHeaders ws, h
End Sub

Private Sub SetupEnemyVariantsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyVariants")
    Dim h(1 To 7) As String
    h(1) = "id": h(2) = "name": h(3) = "health_multiplier": h(4) = "damage_multiplier"
    h(5) = "xp_multiplier": h(6) = "extra_abilities": h(7) = "visual_effect"
    SetHeaders ws, h
End Sub

Private Sub SetupLootTablesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("LootTables")
    Dim h(1 To 13) As String
    h(1) = "id": h(2) = "name": h(3) = "min_drops": h(4) = "max_drops"
    h(5) = "nothing_weight": h(6) = "common_weight": h(7) = "magic_weight"
    h(8) = "rare_weight": h(9) = "unique_weight": h(10) = "gold_min"
    h(11) = "gold_max": h(12) = "item_pool": h(13) = "guaranteed_drops"
    SetHeaders ws, h
End Sub

Private Sub SetupSkillsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Skills")
    Dim h(1 To 18) As String
    h(1) = "id": h(2) = "name": h(3) = "type": h(4) = "tree": h(5) = "tier"
    h(6) = "max_level": h(7) = "mana_cost": h(8) = "stamina_cost": h(9) = "cooldown"
    h(10) = "base_damage": h(11) = "damage_per_level": h(12) = "effect_type"
    h(13) = "effect_value": h(14) = "effect_per_level": h(15) = "duration"
    h(16) = "prerequisite_ids": h(17) = "description": h(18) = "icon_name"
    SetHeaders ws, h
End Sub

Private Sub SetupQuestsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Quests")
    Dim h(1 To 13) As String
    h(1) = "id": h(2) = "name": h(3) = "type": h(4) = "giver_npc": h(5) = "min_level"
    h(6) = "prerequisite_quests": h(7) = "objective_ids": h(8) = "xp_reward"
    h(9) = "gold_reward": h(10) = "item_rewards": h(11) = "loot_table_reward"
    h(12) = "description": h(13) = "completion_text"
    SetHeaders ws, h
End Sub

Private Sub SetupQuestObjectivesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("QuestObjectives")
    Dim h(1 To 6) As String
    h(1) = "id": h(2) = "type": h(3) = "target_id": h(4) = "count"
    h(5) = "description": h(6) = "optional"
    SetHeaders ws, h
End Sub

Private Sub SetupStatModifiersSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("StatModifiers")
    Dim h(1 To 4) As String
    h(1) = "id": h(2) = "display_name": h(3) = "category": h(4) = "description"
    SetHeaders ws, h

    ' Pre-populate with valid stat modifiers
    Dim stats As Variant
    stats = Array("melee_damage", "ranged_damage", "magic_damage", "fire_damage", _
                  "cold_damage", "lightning_damage", "poison_damage", _
                  "strength", "dexterity", "intelligence", "vitality", "energy", "luck", _
                  "armor", "magic_resistance", "dodge_chance", _
                  "attack_speed", "critical_chance", "critical_damage", _
                  "life", "mana", "life_regen", "mana_regen", "movement_speed")

    Dim row As Integer
    row = 2
    Dim stat As Variant
    For Each stat In stats
        ws.Cells(row, 1).value = stat
        row = row + 1
    Next stat
End Sub

Private Sub SetupRaritiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Rarities")
    Dim h(1 To 5) As String
    h(1) = "id": h(2) = "name": h(3) = "color_hex": h(4) = "affix_count": h(5) = "drop_weight"
    SetHeaders ws, h

    ' Pre-populate with standard rarities
    ws.Cells(2, 1).value = "common": ws.Cells(2, 2).value = "Common"
    ws.Cells(2, 3).value = "#FFFFFF": ws.Cells(2, 4).value = 0: ws.Cells(2, 5).value = 100

    ws.Cells(3, 1).value = "magic": ws.Cells(3, 2).value = "Magic"
    ws.Cells(3, 3).value = "#4169E1": ws.Cells(3, 4).value = 2: ws.Cells(3, 5).value = 30

    ws.Cells(4, 1).value = "rare": ws.Cells(4, 2).value = "Rare"
    ws.Cells(4, 3).value = "#FFD700": ws.Cells(4, 4).value = 4: ws.Cells(4, 5).value = 10

    ws.Cells(5, 1).value = "unique": ws.Cells(5, 2).value = "Unique"
    ws.Cells(5, 3).value = "#8B4513": ws.Cells(5, 4).value = -1: ws.Cells(5, 5).value = 1
End Sub

'-------------------------------------------------------------------------------
' AddDebugItems - Adds standard debug/test items to ItemBases
'-------------------------------------------------------------------------------
Public Sub AddDebugItems()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets("ItemBases")
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "ItemBases sheet not found! Run SetupWorkbook first.", vbExclamation
        Exit Sub
    End If

    ' Find first empty row
    Dim row As Long
    row = ws.Cells(ws.Rows.Count, 1).End(xlUp).row + 1

    ' Debug God Weapon
    ws.Cells(row, 1).value = "debug_god_sword"
    ws.Cells(row, 2).value = "[DEBUG] Sword of Testing"
    ws.Cells(row, 3).value = "Weapon"
    ws.Cells(row, 4).value = "Sword"
    ws.Cells(row, 5).value = 99999  ' Damage
    ws.Cells(row, 6).value = 5      ' Attack Speed
    row = row + 1

    ' Debug God Armor
    ws.Cells(row, 1).value = "debug_god_armor"
    ws.Cells(row, 2).value = "[DEBUG] Armor of Immortality"
    ws.Cells(row, 3).value = "Chest"
    ws.Cells(row, 4).value = "Chest"
    ws.Cells(row, 7).value = 99999  ' Armor
    row = row + 1

    ' Debug Weak Weapon (for testing death)
    ws.Cells(row, 1).value = "debug_weak_sword"
    ws.Cells(row, 2).value = "[DEBUG] Wet Noodle"
    ws.Cells(row, 3).value = "Weapon"
    ws.Cells(row, 4).value = "Sword"
    ws.Cells(row, 5).value = 1
    ws.Cells(row, 6).value = 0.5

    MsgBox "Debug items added to ItemBases!", vbInformation
End Sub
