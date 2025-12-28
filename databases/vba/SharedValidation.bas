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
'-------------------------------------------------------------------------------
Public Function GetDefaultNumeric(ByVal cell As Range, Optional ByVal defaultVal As Double = 0) As Double
    If IsEmpty(cell.value) Or Trim(cell.value) = "" Then
        GetDefaultNumeric = defaultVal
    ElseIf IsNumeric(cell.value) Then
        GetDefaultNumeric = CDbl(cell.value)
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
' WriteJsonFile - Writes string content to a JSON file (UTF-8 without BOM)
'-------------------------------------------------------------------------------
Public Sub WriteJsonFile(ByVal filePath As String, ByVal content As String)
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
