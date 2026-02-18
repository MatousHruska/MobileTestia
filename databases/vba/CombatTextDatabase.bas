Attribute VB_Name = "CombatTextDatabase"
'===============================================================================
' CombatTextDatabase Module
' Handles validation and export for Combat Text settings and categories
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_CT_SETTINGS As String = "CombatTextSettings"
Private Const SHEET_CT_CATEGORIES As String = "CombatTextCategories"

' Column indices for CombatTextSettings (1-based) - Key/Value format
Private Const COL_CTS_KEY As Integer = 1
Private Const COL_CTS_VALUE As Integer = 2
Private Const COL_CTS_DESCRIPTION As Integer = 3

' Column indices for CombatTextCategories (1-based)
Private Const COL_CTC_ID As Integer = 1
Private Const COL_CTC_CATEGORY_TYPE As Integer = 2
Private Const COL_CTC_DAMAGE_TYPE As Integer = 3
Private Const COL_CTC_FONT_SIZE As Integer = 4
Private Const COL_CTC_COLOR As Integer = 5
Private Const COL_CTC_ANIMATION As Integer = 6
Private Const COL_CTC_SHOW_SIGN As Integer = 7
Private Const COL_CTC_PREFIX As Integer = 8
Private Const COL_CTC_LIFETIME_MULT As Integer = 9
Private Const COL_CTC_SCALE_WITH_DAMAGE As Integer = 10
Private Const COL_CTC_MIN_SCALE As Integer = 11
Private Const COL_CTC_MAX_SCALE As Integer = 12
Private Const COL_CTC_SCALE_THRESHOLD As Integer = 13

' Valid category types
Private Function GetValidCategoryTypes() As Variant
    GetValidCategoryTypes = Array("damage", "heal", "heal_tick", "dot_tick", "label")
End Function

' Valid damage types
Private Function GetValidDamageTypes() As Variant
    GetValidDamageTypes = Array("physical", "fire", "cold", "lightning", "poison", "arcane", "bleed", "true", "critical", "")
End Function

' Valid animation types
Private Function GetValidAnimations() As Variant
    GetValidAnimations = Array("float_up", "float_up_slow", "bounce", "slide_right", "flash")
End Function

'-------------------------------------------------------------------------------
' ValidateCombatTextCategories - Validates all rows in CombatTextCategories sheet
'-------------------------------------------------------------------------------
Public Sub ValidateCombatTextCategories()
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CT_CATEGORIES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_CT_CATEGORIES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_CTC_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_CTC_ID).Value)

        If Len(id) = 0 Then GoTo NextCategory

        ' Validate ID format
        If Not ValidateId(id, "ct_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: ct_type_name (e.g., ct_damage_physical)"
        End If

        ' Validate category_type
        Dim catType As String
        catType = Trim(ws.Cells(i, COL_CTC_CATEGORY_TYPE).Value)
        If Len(catType) = 0 Then
            LogValidationError errors, errorCount, i, "Category Type", "Category type is required"
        Else
            Dim validTypes As Variant
            validTypes = GetValidCategoryTypes()
            Dim isValidType As Boolean
            isValidType = False
            Dim j As Integer
            For j = LBound(validTypes) To UBound(validTypes)
                If LCase(catType) = LCase(validTypes(j)) Then
                    isValidType = True
                    Exit For
                End If
            Next j
            If Not isValidType Then
                LogValidationError errors, errorCount, i, "Category Type", _
                    "Invalid category type. Valid: damage, heal, heal_tick, dot_tick, label"
            End If
        End If

        ' Validate damage_type if damage category
        Dim dmgType As String
        dmgType = Trim(ws.Cells(i, COL_CTC_DAMAGE_TYPE).Value)
        If LCase(catType) = "damage" And Len(dmgType) = 0 Then
            LogValidationError errors, errorCount, i, "Damage Type", "Damage type required for damage category"
        End If

        ' Validate animation
        Dim anim As String
        anim = Trim(ws.Cells(i, COL_CTC_ANIMATION).Value)
        If Len(anim) > 0 Then
            Dim validAnims As Variant
            validAnims = GetValidAnimations()
            Dim isValidAnim As Boolean
            isValidAnim = False
            Dim k As Integer
            For k = LBound(validAnims) To UBound(validAnims)
                If LCase(anim) = LCase(validAnims(k)) Then
                    isValidAnim = True
                    Exit For
                End If
            Next k
            If Not isValidAnim Then
                LogValidationError errors, errorCount, i, "Animation", _
                    "Invalid animation. Valid: float_up, float_up_slow, bounce, slide_right, flash"
            End If
        End If

        ' Validate font_size positive
        Dim fontSize As Double
        fontSize = GetDefaultNumeric(ws.Cells(i, COL_CTC_FONT_SIZE), 12)
        If fontSize <= 0 Then
            LogValidationError errors, errorCount, i, "Font Size", "Must be greater than 0"
        End If

        ' Validate color format (r,g,b,a)
        Dim colorStr As String
        colorStr = Trim(ws.Cells(i, COL_CTC_COLOR).Value)
        If Len(colorStr) > 0 Then
            Dim colorParts() As String
            colorParts = Split(colorStr, ",")
            If UBound(colorParts) < 2 Then
                LogValidationError errors, errorCount, i, "Color", "Color must be in format: r,g,b,a (e.g., 1.0,0.5,0.0,1.0)"
            End If
        End If

NextCategory:
    Next i

    ShowValidationResults errors, errorCount, "CombatTextCategories"
End Sub

'-------------------------------------------------------------------------------
' ExportCombatText - Exports both settings and categories to single JSON
'-------------------------------------------------------------------------------
Public Sub ExportCombatText()
    Dim wsSettings As Worksheet
    Dim wsCategories As Worksheet

    On Error Resume Next
    Set wsSettings = ThisWorkbook.Sheets(SHEET_CT_SETTINGS)
    Set wsCategories = ThisWorkbook.Sheets(SHEET_CT_CATEGORIES)
    On Error GoTo 0

    Dim json As String
    json = "{" & vbCrLf

    ' Export settings
    json = json & "  ""combat_text_settings"": {"
    If Not wsSettings Is Nothing Then
        json = json & vbCrLf
        Dim lastSettingRow As Long
        lastSettingRow = wsSettings.Cells(wsSettings.Rows.Count, COL_CTS_KEY).End(xlUp).Row

        Dim settingCount As Integer
        settingCount = 0

        Dim i As Long
        For i = 2 To lastSettingRow
            Dim settingKey As String
            settingKey = Trim(wsSettings.Cells(i, COL_CTS_KEY).Value)

            If Len(settingKey) = 0 Then GoTo NextSetting

            If settingCount > 0 Then json = json & "," & vbCrLf

            Dim settingValue As String
            settingValue = Trim(wsSettings.Cells(i, COL_CTS_VALUE).Value)

            ' Check if boolean
            If LCase(settingValue) = "true" Or LCase(settingValue) = "false" Then
                json = json & "    """ & EscapeJsonString(settingKey) & """: " & LCase(settingValue)
            ' Check if numeric
            ElseIf IsNumeric(settingValue) Then
                json = json & "    """ & EscapeJsonString(settingKey) & """: " & FormatJsonNumber(CDbl(settingValue))
            Else
                json = json & "    """ & EscapeJsonString(settingKey) & """: """ & EscapeJsonString(settingValue) & """"
            End If

            settingCount = settingCount + 1

NextSetting:
        Next i
        json = json & vbCrLf & "  }"
    Else
        ' Default settings if sheet doesn't exist
        json = json & vbCrLf
        json = json & "    ""enabled"": true," & vbCrLf
        json = json & "    ""pool_size"": 30," & vbCrLf
        json = json & "    ""max_visible_per_target"": 8," & vbCrLf
        json = json & "    ""default_lifetime"": 1.0," & vbCrLf
        json = json & "    ""rise_speed"": 45.0," & vbCrLf
        json = json & "    ""spread_range_x"": 20.0," & vbCrLf
        json = json & "    ""spread_range_y"": 8.0," & vbCrLf
        json = json & "    ""fade_start_percent"": 0.65," & vbCrLf
        json = json & "    ""stack_offset_y"": 14.0," & vbCrLf
        json = json & "    ""batch_window"": 0.15," & vbCrLf
        json = json & "    ""min_batch_count"": 2" & vbCrLf
        json = json & "  }"
    End If

    json = json & "," & vbCrLf

    ' Export categories
    json = json & "  ""combat_text_categories"": ["

    If Not wsCategories Is Nothing Then
        json = json & vbCrLf

        Dim lastCatRow As Long
        lastCatRow = wsCategories.Cells(wsCategories.Rows.Count, COL_CTC_ID).End(xlUp).Row

        Dim catCount As Integer
        catCount = 0

        Dim c As Long
        For c = 2 To lastCatRow
            Dim catId As String
            catId = Trim(wsCategories.Cells(c, COL_CTC_ID).Value)

            If Len(catId) = 0 Then GoTo NextCat

            If catCount > 0 Then json = json & "," & vbCrLf

            json = json & "    {" & vbCrLf
            json = json & "      ""id"": """ & EscapeJsonString(catId) & """," & vbCrLf
            json = json & "      ""category_type"": """ & EscapeJsonString(LCase(GetDefaultString(wsCategories.Cells(c, COL_CTC_CATEGORY_TYPE), "damage"))) & """," & vbCrLf
            json = json & "      ""damage_type"": """ & EscapeJsonString(LCase(GetDefaultString(wsCategories.Cells(c, COL_CTC_DAMAGE_TYPE)))) & """," & vbCrLf
            json = json & "      ""font_size"": " & FormatJsonNumber(GetDefaultNumeric(wsCategories.Cells(c, COL_CTC_FONT_SIZE), 12)) & "," & vbCrLf
            json = json & "      ""color"": """ & EscapeJsonString(GetDefaultString(wsCategories.Cells(c, COL_CTC_COLOR), "1.0,1.0,1.0,1.0")) & """," & vbCrLf
            json = json & "      ""animation"": """ & EscapeJsonString(LCase(GetDefaultString(wsCategories.Cells(c, COL_CTC_ANIMATION), "float_up"))) & """," & vbCrLf
            json = json & "      ""show_sign"": " & LCase(CStr(GetDefaultBoolean(wsCategories.Cells(c, COL_CTC_SHOW_SIGN), True))) & "," & vbCrLf
            json = json & "      ""prefix"": """ & EscapeJsonString(GetDefaultString(wsCategories.Cells(c, COL_CTC_PREFIX))) & """," & vbCrLf
            json = json & "      ""lifetime_mult"": " & FormatJsonNumber(GetDefaultNumeric(wsCategories.Cells(c, COL_CTC_LIFETIME_MULT), 1)) & "," & vbCrLf
            json = json & "      ""scale_with_damage"": " & LCase(CStr(GetDefaultBoolean(wsCategories.Cells(c, COL_CTC_SCALE_WITH_DAMAGE), False))) & "," & vbCrLf
            json = json & "      ""min_scale"": " & FormatJsonNumber(GetDefaultNumeric(wsCategories.Cells(c, COL_CTC_MIN_SCALE), 0.8)) & "," & vbCrLf
            json = json & "      ""max_scale"": " & FormatJsonNumber(GetDefaultNumeric(wsCategories.Cells(c, COL_CTC_MAX_SCALE), 1.4)) & "," & vbCrLf
            json = json & "      ""scale_threshold"": " & FormatJsonNumber(GetDefaultNumeric(wsCategories.Cells(c, COL_CTC_SCALE_THRESHOLD), 50)) & vbCrLf
            json = json & "    }"

            catCount = catCount + 1

NextCat:
        Next c
        json = json & vbCrLf & "  ]"
    Else
        json = json & "]"
    End If

    json = json & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "combat_text.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported combat text to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupCombatTextSettingsSheet - Creates CombatTextSettings sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupCombatTextSettingsSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CT_SETTINGS)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_CT_SETTINGS
    End If

    Dim headers As Variant
    headers = Array("key", "value", "description")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Setting key name (e.g., enabled, pool_size)"
    SafeAddComment ws.Cells(1, 2), "Value (boolean, number, or string)"
    SafeAddComment ws.Cells(1, 3), "Description of what this setting controls"

    If Not g_SilentMode Then
        MsgBox "CombatTextSettings sheet created with headers!", vbInformation
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupCombatTextCategoriesSheet - Creates CombatTextCategories sheet with headers
'-------------------------------------------------------------------------------
Public Sub SetupCombatTextCategoriesSheet()
    Dim ws As Worksheet

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_CT_CATEGORIES)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SHEET_CT_CATEGORIES
    End If

    Dim headers As Variant
    headers = Array("id", "category_type", "damage_type", "font_size", "color", _
                    "animation", "show_sign", "prefix", "lifetime_mult", "scale_with_damage", _
                    "min_scale", "max_scale", "scale_threshold")

    Dim col As Integer
    For col = 0 To UBound(headers)
        ws.Cells(1, col + 1).Value = headers(col)
        ws.Cells(1, col + 1).Font.Bold = True
        ws.Cells(1, col + 1).Interior.Color = RGB(200, 200, 200)
    Next col
    ws.Rows(1).AutoFilter

    ' Add column notes
    SafeAddComment ws.Cells(1, 1), "Format: ct_type_name (e.g., ct_damage_physical, ct_heal_direct, ct_label_dodge)"
    SafeAddComment ws.Cells(1, 2), "damage, heal, heal_tick, dot_tick, label"
    SafeAddComment ws.Cells(1, 3), "physical, fire, cold, lightning, poison, arcane, bleed, true, critical (blank for non-damage)"
    SafeAddComment ws.Cells(1, 4), "Font size in pixels (default 12)"
    SafeAddComment ws.Cells(1, 5), "Color in r,g,b,a format (e.g., 1.0,0.5,0.0,1.0)"
    SafeAddComment ws.Cells(1, 6), "float_up, float_up_slow, bounce, slide_right, flash"
    SafeAddComment ws.Cells(1, 7), "TRUE/FALSE - show +/- sign"
    SafeAddComment ws.Cells(1, 8), "Text prefix (e.g., + for heals)"
    SafeAddComment ws.Cells(1, 9), "Lifetime multiplier (1.0 = default duration)"
    SafeAddComment ws.Cells(1, 10), "TRUE/FALSE - scale text size based on damage amount"
    SafeAddComment ws.Cells(1, 11), "Minimum scale factor when scale_with_damage is TRUE"
    SafeAddComment ws.Cells(1, 12), "Maximum scale factor when scale_with_damage is TRUE"
    SafeAddComment ws.Cells(1, 13), "Damage amount at which max_scale is reached"

    If Not g_SilentMode Then
        MsgBox "CombatTextCategories sheet created with headers!", vbInformation
    End If
End Sub

'-------------------------------------------------------------------------------
' ValidateCombatText - Validates both settings and categories
'-------------------------------------------------------------------------------
Public Sub ValidateCombatText()
    ValidateCombatTextCategories
End Sub
