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
    ExportBehaviorProfiles

    ' Loot
    ExportLootTables

    ' Skills
    ExportSkills

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
    ExportZones

    ' Interactables
    ExportChests

    ' Spawn Points
    ExportSpawnPoints

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
    ValidateBehaviorProfiles
    ValidateLootTables
    ValidateSkills
    ValidateQuests
    ValidateNPCs
    ValidateShopInventory
    ValidateConsumables
    ValidateStatusEffects
    ValidateZones
    ValidateChests
    ValidateSpawnPoints
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
    SetupBehaviorProfilesSheet
    SetupLootTablesSheet
    SetupSkillsSheet
    SetupQuestsSheet
    SetupQuestObjectivesSheet
    SetupNPCsSheet
    SetupShopInventorySheet
    SetupDialoguesSheet
    SetupConsumablesSheet
    SetupStatusEffectsSheet
    SetupZonesSheet
    SetupChestsSheet
    SetupSpawnPointsSheet
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
    headers = Array("id", "name", "slot", "item_type", "base_damage", "attack_speed", _
                    "base_armor", "req_str", "req_dex", "req_int", "allowed_affix_tags", "description")
    SetHeaders ws, headers
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
    headers = Array("id", "name", "type", "base_health", "base_damage", "armor", _
                    "move_speed", "attack_speed", "attack_range", "detection_range", _
                    "xp_reward", "loot_table_id", "ability_ids", "behavior_profile", "description")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 13), "Comma-separated ability IDs from EnemyAbilities"
    SafeAddComment ws.Cells(1, 14), "Links to BehaviorProfiles id (e.g., bhv_basic_melee)"
End Sub

Private Sub SetupEnemyAbilitiesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyAbilities")
    Dim headers As Variant
    ' 21 columns for the expanded AI ability system
    headers = Array("id", "name", "description", "type", "damage_mult", "damage_type", _
                    "cooldown", "range_min", "range_max", "shape", "shape_size", "shape_angle", _
                    "windup", "recovery", "animation", "priority", "conditions", "effects_on_hit", _
                    "projectile_speed", "dash_speed", "cardinal_only")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 4), "melee, dash_attack, aoe, projectile, pattern, teleport_attack, beam"
    SafeAddComment ws.Cells(1, 5), "Multiplier applied to enemy base_damage"
    SafeAddComment ws.Cells(1, 6), "physical, fire, cold, lightning, poison, chaos, pure"
    SafeAddComment ws.Cells(1, 8), "Minimum range to use ability"
    SafeAddComment ws.Cells(1, 9), "Maximum range to use ability"
    SafeAddComment ws.Cells(1, 10), "circle, cone, line, cross, ring"
    SafeAddComment ws.Cells(1, 11), "Size/radius of hitbox shape"
    SafeAddComment ws.Cells(1, 12), "Angle for cones/beams (degrees)"
    SafeAddComment ws.Cells(1, 13), "Wind-up time before damage (seconds)"
    SafeAddComment ws.Cells(1, 14), "Recovery time after attack (seconds)"
    SafeAddComment ws.Cells(1, 16), "AI priority (higher = preferred)"
    SafeAddComment ws.Cells(1, 17), "Conditions: distance>50, health<50%, etc."
    SafeAddComment ws.Cells(1, 18), "Effects: stun:0.5, burn:3:5, knockback:100"
    SafeAddComment ws.Cells(1, 19), "For projectile abilities (pixels/sec)"
    SafeAddComment ws.Cells(1, 20), "For dash abilities (pixels/sec)"
    SafeAddComment ws.Cells(1, 21), "TRUE/FALSE - snap attack to 4 cardinal directions (default TRUE)"
End Sub

Private Sub SetupEnemyVariantsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("EnemyVariants")
    Dim headers As Variant
    headers = Array("id", "name", "health_multiplier", "damage_multiplier", _
                    "xp_multiplier", "extra_abilities", "visual_effect")
    SetHeaders ws, headers
End Sub

Private Sub SetupBehaviorProfilesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("BehaviorProfiles")
    Dim headers As Variant
    ' 29 columns for behavior profile configuration
    headers = Array("id", "name", "description", _
                    "idle_behavior", "idle_roam_radius", "idle_roam_speed_mult", _
                    "idle_pause_min", "idle_pause_max", "patrol_loop", _
                    "detection_range", "detection_type", "aggro_on_damage", _
                    "aggro_memory_time", "leash_range", _
                    "combat_style", "approach_behavior", "preferred_range", _
                    "chase_speed_mult", "strafe_chance", _
                    "kite_distance", "kite_speed_mult", "circle_direction", _
                    "attack_retreat_distance", "attack_retreat_duration", _
                    "flee_health_threshold", "flee_speed_mult", _
                    "ability_use_chance", "ability_priority_mode", "abilities")
    SetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, 4), "stand, roam, patrol"
    SafeAddComment ws.Cells(1, 5), "Roam radius in pixels (for roam behavior)"
    SafeAddComment ws.Cells(1, 6), "Speed multiplier when roaming (0.5 = half speed)"
    SafeAddComment ws.Cells(1, 9), "TRUE/FALSE - loop patrol route"
    SafeAddComment ws.Cells(1, 11), "sight, none"
    SafeAddComment ws.Cells(1, 12), "TRUE/FALSE - aggro when damaged even outside detection"
    SafeAddComment ws.Cells(1, 14), "Max distance from home before giving up chase"
    SafeAddComment ws.Cells(1, 15), "aggressive, ranged, opportunist, hit_run"
    SafeAddComment ws.Cells(1, 16), "direct, charge, kite, phase, circle"
    SafeAddComment ws.Cells(1, 17), "Preferred combat distance (for ranged)"
    SafeAddComment ws.Cells(1, 19), "0.0-1.0 chance to strafe during combat"
    SafeAddComment ws.Cells(1, 20), "Distance to maintain when kiting"
    SafeAddComment ws.Cells(1, 22), "clockwise, counter, random"
    SafeAddComment ws.Cells(1, 25), "0.0-1.0 - health % to trigger flee"
    SafeAddComment ws.Cells(1, 27), "0.0-1.0 - chance to use ability vs basic attack"
    SafeAddComment ws.Cells(1, 28), "highest, conditional, random_weighted"
    SafeAddComment ws.Cells(1, 29), "Comma-separated ability IDs"
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

Private Sub SetupSkillsSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Skills")
    Dim headers As Variant
    headers = Array("id", "name", "type", "tree", "tier", "max_level", "mana_cost", _
                    "stamina_cost", "cooldown", "base_damage", "damage_per_level", _
                    "effect_type", "effect_value", "effect_per_level", "duration", _
                    "prerequisite_ids", "description", "icon_name")
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
    Dim stats As Variant
    stats = Array("melee_damage", "ranged_damage", "magic_damage", "fire_damage", _
                  "cold_damage", "lightning_damage", "poison_damage", _
                  "strength", "dexterity", "intelligence", "vitality", "energy", "luck", _
                  "armor", "magic_resistance", "dodge_chance", _
                  "attack_speed", "critical_chance", "critical_damage", _
                  "life", "mana", "life_regen", "mana_regen", "movement_speed")

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
                    "portrait_id", "dialogue_talk_id")
    SetHeaders ws, headers
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
                    "tick_interval", "visual_effect", "stackable", "max_stacks", "description")
    SetHeaders ws, headers
End Sub

Private Sub SetupZonesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet("Zones")
    Dim headers As Variant
    headers = Array("id", "name", "zone_type", "min_level", "max_level", "enemy_spawn_list", _
                    "loot_table_id", "respawn_time", "music_track", "description")
    SetHeaders ws, headers
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
    headers = Array("id", "name", "chest_type", "tier", "zone_id", "spawn_chance", _
                    "fixed_gold", "fixed_items", "loot_table_id", "min_items", "max_items", _
                    "respawn_time", "quest_id", "description")
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
