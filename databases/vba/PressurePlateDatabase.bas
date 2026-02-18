Attribute VB_Name = "PressurePlateDatabase"
'===============================================================================
' PressurePlateDatabase Module
' Handles validation and export for Pressure Plates (floor triggers)
' Pressure plates can trigger doors, traps, or other mechanisms
'===============================================================================
Option Explicit

' Sheet names
Private Const SHEET_PRESSURE_PLATES As String = "PressurePlates"

' Column indices for PressurePlates (1-based)
' Core
Private Const COL_ID As Integer = 1
Private Const COL_NAME As Integer = 2
' Linkage
Private Const COL_LINKED_DOOR_ID As Integer = 3
' Behavior
Private Const COL_TRIGGER_MODE As Integer = 4
Private Const COL_RESET_DELAY As Integer = 5
Private Const COL_ONE_SHOT As Integer = 6
' Visuals
Private Const COL_SPRITE_ID As Integer = 7
Private Const COL_SOUND_ID As Integer = 8

' Valid dropdown values
Private validTriggerModes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validTriggerModes = Split("step_on,step_off,toggle", ",")
End Sub

'===============================================================================
' PRESSURE PLATES
'===============================================================================

'-------------------------------------------------------------------------------
' ValidatePressurePlatesData - Validates all rows in PressurePlates sheet
'-------------------------------------------------------------------------------
Public Sub ValidatePressurePlatesData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_PRESSURE_PLATES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_PRESSURE_PLATES & "' not found!", vbExclamation
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

        If Len(id) = 0 Then GoTo NextPlate

        ' Validate ID format
        If Not ValidateId(id, "plate_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: plate_zone_name (e.g., plate_crypt_trap)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_NAME).Value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate trigger_mode
        Dim triggerMode As String
        triggerMode = LCase(Trim(ws.Cells(i, COL_TRIGGER_MODE).Value))
        If Len(triggerMode) = 0 Then
            LogValidationError errors, errorCount, i, "Trigger Mode", "Trigger mode is required"
        ElseIf Not ValidateDropdown(triggerMode, validTriggerModes) Then
            LogValidationError errors, errorCount, i, "Trigger Mode", _
                "Invalid mode. Valid: step_on, step_off, toggle"
        End If

        ' Validate reset_delay non-negative
        Dim resetDelay As Double
        resetDelay = GetDefaultNumeric(ws.Cells(i, COL_RESET_DELAY), 0)
        If resetDelay < 0 Then
            LogValidationError errors, errorCount, i, "Reset Delay", "Cannot be negative"
        End If

NextPlate:
    Next i

    ShowValidationResults errors, errorCount, "PressurePlates"
End Sub

'-------------------------------------------------------------------------------
' ExportPressurePlatesData - Exports PressurePlates to JSON
'-------------------------------------------------------------------------------
Public Sub ExportPressurePlatesData()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_PRESSURE_PLATES)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_PRESSURE_PLATES & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""pressure_plates"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_ID).End(xlUp).Row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_ID).Value)

        If Len(id) = 0 Then GoTo NextExportPlate

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        ' Core
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_NAME))) & """," & vbCrLf
        ' Linkage
        json = json & "      ""linked_door_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_LINKED_DOOR_ID))) & """," & vbCrLf
        ' Behavior
        json = json & "      ""trigger_mode"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_TRIGGER_MODE), "step_on"))) & """," & vbCrLf
        json = json & "      ""reset_delay"": " & FormatJsonNumber(GetDefaultNumeric(ws.Cells(i, COL_RESET_DELAY), 0)) & "," & vbCrLf
        json = json & "      ""one_shot"": " & LCase(GetDefaultBoolean(ws.Cells(i, COL_ONE_SHOT), False)) & "," & vbCrLf
        ' Visuals
        json = json & "      ""sprite_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SPRITE_ID))) & """," & vbCrLf
        json = json & "      ""sound_id"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_SOUND_ID))) & """" & vbCrLf
        json = json & "    }"

        itemCount = itemCount + 1

NextExportPlate:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "pressure_plates.json"
    WriteJsonFile filePath, json

    If Not g_SilentMode Then
        MsgBox "Exported " & itemCount & " pressure plates to:" & vbCrLf & filePath, vbInformation, "Export Complete"
    End If
End Sub

'-------------------------------------------------------------------------------
' SetupPressurePlatesSheet - Creates headers for PressurePlates sheet
'-------------------------------------------------------------------------------
Public Sub SetupPressurePlatesSheet()
    Dim ws As Worksheet
    Set ws = GetOrCreateSheet(SHEET_PRESSURE_PLATES)

    Dim headers As Variant
    headers = Array("id", "name", "linked_door_id", "trigger_mode", _
                    "reset_delay", "one_shot", "sprite_id", "sound_id")
    SetupSheetHeaders ws, headers

    ' Add column notes
    SafeAddComment ws.Cells(1, COL_LINKED_DOOR_ID), "Door ID that this plate controls"
    SafeAddComment ws.Cells(1, COL_TRIGGER_MODE), "step_on: active while standing; step_off: triggers when leaving; toggle: each step flips state"
    SafeAddComment ws.Cells(1, COL_RESET_DELAY), "Seconds before auto-reset (0 = no reset)"
    SafeAddComment ws.Cells(1, COL_ONE_SHOT), "TRUE = only triggers once ever"

    ' Auto-fit columns
    ws.Columns("A:H").AutoFit

    If Not g_SilentMode Then
        MsgBox "PressurePlates sheet headers set up successfully!", vbInformation
    End If
End Sub
