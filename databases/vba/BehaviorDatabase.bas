Attribute VB_Name = "BehaviorDatabase"
'===============================================================================
' BehaviorDatabase Module
' Handles validation and export for Behavior Profiles
'===============================================================================
Option Explicit

' Sheet name
Private Const SHEET_BEHAVIORS As String = "BehaviorProfiles"

' Column indices for BehaviorProfiles (1-based)
Private Const COL_BP_ID As Integer = 1
Private Const COL_BP_NAME As Integer = 2
Private Const COL_BP_DESCRIPTION As Integer = 3

' Idle behavior
Private Const COL_BP_IDLE_BEHAVIOR As Integer = 4      ' stand, roam, patrol
Private Const COL_BP_IDLE_ROAM_RADIUS As Integer = 5
Private Const COL_BP_IDLE_ROAM_SPEED_MULT As Integer = 6
Private Const COL_BP_IDLE_PAUSE_MIN As Integer = 7
Private Const COL_BP_IDLE_PAUSE_MAX As Integer = 8
Private Const COL_BP_PATROL_LOOP As Integer = 9

' Detection
Private Const COL_BP_DETECTION_RANGE As Integer = 10
Private Const COL_BP_DETECTION_TYPE As Integer = 11    ' sight, none
Private Const COL_BP_AGGRO_ON_DAMAGE As Integer = 12
Private Const COL_BP_AGGRO_MEMORY_TIME As Integer = 13
Private Const COL_BP_LEASH_RANGE As Integer = 14

' Combat style
Private Const COL_BP_COMBAT_STYLE As Integer = 15      ' aggressive, ranged, opportunist, hit_run
Private Const COL_BP_APPROACH_BEHAVIOR As Integer = 16 ' direct, charge, kite, phase, circle
Private Const COL_BP_PREFERRED_RANGE As Integer = 17
Private Const COL_BP_CHASE_SPEED_MULT As Integer = 18
Private Const COL_BP_STRAFE_CHANCE As Integer = 19

' Kite/Circle behavior (optional)
Private Const COL_BP_KITE_DISTANCE As Integer = 20
Private Const COL_BP_KITE_SPEED_MULT As Integer = 21
Private Const COL_BP_CIRCLE_DIRECTION As Integer = 22
Private Const COL_BP_ATTACK_RETREAT_DISTANCE As Integer = 23
Private Const COL_BP_ATTACK_RETREAT_DURATION As Integer = 24

' Flee behavior
Private Const COL_BP_FLEE_HEALTH_THRESHOLD As Integer = 25
Private Const COL_BP_FLEE_SPEED_MULT As Integer = 26

' Ability AI
Private Const COL_BP_ABILITY_USE_CHANCE As Integer = 27
Private Const COL_BP_ABILITY_PRIORITY_MODE As Integer = 28 ' highest, conditional, random_weighted
Private Const COL_BP_ABILITIES As Integer = 29          ' Comma-separated ability IDs

' Valid dropdown values
Private validIdleBehaviors() As String
Private validDetectionTypes() As String
Private validCombatStyles() As String
Private validApproachBehaviors() As String
Private validPriorityModes() As String

'-------------------------------------------------------------------------------
' InitValidLists - Initialize validation dropdown arrays
'-------------------------------------------------------------------------------
Private Sub InitValidLists()
    validIdleBehaviors = Split("stand,roam,patrol", ",")
    validDetectionTypes = Split("sight,none", ",")
    validCombatStyles = Split("aggressive,ranged,opportunist,hit_run", ",")
    validApproachBehaviors = Split("direct,charge,kite,phase,circle", ",")
    validPriorityModes = Split("highest,conditional,random_weighted", ",")
End Sub

'===============================================================================
' VALIDATION
'===============================================================================

'-------------------------------------------------------------------------------
' ValidateBehaviorProfiles - Validates all rows in BehaviorProfiles sheet
'-------------------------------------------------------------------------------
Public Sub ValidateBehaviorProfiles()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_BEHAVIORS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_BEHAVIORS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim errors() As String
    Dim errorCount As Integer
    errorCount = 0
    ReDim errors(1 To 1)

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_BP_ID).End(xlUp).row

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_BP_ID).value)

        If Len(id) = 0 Then GoTo NextBehavior

        ' Validate ID format
        If Not ValidateId(id, "bhv_") Then
            LogValidationError errors, errorCount, i, "ID", _
                "Invalid ID format. Use: bhv_name (e.g., bhv_basic_melee)"
        End If

        ' Validate name not empty
        If Len(Trim(ws.Cells(i, COL_BP_NAME).value)) = 0 Then
            LogValidationError errors, errorCount, i, "Name", "Name is required"
        End If

        ' Validate idle behavior
        Dim idleBehavior As String
        idleBehavior = Trim(ws.Cells(i, COL_BP_IDLE_BEHAVIOR).value)
        If Len(idleBehavior) > 0 And Not ValidateDropdown(idleBehavior, validIdleBehaviors) Then
            LogValidationError errors, errorCount, i, "Idle Behavior", _
                "Invalid type. Valid: stand, roam, patrol"
        End If

        ' Validate detection type
        Dim detectionType As String
        detectionType = Trim(ws.Cells(i, COL_BP_DETECTION_TYPE).value)
        If Len(detectionType) > 0 And Not ValidateDropdown(detectionType, validDetectionTypes) Then
            LogValidationError errors, errorCount, i, "Detection Type", _
                "Invalid type. Valid: sight, none"
        End If

        ' Validate combat style
        Dim combatStyle As String
        combatStyle = Trim(ws.Cells(i, COL_BP_COMBAT_STYLE).value)
        If Len(combatStyle) > 0 And Not ValidateDropdown(combatStyle, validCombatStyles) Then
            LogValidationError errors, errorCount, i, "Combat Style", _
                "Invalid type. Valid: aggressive, ranged, opportunist, hit_run"
        End If

        ' Validate approach behavior
        Dim approachBehavior As String
        approachBehavior = Trim(ws.Cells(i, COL_BP_APPROACH_BEHAVIOR).value)
        If Len(approachBehavior) > 0 And Not ValidateDropdown(approachBehavior, validApproachBehaviors) Then
            LogValidationError errors, errorCount, i, "Approach Behavior", _
                "Invalid type. Valid: direct, charge, kite, phase, circle"
        End If

NextBehavior:
    Next i

    ShowValidationResults errors, errorCount, "BehaviorProfiles"
End Sub

'===============================================================================
' EXPORT
'===============================================================================

'-------------------------------------------------------------------------------
' ExportBehaviorProfiles - Exports BehaviorProfiles to JSON
'-------------------------------------------------------------------------------
Public Sub ExportBehaviorProfiles()
    InitValidLists

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_BEHAVIORS)
    On Error GoTo 0

    If ws Is Nothing Then
        MsgBox "Sheet '" & SHEET_BEHAVIORS & "' not found!", vbExclamation
        Exit Sub
    End If

    Dim json As String
    json = "{" & vbCrLf & "  ""behavior_profiles"": [" & vbCrLf

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, COL_BP_ID).End(xlUp).row

    Dim itemCount As Integer
    itemCount = 0

    Dim i As Long
    For i = 2 To lastRow
        Dim id As String
        id = Trim(ws.Cells(i, COL_BP_ID).value)

        If Len(id) = 0 Then GoTo NextExportBehavior

        If itemCount > 0 Then json = json & "," & vbCrLf

        json = json & "    {" & vbCrLf
        json = json & "      ""id"": """ & EscapeJsonString(id) & """," & vbCrLf
        json = json & "      ""name"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_BP_NAME))) & """," & vbCrLf
        json = json & "      ""description"": """ & EscapeJsonString(GetDefaultString(ws.Cells(i, COL_BP_DESCRIPTION))) & """," & vbCrLf
        json = json & vbCrLf

        ' Idle behavior
        json = json & "      ""idle_behavior"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_BP_IDLE_BEHAVIOR), "stand"))) & """," & vbCrLf
        json = json & "      ""idle_roam_radius"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_IDLE_ROAM_RADIUS), 0) & "," & vbCrLf
        json = json & "      ""idle_roam_speed_mult"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_IDLE_ROAM_SPEED_MULT), 0.5) & "," & vbCrLf
        json = json & "      ""idle_pause_min"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_IDLE_PAUSE_MIN), 2) & "," & vbCrLf
        json = json & "      ""idle_pause_max"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_IDLE_PAUSE_MAX), 5) & "," & vbCrLf

        ' Only add patrol_loop if it's a patrol behavior
        Dim idleBhv As String
        idleBhv = LCase(GetDefaultString(ws.Cells(i, COL_BP_IDLE_BEHAVIOR), "stand"))
        If idleBhv = "patrol" Then
            json = json & "      ""patrol_loop"": " & LCase(GetDefaultString(ws.Cells(i, COL_BP_PATROL_LOOP), "true")) & "," & vbCrLf
        End If
        json = json & vbCrLf

        ' Detection
        json = json & "      ""detection_range"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_DETECTION_RANGE), 150) & "," & vbCrLf
        json = json & "      ""detection_type"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_BP_DETECTION_TYPE), "sight"))) & """," & vbCrLf
        json = json & "      ""aggro_on_damage"": " & LCase(GetDefaultString(ws.Cells(i, COL_BP_AGGRO_ON_DAMAGE), "true")) & "," & vbCrLf
        json = json & "      ""aggro_memory_time"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_AGGRO_MEMORY_TIME), 10) & "," & vbCrLf
        json = json & "      ""leash_range"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_LEASH_RANGE), 300) & "," & vbCrLf
        json = json & vbCrLf

        ' Combat style
        json = json & "      ""combat_style"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_BP_COMBAT_STYLE), "aggressive"))) & """," & vbCrLf
        json = json & "      ""approach_behavior"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_BP_APPROACH_BEHAVIOR), "direct"))) & """," & vbCrLf
        json = json & "      ""preferred_range"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_PREFERRED_RANGE), 30) & "," & vbCrLf
        json = json & "      ""chase_speed_mult"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_CHASE_SPEED_MULT), 1) & "," & vbCrLf
        json = json & "      ""strafe_chance"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_STRAFE_CHANCE), 0) & "," & vbCrLf

        ' Kite/Circle optional fields
        Dim kiteDistance As Double
        Dim kiteSpeed As Double
        kiteDistance = GetDefaultNumeric(ws.Cells(i, COL_BP_KITE_DISTANCE), 0)
        kiteSpeed = GetDefaultNumeric(ws.Cells(i, COL_BP_KITE_SPEED_MULT), 0)

        If kiteDistance > 0 Then
            json = json & "      ""kite_distance"": " & kiteDistance & "," & vbCrLf
        End If
        If kiteSpeed > 0 Then
            json = json & "      ""kite_speed_mult"": " & kiteSpeed & "," & vbCrLf
        End If

        Dim circleDir As String
        circleDir = GetDefaultString(ws.Cells(i, COL_BP_CIRCLE_DIRECTION))
        If Len(circleDir) > 0 Then
            json = json & "      ""circle_direction"": """ & EscapeJsonString(LCase(circleDir)) & """," & vbCrLf
        End If

        Dim retreatDist As Double
        Dim retreatDur As Double
        retreatDist = GetDefaultNumeric(ws.Cells(i, COL_BP_ATTACK_RETREAT_DISTANCE), 0)
        retreatDur = GetDefaultNumeric(ws.Cells(i, COL_BP_ATTACK_RETREAT_DURATION), 0)

        If retreatDist > 0 Then
            json = json & "      ""attack_retreat_distance"": " & retreatDist & "," & vbCrLf
        End If
        If retreatDur > 0 Then
            json = json & "      ""attack_retreat_duration"": " & retreatDur & "," & vbCrLf
        End If
        json = json & vbCrLf

        ' Flee behavior
        json = json & "      ""flee_health_threshold"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_FLEE_HEALTH_THRESHOLD), 0) & "," & vbCrLf
        json = json & "      ""flee_speed_mult"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_FLEE_SPEED_MULT), 1) & "," & vbCrLf
        json = json & vbCrLf

        ' Ability AI
        json = json & "      ""ability_use_chance"": " & GetDefaultNumeric(ws.Cells(i, COL_BP_ABILITY_USE_CHANCE), 1) & "," & vbCrLf
        json = json & "      ""ability_priority_mode"": """ & EscapeJsonString(LCase(GetDefaultString(ws.Cells(i, COL_BP_ABILITY_PRIORITY_MODE), "highest"))) & """," & vbCrLf

        ' Abilities array - parse comma-separated list into JSON array
        Dim abilitiesStr As String
        abilitiesStr = GetDefaultString(ws.Cells(i, COL_BP_ABILITIES))
        json = json & "      ""abilities"": " & ConvertToJsonArray(abilitiesStr) & vbCrLf

        json = json & "    }"

        itemCount = itemCount + 1

NextExportBehavior:
    Next i

    json = json & vbCrLf & "  ]" & vbCrLf & "}"

    Dim filePath As String
    filePath = GetExportPath() & "behavior_profiles.json"
    WriteJsonFile filePath, json

    MsgBox "Exported " & itemCount & " behavior profiles to:" & vbCrLf & filePath, vbInformation, "Export Complete"
End Sub

'-------------------------------------------------------------------------------
' ConvertToJsonArray - Converts comma-separated string to JSON array
'-------------------------------------------------------------------------------
Private Function ConvertToJsonArray(csvString As String) As String
    If Len(Trim(csvString)) = 0 Then
        ConvertToJsonArray = "[]"
        Exit Function
    End If

    Dim parts() As String
    parts = Split(csvString, ",")

    Dim result As String
    result = "["

    Dim i As Integer
    For i = LBound(parts) To UBound(parts)
        If i > LBound(parts) Then result = result & ", "
        result = result & """" & EscapeJsonString(Trim(parts(i))) & """"
    Next i

    result = result & "]"
    ConvertToJsonArray = result
End Function
