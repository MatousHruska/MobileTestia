Attribute VB_Name = "IndexSheet"
'===============================================================================
' IndexSheet Module
' Creates a visual, clickable table of contents for the workbook
'===============================================================================
Option Explicit

Private Const SHEET_INDEX As String = "Index"

'-------------------------------------------------------------------------------
' GenerateIndex - Creates a clickable table of contents
'-------------------------------------------------------------------------------
Public Sub GenerateIndex()
    Dim wsIndex As Worksheet
    Dim ws As Worksheet
    Dim row As Integer
    Dim col As Integer
    Dim sheetCount As Integer
    Dim currentGroup As String
    Dim lastTabColor As Long
    Dim groupStartRow As Integer

    ' Get or create Index sheet
    On Error Resume Next
    Set wsIndex = ThisWorkbook.Sheets(SHEET_INDEX)
    On Error GoTo 0

    If wsIndex Is Nothing Then
        MsgBox "Index sheet not found! Please create a sheet named 'Index' first.", vbExclamation
        Exit Sub
    End If

    ' Clear existing content
    wsIndex.Cells.Clear

    ' Setup header
    With wsIndex
        ' Title
        .Range("B2").Value = "DATABASE INDEX"
        .Range("B2").Font.Size = 24
        .Range("B2").Font.Bold = True
        .Range("B2").Font.Color = RGB(50, 50, 50)

        ' Subtitle
        .Range("B3").Value = "Click any sheet name to navigate"
        .Range("B3").Font.Size = 11
        .Range("B3").Font.Italic = True
        .Range("B3").Font.Color = RGB(120, 120, 120)

        ' Last updated
        .Range("B4").Value = "Last updated: " & Format(Now, "yyyy-mm-dd hh:mm")
        .Range("B4").Font.Size = 9
        .Range("B4").Font.Color = RGB(150, 150, 150)
    End With

    ' Start listing sheets
    row = 6
    col = 2
    lastTabColor = -1
    groupStartRow = row
    sheetCount = 0

    ' Collect sheets by tab color groups
    Dim sheetsByColor As Object
    Set sheetsByColor = CreateObject("Scripting.Dictionary")

    For Each ws In ThisWorkbook.Sheets
        If ws.Name <> SHEET_INDEX Then
            Dim colorKey As String
            ' Handle colorless tabs (ColorIndex = -4142 means no color)
            If ws.Tab.ColorIndex = -4142 Or ws.Tab.ColorIndex = xlColorIndexNone Then
                colorKey = "NO_COLOR"
            Else
                colorKey = CStr(ws.Tab.Color)
            End If

            If Not sheetsByColor.Exists(colorKey) Then
                sheetsByColor.Add colorKey, CreateObject("Scripting.Dictionary")
            End If
            sheetsByColor(colorKey).Add ws.Name, ws
        End If
    Next ws

    ' Now output sheets grouped by color
    Dim colorKeys As Variant
    Dim i As Integer
    Dim sheetNames As Variant
    Dim j As Integer

    colorKeys = sheetsByColor.Keys

    For i = 0 To sheetsByColor.Count - 1
        Dim colorGroup As Object
        Set colorGroup = sheetsByColor(colorKeys(i))
        Dim tabColor As Long
        Dim hasColor As Boolean

        ' Check if this is the colorless group
        If colorKeys(i) = "NO_COLOR" Then
            hasColor = False
            tabColor = RGB(200, 200, 200)  ' Default gray for colorless
        Else
            hasColor = True
            tabColor = CLng(colorKeys(i))
        End If

        ' Add group separator if color changed
        If i > 0 Then
            row = row + 1  ' Add spacing between groups
        End If

        groupStartRow = row
        sheetNames = colorGroup.Keys

        For j = 0 To colorGroup.Count - 1
            Set ws = colorGroup(sheetNames(j))

            Dim sheetHasColor As Boolean
            sheetHasColor = Not (ws.Tab.ColorIndex = -4142 Or ws.Tab.ColorIndex = xlColorIndexNone)

            With wsIndex
                ' Create hyperlink cell
                .Hyperlinks.Add _
                    Anchor:=.Cells(row, col), _
                    Address:="", _
                    SubAddress:="'" & ws.Name & "'!A1", _
                    TextToDisplay:=ws.Name

                ' Style the cell
                With .Cells(row, col)
                    .Font.Size = 12
                    .Font.Bold = False
                    .Font.Underline = xlUnderlineStyleNone

                    ' Use sheet tab color for text if it has one, otherwise dark gray
                    If sheetHasColor Then
                        .Font.Color = DarkenColor(ws.Tab.Color, 0.3)
                    Else
                        .Font.Color = RGB(60, 60, 60)
                    End If

                    .IndentLevel = 1
                End With

                ' Add color indicator bar
                With .Cells(row, col - 1)
                    If sheetHasColor Then
                        .Interior.Color = ws.Tab.Color
                    Else
                        .Interior.Color = RGB(200, 200, 200)
                    End If
                End With

                ' Add sheet description in next column
                .Cells(row, col + 1).Value = GetSheetDescription(ws.Name)
                .Cells(row, col + 1).Font.Size = 10
                .Cells(row, col + 1).Font.Color = RGB(120, 120, 120)
                .Cells(row, col + 1).Font.Italic = True
            End With

            row = row + 1
            sheetCount = sheetCount + 1
        Next j
    Next i

    ' Format columns
    With wsIndex
        .Columns("A").ColumnWidth = 2   ' Color bar column
        .Columns("B").ColumnWidth = 25  ' Sheet names
        .Columns("C").ColumnWidth = 45  ' Descriptions

        ' Add border around the content area
        Dim contentRange As Range
        Set contentRange = .Range(.Cells(6, 1), .Cells(row - 1, 3))

        ' Light gray background for alternating rows
        Dim r As Integer
        For r = 6 To row - 1
            If (r - 6) Mod 2 = 1 Then
                .Range(.Cells(r, 2), .Cells(r, 3)).Interior.Color = RGB(248, 248, 248)
            End If
        Next r
    End With

    ' Add footer with stats
    With wsIndex
        .Cells(row + 2, col).Value = "Total sheets: " & sheetCount
        .Cells(row + 2, col).Font.Size = 10
        .Cells(row + 2, col).Font.Color = RGB(150, 150, 150)
    End With

    ' Move Index to first position
    wsIndex.Move Before:=ThisWorkbook.Sheets(1)

    ' Activate Index sheet
    wsIndex.Activate
    wsIndex.Range("A1").Select

    MsgBox "Index generated with " & sheetCount & " sheets!", vbInformation
End Sub

'-------------------------------------------------------------------------------
' GetSheetDescription - Returns a description for known sheet names
'-------------------------------------------------------------------------------
Private Function GetSheetDescription(sheetName As String) As String
    Select Case sheetName
        ' Core Data
        Case "Enemies": GetSheetDescription = "Enemy definitions and stats"
        Case "Items": GetSheetDescription = "Weapons, armor, accessories"
        Case "Skills": GetSheetDescription = "Player abilities and skills"
        Case "Quests": GetSheetDescription = "Quest definitions and objectives"
        Case "NPCs": GetSheetDescription = "Non-player characters"
        Case "Dialogues": GetSheetDescription = "Conversation trees"

        ' World
        Case "Zones": GetSheetDescription = "Game zones and areas"
        Case "Locations": GetSheetDescription = "Sub-areas within zones"
        Case "SpawnPoints": GetSheetDescription = "Enemy spawn configurations"
        Case "Chests": GetSheetDescription = "Chest spawn definitions"
        Case "LootTables": GetSheetDescription = "Loot drop tables"

        ' Combat & Effects
        Case "StatusEffects": GetSheetDescription = "Buffs, debuffs, DoTs"
        Case "Consumables": GetSheetDescription = "Potions, scrolls, food"
        Case "Behaviors": GetSheetDescription = "AI behavior profiles"
        Case "CombatText": GetSheetDescription = "Floating combat text"

        ' UI & Presentation
        Case "UITheme": GetSheetDescription = "UI style definitions"
        Case "PopupMessages": GetSheetDescription = "System messages"
        Case "FloatingDialogues": GetSheetDescription = "World speech bubbles"
        Case "Cutscenes": GetSheetDescription = "Cutscene sequences"
        Case "StatDescriptions": GetSheetDescription = "Stat tooltip text"

        ' Configuration
        Case "GameplaySettings": GetSheetDescription = "Core game constants"
        Case "Achievements": GetSheetDescription = "Achievement definitions"
        Case "ShopInventory": GetSheetDescription = "Shop item listings"

        Case Else: GetSheetDescription = ""
    End Select
End Function

'-------------------------------------------------------------------------------
' DarkenColor - Darkens a color by a percentage
'-------------------------------------------------------------------------------
Private Function DarkenColor(ByVal color As Long, ByVal factor As Double) As Long
    Dim r As Integer, g As Integer, b As Integer

    ' Extract RGB components
    r = color Mod 256
    g = (color \ 256) Mod 256
    b = (color \ 65536) Mod 256

    ' Darken each component
    r = Int(r * (1 - factor))
    g = Int(g * (1 - factor))
    b = Int(b * (1 - factor))

    ' Recombine
    DarkenColor = RGB(r, g, b)
End Function

'-------------------------------------------------------------------------------
' RefreshIndex - Quick refresh of the index
'-------------------------------------------------------------------------------
Public Sub RefreshIndex()
    GenerateIndex
End Sub
