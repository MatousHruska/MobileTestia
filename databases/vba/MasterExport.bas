Attribute VB_Name = "MasterExport"
'===============================================================================
' MasterExport Module
' Master export and validation functions for all databases
' Enemy AI uses module_ids system (see EnemyModuleDatabase)
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
    ExportEnemyVariants
    ExportEnemyModules

    ' Abilities (Combat System)
    ExportAbilities
    ExportEnemyAbilities

    ' Loot
    ExportLootTables

    ' Talents & Talent Trees
    ExportTalentTrees
    ExportTalents

    ' Quests
    ExportQuests
    ExportQuestObjectives

    ' NPCs & Trading
    ExportNPCs
    ExportShopInventory
    ExportDialogues

    ' Gameplay
    ExportConsumables
    ExportStatusEffects
    ExportGameplaySettings
    ExportZones
    ExportLocations
    ExportInteriorRegionsData

    ' Interactables
    ExportChests
    ExportDoorsData
    ExportLeversData
    ExportPressurePlatesData
    ExportLootablesData
    ExportSignsData
    ExportLoreEchoesData
    ExportTriggerAreasData

    ' Spawn Points
    ExportSpawnPoints

    ' Cutscenes
    ExportCutscenes

    ' Floating Dialogues
    ExportFloatingDialogues

    ' Popup Messages
    ExportPopupMessages

    ' Stat Descriptions
    ExportStatDescriptions

    ' UI Theme
    ExportUITheme

    ' Achievements
    ExportAchievements

    ' Combat Text
    ExportCombatText

    ' Map System (Chunks & Terrain)
    ExportChunksData
    ExportTerrainTypesData

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
    ValidateEnemyModules
    ValidateAbilities
    ValidateEnemyAbilities
    ValidateLootTables
    ValidateTalentTrees
    ValidateTalents
    ValidateQuests
    ValidateNPCs
    ValidateShopInventory
    ValidateConsumables
    ValidateStatusEffects
    ValidateZones
    ValidateLocations
    ValidateInteriorRegions
    ValidateChests
    ValidateDoorsData
    ValidateLeversData
    ValidatePressurePlatesData
    ValidateLootablesData
    ValidateSignsData
    ValidateLoreEchoesData
    ValidateTriggerAreasData
    ValidateSpawnPoints
    ValidateCutscenes
    ValidateFloatingDialogues
    ValidatePopupMessages
    ValidateUITheme
    ValidateAchievements
    ValidateCombatText
    ValidateChunks
    ValidateTerrainTypes
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

    On Error GoTo SheetError
    Dim currentSheet As String

    ' Create/setup each sheet
    currentSheet = "ItemBases": SetupItemBasesSheet
    currentSheet = "Affixes": SetupAffixesSheet
    currentSheet = "UniqueItems": SetupUniqueItemsSheet
    currentSheet = "Enemies": SetupEnemiesSheet
    currentSheet = "EnemyVariants": SetupEnemyVariantsSheet
    currentSheet = "EnemyModules": SetupEnemyModulesSheet
    currentSheet = "Abilities": SetupAbilitiesSheet
    currentSheet = "EnemyAbilities": SetupEnemyAbilitiesSheet
    currentSheet = "LootTables": SetupLootTablesSheet
    currentSheet = "TalentTrees": SetupTalentTreesSheet
    currentSheet = "Talents": SetupTalentsSheet
    currentSheet = "Quests": SetupQuestsSheet
    currentSheet = "QuestObjectives": SetupQuestObjectivesSheet
    currentSheet = "NPCs": SetupNPCsSheet
    currentSheet = "ShopInventory": SetupShopInventorySheet
    currentSheet = "Dialogues": SetupDialoguesSheet
    currentSheet = "Consumables": SetupConsumablesSheet
    currentSheet = "StatusEffects": SetupStatusEffectsSheet
    currentSheet = "GameplaySettings": SetupGameplaySettingsSheet
    currentSheet = "Zones": SetupZonesSheet
    currentSheet = "Locations": SetupLocationsSheet
    currentSheet = "InteriorRegions": SetupInteriorRegionsSheet
    currentSheet = "Chests": SetupChestsSheet
    currentSheet = "Doors": SetupDoorsSheet
    currentSheet = "Levers": SetupLeversSheet
    currentSheet = "PressurePlates": SetupPressurePlatesSheet
    currentSheet = "Lootables": SetupLootablesSheet
    currentSheet = "Signs": SetupSignsSheet
    currentSheet = "LoreEchoes": SetupLoreEchoesSheet
    currentSheet = "TriggerAreas": SetupTriggerAreasSheet
    currentSheet = "SpawnPoints": SetupSpawnPointsSheet
    currentSheet = "Cutscenes": SetupCutscenesSheet
    currentSheet = "FloatingDialogues": SetupFloatingDialoguesSheet
    currentSheet = "PopupMessages": SetupPopupMessagesSheet
    currentSheet = "StatDescriptions": SetupStatDescriptionsSheet
    currentSheet = "StatModifiers": SetupStatModifiersSheet
    currentSheet = "Rarities": SetupRaritiesSheet
    currentSheet = "UITheme": SetupUIThemeSheet
    currentSheet = "Achievements": SetupAchievementsSheet
    currentSheet = "CombatTextSettings": SetupCombatTextSettingsSheet
    currentSheet = "CombatTextCategories": SetupCombatTextCategoriesSheet
    currentSheet = "Chunks": SetupChunksSheet
    currentSheet = "TerrainTypes": SetupTerrainTypesSheet

    MsgBox "Workbook setup complete!" & vbCrLf & vbCrLf & _
           "All sheets have been created with proper headers." & vbCrLf & _
           "Don't forget to add Data Validation (dropdowns) to relevant columns!", _
           vbInformation, "Setup Complete"
    Exit Sub

SheetError:
    MsgBox "Error setting up sheet: " & currentSheet & vbCrLf & vbCrLf & _
           "Error " & Err.Number & ": " & Err.Description, vbCritical, "Setup Error"
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
    Else
        ' Make sure existing sheet is visible
        ws.Visible = xlSheetVisible
    End If

    Set GetOrCreateSheet = ws
End Function

'-------------------------------------------------------------------------------
' Helper: Set headers for a sheet (0-based array)
'-------------------------------------------------------------------------------
Private Sub SetHeaders(ByVal ws As Worksheet, ByRef headers As Variant)
    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter
End Sub

'-------------------------------------------------------------------------------
' Helper: Safely add comment (delete existing first)
'-------------------------------------------------------------------------------
Private Sub SafeAddComment(ByVal cell As Range, ByVal commentText As String)
    On Error Resume Next
    cell.ClearComments
    cell.AddComment commentText
    On Error GoTo 0
End Sub

'-------------------------------------------------------------------------------
' Setup individual sheets
'-------------------------------------------------------------------------------
Private Sub SetupItemBasesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("ItemBases")
    Dim headers As Variant
    headers = Array("id", "name", "slot", "item_type", "weapon_damage", "physical_damage", _
                    "fire_damage", "cold_damage", "lightning_damage", "poison_damage", _
                    "attack_speed", "base_armor", "req_str", "req_dex", "req_int", _
                    "allowed_affix_tags", "description", "weapon_category")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 5), "Total weapon damage (sum of all damage types)"
    SafeAddComment ws.Cells(1, 6), "Physical portion of weapon damage"
    SafeAddComment ws.Cells(1, 7), "Fire elemental damage"
    SafeAddComment ws.Cells(1, 8), "Cold elemental damage"
    SafeAddComment ws.Cells(1, 9), "Lightning elemental damage"
    SafeAddComment ws.Cells(1, 10), "Poison elemental damage"
    SafeAddComment ws.Cells(1, 11), "Attacks per second (1.0 = normal)"
    SafeAddComment ws.Cells(1, 18), "Weapon category: melee_1h, melee_2h, ranged, magic"
End Sub

Private Sub SetupAffixesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Affixes")
    Dim headers As Variant
    headers = Array("id", "name", "type", "stat_modifier", "min_value", "max_value", _
                    "spawn_weight", "item_level_min", "item_level_max", "allowed_tags")
    SetHeaders ws, headers
End Sub

Private Sub SetupUniqueItemsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("UniqueItems")
    Dim headers As Variant
    headers = Array("id", "name", "base_id", "fixed_stats", "special_ability", _
                    "lore_text", "drop_weight", "min_level")
    SetHeaders ws, headers
End Sub

Private Sub SetupEnemiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Enemies")
    Dim headers As Variant
    headers = Array("id", "name", "type", "base_health", "base_damage", "armor", "base_shield", _
                    "move_speed", "attack_speed", "detection_range", _
                    "xp_reward", "loot_table_id", "module_ids", "module_config", "navigation_layer", "description")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 7), "Shield absorbs damage before health (0 = no shield)"
    SafeAddComment ws.Cells(1, 13), "Comma-separated module IDs for AI (e.g., mod_target_detection,mod_chase,mod_combat)"
    SafeAddComment ws.Cells(1, 14), "Per-enemy module config overrides as JSON. Format: {""mod_idle"": {""can_roam"": false}}"
    SafeAddComment ws.Cells(1, 15), "Navigation layer: ground, flying, jumping, ghost. Determines terrain traversal."
End Sub

Private Sub SetupEnemyVariantsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyVariants")
    Dim headers As Variant
    headers = Array("id", "name", "health_multiplier", "damage_multiplier", _
                    "xp_multiplier", "extra_abilities", "visual_effect")
    SetHeaders ws, headers
End Sub

Private Sub SetupEnemyModulesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyModules")
    Dim headers As Variant
    headers = Array("id", "name", "module_type", "description", "script_path", "priority", "default_config")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Module ID: mod_name (e.g., mod_target_detection)"
    SafeAddComment ws.Cells(1, 3), "detection, movement, combat, social, special, utility"
    SafeAddComment ws.Cells(1, 5), "GDScript path (auto-generated if empty)"
    SafeAddComment ws.Cells(1, 6), "Higher priority = runs first (100=detection, 80=movement, 60=combat)"
    SafeAddComment ws.Cells(1, 7), "JSON config object, e.g., {""detection_radius"": 150}"
End Sub

Private Sub SetupLootTablesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("LootTables")
    Dim headers As Variant
    headers = Array("id", "name", "min_drops", "max_drops", "nothing_weight", _
                    "common_weight", "magic_weight", "rare_weight", "unique_weight", _
                    "gold_min", "gold_max", "item_pool", "guaranteed_drops")
    SetHeaders ws, headers
End Sub

Private Sub SetupQuestsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Quests")
    Dim headers As Variant
    ' Updated structure with embedded objectives support
    headers = Array("id", "name", "description", "type", "min_level", "giver_npc", _
                    "turn_in_npc", "prerequisite_quests", "next_quest", "can_abandon", _
                    "auto_complete", "xp_reward", "gold_reward", "item_rewards", _
                    "start_dialogue", "complete_dialogue")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 4), "story or side"
    SafeAddComment ws.Cells(1, 10), "TRUE/FALSE - story quests should be FALSE"
    SafeAddComment ws.Cells(1, 11), "TRUE/FALSE - auto complete when objectives done"
    SafeAddComment ws.Cells(1, 14), "Comma-separated item IDs"
End Sub

Private Sub SetupQuestObjectivesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("QuestObjectives")
    Dim headers As Variant
    ' Objectives linked to quests by quest_id
    headers = Array("quest_id", "objective_id", "type", "target", "count", "description", "optional")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Links to quest id in Quests sheet"
    SafeAddComment ws.Cells(1, 3), "kill_named, kill_count, gather, delivery, interact, talk, escort, defend, use_ability, defeat_no_kill, reach_location, race"
    SafeAddComment ws.Cells(1, 4), "enemy_id, item_id, npc_id, zone_id, etc."
    SafeAddComment ws.Cells(1, 7), "TRUE/FALSE"
End Sub

Private Sub SetupStatModifiersSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("StatModifiers")
    Dim headers As Variant
    headers = Array("id", "display_name", "category", "description")
    SetHeaders ws, headers

    ' Pre-populate with valid stat modifiers
    ' Categories: offensive, defensive, primary, utility, skill
    Dim stats As Variant
    stats = Array( _
        "attack_power", "spell_power", "fire_power", "cold_power", _
        "lightning_power", "poison_power", _
        "strength", "dexterity", "intelligence", "vitality", "energy", "luck", _
        "armor", "magic_resistance", "dodge_chance", _
        "attack_speed", "critical_chance", "critical_damage", _
        "life", "mana", "life_regen", "mana_regen", "movement_speed", _
        "hit_range", "hit_arc", "lunge_force", "lunge_duration", _
        "explosion_radius", "projectile_speed", "cast_speed", "cooldown_reduction")

    Dim row As Integer
    row = 2
    Dim i As Integer
    For i = 0 To UBound(stats)
        ws.Cells(row, 1).value = stats(i)
        row = row + 1
    Next i
End Sub

Private Sub SetupRaritiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Rarities")
    Dim headers As Variant
    headers = Array("id", "name", "color_hex", "affix_count", "drop_weight")
    SetHeaders ws, headers

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

Private Sub SetupNPCsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("NPCs")
    Dim headers As Variant
    headers = Array("id", "name", "type", "location", "shop_inventory_id", _
                    "dialogue_greeting", "faction", "sprite_id", "min_level", "is_interactable", _
                    "portrait_id", "dialogue_talk_id", "spawn_condition")
    SetHeaders ws, headers

    ' Add comment for spawn_condition format
    SafeAddComment ws.Cells(1, 13), "Condition for NPC to spawn. Format: type:value. Examples: quest_active:qst_main, quest_completed:qst_tutorial, flag_set:met_king. Leave empty for always spawn."
End Sub

Private Sub SetupShopInventorySheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("ShopInventory")
    Dim headers As Variant
    headers = Array("id", "name", "item_id", "item_type", "stock", "restock_hours", _
                    "price_multiplier", "currency_type", "min_player_level", "max_player_level")
    SetHeaders ws, headers
End Sub

Private Sub SetupConsumablesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Consumables")
    Dim headers As Variant
    headers = Array("id", "name", "consumable_type", "effect_type", "effect_value", _
                    "duration", "cooldown", "stack_size", "price_base", "description")
    SetHeaders ws, headers
End Sub

Private Sub SetupStatusEffectsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("StatusEffects")
    Dim headers As Variant
    headers = Array("id", "name", "type", "stat_affected", "value", "duration", _
                    "tick_interval", "visual_effect", "stackable", "max_stacks", "show_in_hud", _
                    "icon_color", "ends_when", "description")
    SetHeaders ws, headers

    ' Add comments
    SafeAddComment ws.Cells(1, 12), "Hex color for HUD icon (e.g., #FF5500 for orange)"
    SafeAddComment ws.Cells(1, 13), "Condition that removes the effect (e.g., player_full_health, player_below_50)"
End Sub

Private Sub SetupGameplaySettingsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("GameplaySettings")
    Dim headers As Variant
    headers = Array("key", "value", "description")
    SetHeaders ws, headers

    ' Add comments
    SafeAddComment ws.Cells(1, 1), "Setting key name (e.g., armor_constant)"
    SafeAddComment ws.Cells(1, 2), "Numeric value for the setting"
    SafeAddComment ws.Cells(1, 3), "Description of what this setting controls"
End Sub

Private Sub SetupZonesSheet()
    ' NOTE: enemy_spawn_list, loot_table_id, respawn_time removed - use SpawnPoints database
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Zones")
    Dim headers As Variant
    headers = Array("id", "name", "zone_type", "min_level", "max_level", _
                    "music_track", "ambient_sound", "is_safe_zone", "is_pvp_enabled", _
                    "status_effect_id", "discovery_popup", "description")
    SetHeaders ws, headers

    ' Add comments
    SafeAddComment ws.Cells(1, 6), "Music track to play in this zone"
    SafeAddComment ws.Cells(1, 7), "Background ambient sound file"
    SafeAddComment ws.Cells(1, 8), "true/false - No combat allowed in this zone"
    SafeAddComment ws.Cells(1, 9), "true/false - PvP enabled in this zone"
    SafeAddComment ws.Cells(1, 10), "Status effect applied while in zone (e.g., status_cold)"
    SafeAddComment ws.Cells(1, 11), "true/false - Show discovery popup on first visit"
End Sub

Private Sub SetupDialoguesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Dialogues")
    Dim headers As Variant
    headers = Array("id", "frames")
    SetHeaders ws, headers
End Sub

Private Sub SetupChestsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Chests")
    Dim headers As Variant
    headers = Array("id", "name", "chest_type", "zone_id", "spawn_chance", _
                    "wooden_weight", "iron_weight", "golden_weight", _
                    "loot_table_id", "min_items", "max_items", "guaranteed_gold", _
                    "fixed_gold", "fixed_items", "can_respawn", "respawn_time", _
                    "quest_id", "required_quest_state", "description")
    SetHeaders ws, headers
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

'-------------------------------------------------------------------------------
' SetupEnemySheetsOnly - Creates just the Enemies, EnemyVariants sheets
' Use this if SetupWorkbook fails to create enemy sheets
'-------------------------------------------------------------------------------
Public Sub SetupEnemySheetsOnly()
    On Error GoTo EnemyError

    SetupEnemiesSheet
    SetupEnemyVariantsSheet
    SetupEnemyModulesSheet

    MsgBox "Enemy sheets created successfully!" & vbCrLf & vbCrLf & _
           "Sheets created: Enemies, EnemyVariants, EnemyModules", _
           vbInformation, "Setup Complete"
    Exit Sub

EnemyError:
    MsgBox "Error creating enemy sheets:" & vbCrLf & vbCrLf & _
           "Error " & Err.Number & ": " & Err.Description, vbCritical, "Setup Error"
End Sub

'-------------------------------------------------------------------------------
' DiagnosticCheck - Lists all modules and checks for duplicates
'-------------------------------------------------------------------------------
Public Sub DiagnosticCheck()
    Dim msg As String
    msg = "VBA Modules in this workbook:" & vbCrLf & vbCrLf

    Dim vbComp As Object
    For Each vbComp In ThisWorkbook.VBProject.VBComponents
        msg = msg & "- " & vbComp.Name & " (" & vbComp.Type & ")" & vbCrLf
    Next vbComp

    msg = msg & vbCrLf & "If you see duplicate modules (like MasterExport1), " & vbCrLf
    msg = msg & "delete the duplicates and reimport the .bas files."

    MsgBox msg, vbInformation, "Diagnostic Check"
End Sub
