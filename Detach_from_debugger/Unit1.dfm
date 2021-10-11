object Form1: TForm1
  Left = 290
  Top = 133
  Width = 655
  Height = 582
  Caption = 'Detach From Debugger'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -14
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesktopCenter
  OnCreate = FormCreate
  DesignSize = (
    647
    554)
  PixelsPerInch = 120
  TextHeight = 16
  object ListView1: TListView
    Left = 8
    Top = 8
    Width = 633
    Height = 505
    Anchors = [akLeft, akTop, akRight, akBottom]
    Columns = <
      item
        Caption = 'Process'
        Width = 246
      end
      item
        Alignment = taRightJustify
        Caption = 'PID'
        Width = 62
      end
      item
        Caption = 'Debugged'
        Width = 123
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnColumnClick = ListView1ColumnClick
    OnCustomDrawItem = ListView1CustomDrawItem
    OnMouseDown = ListView1MouseDown
  end
  object Button1: TButton
    Left = 8
    Top = 520
    Width = 633
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = 'Detach'
    Enabled = False
    TabOrder = 1
    OnClick = Button1Click
  end
  object XPManifest1: TXPManifest
    Left = 132
    Top = 244
  end
  object Timer1: TTimer
    Enabled = False
    OnTimer = Timer1Timer
    Left = 90
    Top = 122
  end
end
