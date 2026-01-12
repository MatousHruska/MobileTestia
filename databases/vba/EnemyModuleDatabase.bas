Attribute VB_Name = "EnemyModuleDatabase"
'===============================================================================
' EnemyModuleDatabase Module
' Handles validation and export for Modular AI Enemy Modules
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_MODULES As String = "EnemyModules"

' Column indices for EnemyModules (1-based)
Private Const COL_MOD_ID As Integer = 1
Private Const COL_MOD_NAME As Integer = 2
Private Const COL_MOD_TYPE As Integer = 3
Private Const COL_MOD_DESCRIPTION As Integer = 4
Private Const COL_MOD_SCRIPT_PATH As Integer = 5
Private Const COL_MOD_PRIORITY As Integer = 6
Private Const COL_MOD_DEFAULT_CONFIG As Integer = 7

' Valid dropdown values
Private validModuleTypes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validModuleTypes = Split("detection,movement,combat,social,special,utility", ",")
End Sub

'===============================================================================
' VALIDATION
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateEnemyModules - Validates all rows in EnemyModules sheet
'-------------------------------------------------------------------------------
Public Sub ValidateEnemyModules()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_MODULES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_MODULES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_MOD_ID).End(xlUp).Row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_MOD_ID).Value)

        If Len(id) = 0 Then GoTo NextModule

        ' Validate ID format
        If Not ValidateId(id, "mod_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: mod_name (e.g., mod_target_detection)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_MOD_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate module type
        Dim moduleType As String
        moduleType = Trim(ws.Cells(i, COL_MOD_TYPE).Value)
        If Len(moduleType) > 0 And Not ValidateDropdown(moduleType, validModuleTypes) Then
            LogValidationError errors, errorCount, i, "Module Type", _
                "Invalid type. Valid: detection, movement, combat, social, special, utility"
        End If

        ' Validate priority is numeric
        Dim priority As String
        priority = Trim(ws.Cells(i, COL_MOD_PRIORITY).Value)
        If Len(priority) > 0 And Not IsNumeric(priority) Then
            LogValidationError errors, errorCount, i, "Priority", _
                "Priority must be a number"
        End If

        ' Validate default_config is valid JSON (basic check)
        Dim config As String
        config = Trim(ws.Cells(i, COL_MOD_DEFAULT_CONFIG).Value)
        If Len(config) > 0 Then
            If Left(config, 1) <> "{" Or Right(config, 1) <> "}" Then
                LogValidationError errors, errorCount, i, "Default Config", _
                    "Config must be valid JSON object (start with { and end with })"
            End If
        End If

NextModule:
    Next i

    ShowValidationResults errors, errorCount, "EnemyModules"
End Sub

'===============================================================================
' EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportEnemyModules - Exports EnemyModules to JSON
'-------------------------------------------------------------------------------
Public Sub ExportEnemyModules()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_MODULES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_MODULES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""enemy_modules"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_MOD_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_MOD_ID).Value)

        If Len(id) = 0 Then GoTo NextExportModule

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_MOD_NAME))) & """," & vbCrLf
        json = json & "      ""module_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_MOD_TYPE), "utility"))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_MOD_DESCRIPTION))) & """," & vbCrLf

        ' Script path - auto-generate if empty
        Dim scriptPath As String
        scriptPath = Trim(ws.Cells(i, COL_MOD_SCRIPT_PATH).Value)
        If Len(scriptPath) = 0 Then
            ' Auto-generate: mod_target_detection -> res://scripts/npc/ai/modules/target_detection_module.gd
            Dim moduleName As String
            moduleName = Mid(id, 5) ' Remove "mod_" prefix
            scriptPath = "res://scripts/npc/ai/modules/" & moduleName & "_module.gd"
        End If
        json = json & "      ""script_path"": """ & EscapeJsonString(scriptPath) & """," & vbCrLf

        json = json & "      ""priority"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_MOD_PRIORITY), 50)) & "," & vbCrLf

        ' Default config - output as JSON object
        Dim configStr As String
        configStr = Trim(ws.Cells(i, COL_MOD_DEFAULT_CONFIG).Value)
        If Len(configStr) = 0 Then
            json = json & "      ""default_config"": {}" & vbCrLf
        Else
            json = json & "      ""default_config"": " & configStr & vbCrLf
        End If

        json = json & "    }"

        itemCount = itemCount + 1

NextExportModule:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "enemy_modules.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " enemy modules to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub
