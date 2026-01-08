Attribute VB_Name = "SharedValidation"
'===============================================================================
' SharedValidation Module
' Common validation and utility functions for all database spreadsheets
'===============================================================================
Option Explicit

' Constants for validation
Public Const VALID_ID_PATTERN As String = "^[a-z]+_[a-z]+_[a-z0-9_]+$"
Public Const DEBUG_PREFIX As String = "debug_"

' Valid prefixes for ID naming convention
Public Enum IdPrefix
    ipWeapon = 1    ' wep_
    ipArmor = 2     ' arm_
    ipAccessory = 3 ' acc_
    ipConsumable = 4 ' con_
    ipAffix = 5     ' afx_
    ipEnemy = 6     ' ene_
    ipSkill = 7     ' skl_
    ipQuest = 8     ' qst_
    ipLoot = 9      ' loot_
End Enum

'-------------------------------------------------------------------------------
' ValidateId - Validates ID format (category_type_name)
'-------------------------------------------------------------------------------
Public Function ValidateId(ByVal id As String, ByVal expectedPrefix As String) As Boolean
    ' Check if empty
    If Len(Trim(id)) = 0 Then
        ValidateId = False
        Exit Function
    End If

    ' Allow debug items
    If Left(id, Len(DEBUG_PREFIX)) = DEBUG_PREFIX Then
        ValidateId = True
        Exit Function
    End If

    ' Check prefix
    If Left(id, Len(expectedPrefix)) <> expectedPrefix Then
        ValidateId = False
        Exit Function
    End If

    ' Check format: must have at least 2 underscores (3 parts)
    Dim parts() As String
    parts = Split(id, "_")
    If UBound(parts) < 2 Then
        ValidateId = False
        Exit Function
    End If

    ' Check all lowercase and alphanumeric
    Dim i As Integer
    For i = 1 To Len(id)
        Dim c As String
        c = Mid(id, i, 1)
        If Not (c Like "[a-z0-9_]") Then
            ValidateId = False
            Exit Function
        End If
    Next i

    ValidateId = True
End Function

'-------------------------------------------------------------------------------
' ValidateDropdown - Checks if value exists in validation list
'-------------------------------------------------------------------------------
Public Function ValidateDropdown(ByVal value As String, ByRef validValues() As String) As Boolean
    Dim i As Integer
    For i = LBound(validValues) To UBound(validValues)
        If LCase(Trim(value)) = LCase(Trim(validValues(i))) Then
            ValidateDropdown = True
            Exit Function
        End If
    Next i
    ValidateDropdown = False
End Function

'-------------------------------------------------------------------------------
' GetDefaultNumeric - Returns default value for empty numeric cells
' Handles both period and comma as decimal separators (locale-safe)
'-------------------------------------------------------------------------------
Public Function GetDefaultNumeric(ByVal cell As Range, Optional ByVal defaultVal As Double = 0) As Double
    If IsEmpty(cell.Value) Or Trim(cell.Value) = "" Then
        GetDefaultNumeric = defaultVal
        Exit Function
    End If

    ' If it's already a number, use it directly
    If IsNumeric(cell.Value) Then
        GetDefaultNumeric = CDbl(cell.Value)
        Exit Function
    End If

    ' Try to parse as string with period decimal (for locales using comma)
    Dim strVal As String
    strVal = Trim(CStr(cell.Value))

    ' Replace period with locale decimal separator and try again
    Dim localeSep As String
    localeSep = Mid(CStr(1.5), 2, 1)  ' Get locale decimal separator

    If localeSep = "," Then
        ' Locale uses comma - replace period with comma
        strVal = Replace(strVal, ".", ",")
    Else
        ' Locale uses period - replace comma with period
        strVal = Replace(strVal, ",", ".")
    End If

    If IsNumeric(strVal) Then
        GetDefaultNumeric = CDbl(strVal)
    Else
        GetDefaultNumeric = defaultVal
    End If
End Function

'-------------------------------------------------------------------------------
' GetDefaultString - Returns default value for empty string cells
'-------------------------------------------------------------------------------
Public Function GetDefaultString(ByVal cell As Range, Optional ByVal defaultVal As String = "") As String
    If IsEmpty(cell.value) Or Trim(cell.value) = "" Then
        GetDefaultString = defaultVal
    Else
        GetDefaultString = CStr(cell.value)
    End If
End Function

'-------------------------------------------------------------------------------
' GetDefaultBoolean - Returns default value for empty boolean cells
'-------------------------------------------------------------------------------
Public Function GetDefaultBoolean(ByVal cell As Range, Optional ByVal defaultVal As Boolean = False) As Boolean
    If IsEmpty(cell.value) Or Trim(cell.value) = "" Then
        GetDefaultBoolean = defaultVal
    Else
        Dim val As String
        val = LCase(Trim(cell.value))
        If val = "true" Or val = "yes" Or val = "1" Then
            GetDefaultBoolean = True
        ElseIf val = "false" Or val = "no" Or val = "0" Then
            GetDefaultBoolean = False
        Else
            GetDefaultBoolean = defaultVal
        End If
    End If
End Function

'-------------------------------------------------------------------------------
' FormatJsonNumber - Formats number with period decimal separator (locale-safe)
'-------------------------------------------------------------------------------
Public Function FormatJsonNumber(ByVal num As Double) As String
    Dim result As String
    result = CStr(num)
    ' Replace locale decimal separator with period
    result = Replace(result, ",", ".")
    FormatJsonNumber = result
End Function

'-------------------------------------------------------------------------------
' EscapeJsonString - Escapes special characters for JSON
'-------------------------------------------------------------------------------
Public Function EscapeJsonString(ByVal str As String) As String
    str = Replace(str, "\", "\\")
    str = Replace(str, """", "\""")
    str = Replace(str, vbCr, "\r")
    str = Replace(str, vbLf, "\n")
    str = Replace(str, vbTab, "\t")
    EscapeJsonString = str
End Function

'-------------------------------------------------------------------------------
' SanitizeJsonDecimals - Fixes decimal separators in JSON output
' Replaces commas in numeric contexts with periods (e.g., "0,5" -> "0.5")
' Call this on the final JSON string before writing to file
'-------------------------------------------------------------------------------
Public Function SanitizeJsonDecimals(ByVal json As String) As String
    Dim result As String
    Dim i As Long
    Dim ch As String
    Dim inString As Boolean
    Dim prevChar As String
    Dim nextChar As String

    result = json
    inString = False

    ' Pattern: digit,digit outside of strings should become digit.digit
    ' This handles cases like "value": 0,5 which should be "value": 0.5

    i = 1
    Do While i <= Len(result)
        ch = Mid(result, i, 1)

        ' Track if we're inside a string
        If ch = """" Then
            ' Check if escaped
            If i > 1 Then
                If Mid(result, i - 1, 1) <> "\" Then
                    inString = Not inString
                End If
            Else
                inString = Not inString
            End If
        End If

        ' If not in string and we have a comma between digits, replace with period
        If Not inString And ch = "," Then
            prevChar = ""
            nextChar = ""
            If i > 1 Then prevChar = Mid(result, i - 1, 1)
            If i < Len(result) Then nextChar = Mid(result, i + 1, 1)

            ' Check if comma is between digits (decimal separator mistake)
            If IsNumeric(prevChar) And IsNumeric(nextChar) Then
                result = Left(result, i - 1) & "." & Mid(result, i + 1)
            End If
        End If

        i = i + 1
    Loop

    SanitizeJsonDecimals = result
End Function

'-------------------------------------------------------------------------------
' WriteJsonFile - Writes string content to a JSON file (UTF-8 without BOM)
' Automatically sanitizes decimal separators (comma -> period) before writing
'-------------------------------------------------------------------------------
Public Sub WriteJsonFile(ByVal filePath As String, ByVal content As String)
    ' Sanitize decimal separators before writing (safety net for locale issues)
    content = SanitizeJsonDecimals(content)

    ' Use ADODB.Stream for proper UTF-8 encoding without BOM
    Dim stream As Object
    Set stream = CreateObject("ADODB.Stream")

    stream.Type = 2  ' adTypeText
    stream.Charset = "UTF-8"
    stream.Open
    stream.WriteText content

    ' Remove BOM by copying to binary stream
    Dim binaryStream As Object
    Set binaryStream = CreateObject("ADODB.Stream")
    binaryStream.Type = 1  ' adTypeBinary
    binaryStream.Open

    ' Skip the 3-byte UTF-8 BOM
    stream.Position = 3
    stream.CopyTo binaryStream

    ' Save to file
    binaryStream.SaveToFile filePath, 2  ' adSaveCreateOverWrite

    binaryStream.Close
    stream.Close

    Set binaryStream = Nothing
    Set stream = Nothing
End Sub

'-------------------------------------------------------------------------------
' GetExportPath - Gets the export folder path relative to workbook
'-------------------------------------------------------------------------------
Public Function GetExportPath() As String
    Dim wbPath As String
    wbPath = ThisWorkbook.Path

    ' Default to exports folder next to workbook
    GetExportPath = wbPath & "\exports\"

    ' Create folder if it doesn't exist
    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FolderExists(GetExportPath) Then
        fso.CreateFolder GetExportPath
    End If
    Set fso = Nothing
End Function

'-------------------------------------------------------------------------------
' LogValidationError - Adds error to validation log
'-------------------------------------------------------------------------------
Public Sub LogValidationError(ByRef errors() As String, ByRef errorCount As Integer, _
                              ByVal row As Long, ByVal column As String, ByVal message As String)
    errorCount = errorCount + 1
    ReDim Preserve errors(1 To errorCount)
    errors(errorCount) = "Row " & row & ", Column " & column & ": " & message
End Sub

'-------------------------------------------------------------------------------
' ShowValidationResults - Displays validation results to user
'-------------------------------------------------------------------------------
Public Sub ShowValidationResults(ByRef errors() As String, ByVal errorCount As Integer, _
                                  ByVal tableName As String)
    If errorCount = 0 Then
        MsgBox tableName & " validation passed!" & vbCrLf & "No errors found.", _
               vbInformation, "Validation Success"
    Else
        Dim msg As String
        msg = tableName & " validation found " & errorCount & " error(s):" & vbCrLf & vbCrLf

        Dim i As Integer
        Dim maxShow As Integer
        maxShow = Application.Min(errorCount, 10) ' Show max 10 errors

        For i = 1 To maxShow
            msg = msg & errors(i) & vbCrLf
        Next i

        If errorCount > 10 Then
            msg = msg & vbCrLf & "... and " & (errorCount - 10) & " more errors."
        End If

        MsgBox msg, vbExclamation, "Validation Errors"
    End If
End Sub

'-------------------------------------------------------------------------------
' ParseCommaSeparated - Splits comma-separated string into array
'-------------------------------------------------------------------------------
Public Function ParseCommaSeparated(ByVal str As String) As String()
    Dim result() As String
    If Len(Trim(str)) = 0 Then
        ReDim result(0)
        result(0) = ""
        ParseCommaSeparated = result
        Exit Function
    End If

    result = Split(str, ",")
    Dim i As Integer
    For i = LBound(result) To UBound(result)
        result(i) = Trim(result(i))
    Next i
    ParseCommaSeparated = result
End Function

'-------------------------------------------------------------------------------
' SafeAddComment - Safely add comment to cell (delete existing first)
'-------------------------------------------------------------------------------
Public Sub SafeAddComment(ByVal cell As Range, ByVal commentText As String)
    On Error Resume Next
    cell.ClearComments
    cell.AddComment commentText
    On Error GoTo 0
End Sub

'-------------------------------------------------------------------------------
' GetOrCreateSheet - Creates a sheet if it doesn't exist, or returns existing
'-------------------------------------------------------------------------------
Public Function GetOrCreateSheet(ByVal sheetName As String) As Worksheet
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
' SetupSheetHeaders - Set headers for a sheet (0-based array)
'-------------------------------------------------------------------------------
Public Sub SetupSheetHeaders(ByVal ws As Worksheet, ByRef headers As Variant)
    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter
End Sub

'===============================================================================
' ID RENAME UTILITY
'===============================================================================

'-------------------------------------------------------------------------------
' RenameId - Renames an ID across ALL sheets in the workbook
'-------------------------------------------------------------------------------
Public Sub RenameId()
    Dim oldId As String, newId As String
    oldId = InputBox("Enter OLD ID to replace:", "Rename ID")
    If Len(oldId) = 0 Then Exit Sub

    newId = InputBox("Enter NEW ID:", "Rename ID")
    If Len(newId) = 0 Then Exit Sub

    Dim ws As Worksheet
    Dim cell As Range
    Dim count As Long
    count = 0

    Application.ScreenUpdating = False

    For Each ws In ThisWorkbook.Worksheets
        For Each cell In ws.UsedRange
            If VarType(cell.Value) = vbString Then
                If cell.Value = oldId Then
                    cell.Value = newId
                    count = count + 1
                ElseIf InStr(cell.Value, oldId) > 0 Then
                    ' Handle comma-separated lists
                    cell.Value = Replace(cell.Value, oldId, newId)
                    count = count + 1
                End If
            End If
        Next cell
    Next ws

    Application.ScreenUpdating = True

    MsgBox "Replaced " & count & " occurrences of '" & oldId & "' with '" & newId & "'", _
           vbInformation, "Rename Complete"
End Sub

'===============================================================================
' DATA VALIDATION SETUP
'===============================================================================

'-------------------------------------------------------------------------------
' SetupAllDataValidation - Creates named ranges and applies dropdowns
'-------------------------------------------------------------------------------
Public Sub SetupAllDataValidation()
    Dim response As VbMsgBoxResult
    response = MsgBox("This will set up data validation dropdowns for all sheets." & vbCrLf & _
                      "Named ranges will be created for ID columns." & vbCrLf & vbCrLf & _
                      "Continue?", vbYesNo + vbQuestion, "Setup Data Validation")

    If response <> vbYes Then Exit Sub

    Application.ScreenUpdating = False

    ' Create named ranges for ID columns
    CreateIdNamedRanges

    ' Apply foreign key dropdowns
    ApplyForeignKeyValidation

    ' Apply enum dropdowns
    ApplyEnumValidation

    Application.ScreenUpdating = True

    MsgBox "Data validation setup complete!" & vbCrLf & vbCrLf & _
           "Named ranges created for ID columns." & vbCrLf & _
           "Dropdowns applied to foreign key and enum columns.", _
           vbInformation, "Setup Complete"
End Sub

'-------------------------------------------------------------------------------
' CreateIdNamedRanges - Creates named ranges for all ID columns
'-------------------------------------------------------------------------------
Private Sub CreateIdNamedRanges()
    ' Delete existing named ranges first
    On Error Resume Next
    Dim nm As Name
    For Each nm In ThisWorkbook.Names
        If Left(nm.Name, 3) = "ID_" Then nm.Delete
    Next nm
    On Error GoTo 0

    ' Create named ranges for each sheet's ID column
    CreateNamedRange "Zones", 1, "ID_Zones"
    CreateNamedRange "Enemies", 1, "ID_Enemies"
    CreateNamedRange "EnemyAbilities", 1, "ID_EnemyAbilities"
    CreateNamedRange "EnemyVariants", 1, "ID_EnemyVariants"
    CreateNamedRange "BehaviorProfiles", 1, "ID_BehaviorProfiles"
    CreateNamedRange "LootTables", 1, "ID_LootTables"
    CreateNamedRange "ItemBases", 1, "ID_ItemBases"
    CreateNamedRange "Affixes", 1, "ID_Affixes"
    CreateNamedRange "UniqueItems", 1, "ID_UniqueItems"
    CreateNamedRange "TalentTrees", 1, "ID_TalentTrees"
    CreateNamedRange "Talents", 1, "ID_Talents"
    CreateNamedRange "Quests", 1, "ID_Quests"
    CreateNamedRange "NPCs", 1, "ID_NPCs"
    CreateNamedRange "ShopInventory", 1, "ID_ShopInventory"
    CreateNamedRange "Dialogues", 1, "ID_Dialogues"
    CreateNamedRange "Consumables", 1, "ID_Consumables"
    CreateNamedRange "StatusEffects", 1, "ID_StatusEffects"
    CreateNamedRange "Chests", 1, "ID_Chests"
    CreateNamedRange "SpawnPoints", 1, "ID_SpawnPoints"
    CreateNamedRange "Cutscenes", 1, "ID_Cutscenes"
    CreateNamedRange "FloatingDialogues", 1, "ID_FloatingDialogues"
    CreateNamedRange "Locations", 1, "ID_Locations"
    CreateNamedRange "PopupMessages", 1, "ID_PopupMessages"
    CreateNamedRange "UITheme", 1, "ID_UITheme"
    CreateNamedRange "Achievements", 1, "ID_Achievements"
    CreateNamedRange "CombatTextCategories", 1, "ID_CombatTextCategories"
End Sub

'-------------------------------------------------------------------------------
' CreateNamedRange - Creates a named range for a column in a sheet
'-------------------------------------------------------------------------------
Private Sub CreateNamedRange(ByVal sheetName As String, ByVal col As Integer, ByVal rangeName As String)
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(sheetName)
    If ws Is Nothing Then Exit Sub

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.count, col).End(xlUp).Row
    If lastRow < 2 Then lastRow = 2

    ' Create dynamic named range (row 2 to last row with data + 100 buffer)
    Dim rng As Range
    Set rng = ws.Range(ws.Cells(2, col), ws.Cells(lastRow + 100, col))

    ThisWorkbook.Names.Add Name:=rangeName, RefersTo:=rng
    On Error GoTo 0
End Sub

'-------------------------------------------------------------------------------
' ApplyForeignKeyValidation - Applies dropdown validation for foreign keys
'-------------------------------------------------------------------------------
Private Sub ApplyForeignKeyValidation()
    ' NPCs
    ApplyValidation "NPCs", 5, "ID_ShopInventory"   ' shop_inventory_id
    ApplyValidation "NPCs", 12, "ID_Dialogues"      ' dialogue_talk_id

    ' ShopInventory
    ApplyValidation "ShopInventory", 3, "ID_ItemBases"  ' item_id

    ' Zones
    ApplyValidation "Zones", 7, "ID_LootTables"     ' loot_table_id
    ApplyValidation "Zones", 13, "ID_StatusEffects" ' status_effect_id

    ' Locations
    ApplyValidation "Locations", 2, "ID_Zones"          ' zone_id
    ApplyValidation "Locations", 7, "ID_StatusEffects"  ' status_effect_id

    ' Enemies (column 7 = base_shield added)
    ApplyValidation "Enemies", 13, "ID_LootTables"  ' loot_table_id
    ApplyValidation "Enemies", 15, "ID_BehaviorProfiles"  ' behavior_profile

    ' Chests (new schema: zone_id=4, loot_table_id=9, quest_id=17)
    ApplyValidation "Chests", 4, "ID_Zones"         ' zone_id
    ApplyValidation "Chests", 9, "ID_LootTables"    ' loot_table_id
    ApplyValidation "Chests", 17, "ID_Quests"       ' quest_id

    ' SpawnPoints
    ApplyValidation "SpawnPoints", 13, "ID_Quests"  ' require_quest_active
    ApplyValidation "SpawnPoints", 14, "ID_Quests"  ' require_quest_completed
    ApplyValidation "SpawnPoints", 15, "ID_Quests"  ' disable_after_quest
    ApplyValidation "SpawnPoints", 16, "ID_Quests"  ' disable_during_quest
    ApplyListValidation "SpawnPoints", 17, "TRUE,FALSE"  ' can_respawn

    ' Quests
    ApplyValidation "Quests", 6, "ID_NPCs"          ' giver_npc
    ApplyValidation "Quests", 7, "ID_NPCs"          ' turn_in_npc
    ApplyValidation "Quests", 9, "ID_Quests"        ' next_quest
    ApplyValidation "Quests", 15, "ID_Dialogues"    ' start_dialogue
    ApplyValidation "Quests", 16, "ID_Dialogues"    ' complete_dialogue

    ' QuestObjectives
    ApplyValidation "QuestObjectives", 1, "ID_Quests"  ' quest_id

    ' UniqueItems
    ApplyValidation "UniqueItems", 3, "ID_ItemBases"   ' base_id

    ' Cutscenes
    ApplyValidation "Cutscenes", 4, "ID_Zones"      ' trigger_target (for zone_enter)

    ' FloatingDialogues - trigger_filter contains zone_id but is free-form text
End Sub

'-------------------------------------------------------------------------------
' ApplyEnumValidation - Applies dropdown validation for enum fields
'-------------------------------------------------------------------------------
Private Sub ApplyEnumValidation()
    ' BehaviorProfiles
    ApplyListValidation "BehaviorProfiles", 4, "stand,roam,patrol"  ' idle_behavior
    ApplyListValidation "BehaviorProfiles", 11, "sight,none"        ' detection_type
    ApplyListValidation "BehaviorProfiles", 15, "aggressive,ranged,opportunist,hit_run"  ' combat_style
    ApplyListValidation "BehaviorProfiles", 16, "direct,charge,kite,phase,circle"  ' approach_behavior
    ApplyListValidation "BehaviorProfiles", 22, "clockwise,counter,random"  ' circle_direction
    ApplyListValidation "BehaviorProfiles", 28, "highest,conditional,random_weighted"  ' ability_priority_mode

    ' CombatTextCategories
    ApplyListValidation "CombatTextCategories", 2, "damage,heal,heal_tick,dot_tick,label"  ' category_type
    ApplyListValidation "CombatTextCategories", 3, "physical,fire,cold,lightning,poison,arcane,bleed,true,critical"  ' damage_type
    ApplyListValidation "CombatTextCategories", 6, "float_up,float_up_slow,bounce,slide_right,flash"  ' animation
    ApplyListValidation "CombatTextCategories", 7, "TRUE,FALSE"  ' show_sign
    ApplyListValidation "CombatTextCategories", 10, "TRUE,FALSE"  ' scale_with_damage

    ' Talents
    ApplyValidation "Talents", 3, "ID_TalentTrees"     ' tree reference
    ApplyListValidation "Talents", 7, "active,passive" ' type
    ApplyListValidation "Talents", 8, "melee,ranged,magic" ' skill_category
    ApplyListValidation "Talents", 9, "true,false" ' auto_learn
    ApplyListValidation "Talents", 12, "physical,fire,cold,lightning,poison,arcane,bleed,pure" ' damage_type
    ApplyListValidation "Talents", 23, "damage,heal,buff,debuff,projectile,magic_projectile,magic_projectile_aoe,summon,teleport,aoe,self_buff"  ' effect_type
    ApplyListValidation "Talents", 31, "melee,melee_1h,melee_2h,ranged,magic"  ' required_weapon_category

    ' NPCs
    ApplyListValidation "NPCs", 3, "quest_giver,trader,trainer,innkeeper,blacksmith,generic"  ' type

    ' ShopInventory
    ApplyListValidation "ShopInventory", 4, "base,unique,consumable"  ' item_type
    ApplyListValidation "ShopInventory", 8, "gold,gems"               ' currency_type

    ' FloatingDialogues
    ApplyListValidation "FloatingDialogues", 2, "zone_enter,zone_exit,location_enter,location_exit,item_pickup,item_equip,potion_use,skill_use,enemy_kill,boss_kill,critical_hit,near_death,level_up,quest_complete,quest_start,gold_pickup,chest_open,shrine_activate,player_idle,combat_start,combat_end,revive"  ' trigger_event

    ' PopupMessages
    ApplyListValidation "PopupMessages", 2, "zone_enter,zone_exit,location_enter,location_exit,quest_start,quest_complete,quest_objective,cutscene_end,manual"  ' trigger_event
    ApplyListValidation "PopupMessages", 6, "none,location,quest,warning,info,combat,discovery"  ' icon

    ' Cutscenes
    ApplyListValidation "Cutscenes", 2, "zone_enter,quest_complete,quest_start,interact,manual"  ' trigger

    ' Consumables
    ApplyListValidation "Consumables", 3, "potion,scroll,food,elixir"  ' consumable_type
    ApplyListValidation "Consumables", 4, "heal_health,heal_mana,buff_stat,cure_status,teleport_town,resurrect"  ' effect_type

    ' StatusEffects
    ApplyListValidation "StatusEffects", 3, "buff,debuff,debuff_dot,buff_hot,control"  ' type

    ' Zones
    ApplyListValidation "Zones", 3, "outdoor,dungeon,cave,town,boss_room,camp"  ' zone_type

    ' Locations
    ApplyListValidation "Locations", 4, "town,camp,poi,dungeon_entrance,quest_area,danger_zone,sanctuary,boss_arena,secret_area"  ' location_type

    ' Enemies
    ApplyListValidation "Enemies", 3, "Normal,Miniboss,Boss"  ' type

    ' EnemyAbilities
    ApplyListValidation "EnemyAbilities", 4, "melee,dash_attack,aoe,projectile,pattern,teleport_attack,beam"  ' type
    ApplyListValidation "EnemyAbilities", 6, "physical,fire,cold,lightning,poison,arcane,bleed,pure"  ' damage_type
    ApplyListValidation "EnemyAbilities", 10, "circle,cone,line,cross,ring"  ' shape

    ' Chests (new schema uses tier weights instead of single tier)
    ApplyListValidation "Chests", 3, "loot,quest"           ' chest_type
    ApplyListValidation "Chests", 12, "TRUE,FALSE"          ' guaranteed_gold
    ApplyListValidation "Chests", 15, "TRUE,FALSE"          ' can_respawn

    ' Quests
    ApplyListValidation "Quests", 4, "story,side"           ' type

    ' QuestObjectives
    ApplyListValidation "QuestObjectives", 3, "kill_named,kill_count,gather,delivery,interact,talk,escort,defend,use_ability,defeat_no_kill,reach_location,race"  ' type

    ' ItemBases
    ApplyListValidation "ItemBases", 3, "Weapon,Head,Chest,Hands,Legs,Feet,Ring,Amulet,Offhand"  ' slot
    ApplyListValidation "ItemBases", 4, "Sword,Axe,Mace,Dagger,Staff,Wand,Bow,Crossbow,Shield,Helmet,Chest,Gloves,Boots,Leggings,Ring,Amulet"  ' item_type
    ApplyListValidation "ItemBases", 18, "melee_1h,melee_2h,ranged,magic"  ' weapon_category

    ' Affixes
    ApplyListValidation "Affixes", 3, "prefix,suffix"       ' type
    ApplyListValidation "Affixes", 4, "attack_power,spell_power,fire_power,cold_power,lightning_power,poison_power,strength,dexterity,intelligence,vitality,energy,luck,armor,magic_resistance,dodge_chance,attack_speed,critical_chance,critical_damage,life,mana,life_regen,mana_regen,movement_speed"  ' stat_modifier

    ' Boolean fields (TRUE/FALSE)
    ApplyListValidation "BehaviorProfiles", 9, "TRUE,FALSE"   ' patrol_loop
    ApplyListValidation "BehaviorProfiles", 12, "TRUE,FALSE"  ' aggro_on_damage
    ApplyListValidation "Quests", 10, "TRUE,FALSE"            ' can_abandon
    ApplyListValidation "Quests", 11, "TRUE,FALSE"            ' auto_complete
    ApplyListValidation "QuestObjectives", 7, "TRUE,FALSE"    ' optional
    ApplyListValidation "NPCs", 10, "TRUE,FALSE"              ' is_interactable
    ApplyListValidation "StatusEffects", 9, "TRUE,FALSE"      ' stackable
    ApplyListValidation "StatusEffects", 11, "TRUE,FALSE"     ' show_in_hud
    ApplyListValidation "EnemyAbilities", 21, "TRUE,FALSE"    ' cardinal_only
    ApplyListValidation "Cutscenes", 6, "TRUE,FALSE"          ' once_only
    ApplyListValidation "Talents", 43, "TRUE,FALSE"           ' can_move_while_casting
    ApplyListValidation "Talents", 44, "TRUE,FALSE"           ' interrupt_on_damage
End Sub

'-------------------------------------------------------------------------------
' ApplyValidation - Applies named range validation to a column
'-------------------------------------------------------------------------------
Private Sub ApplyValidation(ByVal sheetName As String, ByVal col As Integer, ByVal namedRange As String)
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(sheetName)
    If ws Is Nothing Then Exit Sub

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.count, 1).End(xlUp).Row
    If lastRow < 2 Then lastRow = 100

    Dim rng As Range
    Set rng = ws.Range(ws.Cells(2, col), ws.Cells(lastRow + 100, col))

    With rng.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertWarning, _
             Formula1:="=" & namedRange
        .IgnoreBlank = True
        .ShowError = True
        .ErrorTitle = "Invalid ID"
        .ErrorMessage = "Please select a valid ID from the dropdown list."
    End With
    On Error GoTo 0
End Sub

'-------------------------------------------------------------------------------
' ApplyListValidation - Applies static list validation to a column
'-------------------------------------------------------------------------------
Private Sub ApplyListValidation(ByVal sheetName As String, ByVal col As Integer, ByVal listValues As String)
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(sheetName)
    If ws Is Nothing Then Exit Sub

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.count, 1).End(xlUp).Row
    If lastRow < 2 Then lastRow = 100

    Dim rng As Range
    Set rng = ws.Range(ws.Cells(2, col), ws.Cells(lastRow + 100, col))

    With rng.Validation
        .Delete
        .Add Type:=xlValidateList, AlertStyle:=xlValidAlertWarning, _
             Formula1:=listValues
        .IgnoreBlank = True
        .ShowError = True
        .ErrorTitle = "Invalid Value"
        .ErrorMessage = "Please select a valid value from the dropdown list."
    End With
    On Error GoTo 0
End Sub
