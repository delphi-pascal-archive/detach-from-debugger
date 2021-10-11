unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ProcessInfo, ComCtrls, Math, CommCtrl, XPMan, StdCtrls, ExtCtrls;

type
  TForm1 = class(TForm)
    XPManifest1: TXPManifest;
    ListView1: TListView;
    Button1: TButton;
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ListView1ColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListView1CustomDrawItem(Sender: TCustomListView;
      Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure Timer1Timer(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure ListView1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    { Private declarations }
  public
    { Public declarations }
    ListViewHeaderWnd: HWND;
    FListViewWndProc: TWndMethod;
    procedure UpdateInfo;
    procedure ListViewWndProc(var Message: TMessage);
  end;

const
  HDF_SORTDOWN = $0200;
  HDF_SORTUP = $0400;

type
  TProcessInfo = class(TObject)
    ImageName: WideString;
    ProcessId: THandle;
    InheritedFromProcessId: THandle;
    IsBeingDebugged: WideString;
    New, Terminated: Integer;
  end;

var
  Form1: TForm1;
  RefreshFirstTime: Boolean = True;
  ProcessList: array of TProcessInfo;
  NewPIDList, PIDList, ProcessInfoList: TStringList;

  SortCaption: WideString = 'Process';
  SortCaptionNew: WideString = 'Process';
  SortType: Byte = 0;
  SortedColumn: Byte = 0;
  NeedUpdateSimple: Boolean = False;
  HighlightDuration: Cardinal = 3;
  SelectedProcessId: Integer = -1;

implementation

{$R *.dfm}

procedure TForm1.ListViewWndProc(var Message: TMessage);
var
  i: Cardinal;
  HDItemHitTestInfo: THDHitTestInfo;
  HDItem: THDItem;
  HDItemText: array [0 .. MAX_PATH] of Char;
begin
  if Message.Msg = WM_NOTIFY then
  begin
    FListViewWndProc(Message);
    with PHDNotify(Pointer(Message.LParam))^ do
    begin
      if ListViewHeaderWnd = Hdr.hwndFrom then
      begin
        case Hdr.code of
          HDN_ITEMCHANGEDW, HDN_ITEMCHANGEDA:
            begin
              if PItem^.Mask and HDI_WIDTH <> 0 then
              begin
                ListView1.Column[Item].Width := PItem.cxy;
                HDItem.Mask := HDI_FORMAT;
                if Header_GetItem(Hdr.hwndFrom, SortedColumn, HDItem) then
                begin
                  if SortType = 1 then
                  begin
                    if (HDItem.fmt and HDF_RIGHT) = HDF_RIGHT then
                      HDItem.fmt := HDF_STRING or HDF_RIGHT or HDF_SORTDOWN
                    else
                      HDItem.fmt := HDF_STRING or HDF_LEFT or HDF_SORTDOWN;
                  end
                  else
                  begin
                    if (HDItem.fmt and HDF_RIGHT) = HDF_RIGHT then
                      HDItem.fmt := HDF_STRING or HDF_RIGHT or HDF_SORTUP
                    else
                      HDItem.fmt := HDF_STRING or HDF_LEFT or HDF_SORTUP;
                  end;
                  Header_SetItem(Hdr.hwndFrom, SortedColumn, HDItem);
                end;
              end;
            end;

          HDN_ITEMDBLCLICKA, HDN_ITEMDBLCLICKW:
            Exit;

          HDN_ITEMCLICKA, HDN_ITEMCLICKW:
            begin
              LockWindowUpdate(ListView1.Handle);
              try
                HDItem.Mask := HDI_FORMAT;
                for i := 0 to ListView1.Columns.Count - 1 do
                begin
                  if Header_GetItem(ListViewHeaderWnd, i, HDItem) then
                  begin
                    if (HDItem.fmt and HDF_SORTDOWN) = HDF_SORTDOWN then
                      HDItem.fmt := HDItem.fmt xor HDF_SORTDOWN;
                    if (HDItem.fmt and HDF_SORTUP) = HDF_SORTUP then
                      HDItem.fmt := HDItem.fmt xor HDF_SORTUP;
                    Header_SetItem(ListViewHeaderWnd, i, HDItem);
                  end;
                end;
                if Header_GetItem(Hdr.hwndFrom, SortedColumn, HDItem) then
                begin
                  if SortType = 1 then
                  begin
                    if (HDItem.fmt and HDF_RIGHT) = HDF_RIGHT then
                      HDItem.fmt := HDF_STRING or HDF_RIGHT or HDF_SORTDOWN
                    else
                      HDItem.fmt := HDF_STRING or HDF_LEFT or HDF_SORTDOWN;
                  end
                  else
                  begin
                    if (HDItem.fmt and HDF_RIGHT) = HDF_RIGHT then
                      HDItem.fmt := HDF_STRING or HDF_RIGHT or HDF_SORTUP
                    else
                      HDItem.fmt := HDF_STRING or HDF_LEFT or HDF_SORTUP;
                  end;
                  Header_SetItem(Hdr.hwndFrom, SortedColumn, HDItem);
                end;
              finally
                LockWindowUpdate(0);
              end;
            end;
        end;
      end;
    end;
  end
  else
    FListViewWndProc(Message);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Font.Name:= 'Tahoma';
  Button1.Top:= ClientHeight - 6 - Button1.Height;
  ListView1.Left:= 3;
  ListView1.Top:= 3;
  ListView1.Width:= ClientWidth - 6;
  ListView1.Height:= ClientHeight - Button1.Height - 15;
  ListView1.DoubleBuffered:= True;
  ListViewHeaderWnd := SendMessage(ListView1.Handle, LVM_GETHEADER, 0, 0);
  FListViewWndProc := ListView1.WindowProc;
  ListView1.WindowProc := ListViewWndProc;
  if ListView1.Columns.Count > 0 then
  begin
    ListView1.Columns[0].Width := ListView1.Columns[0].Width + 1;
    ListView1.Columns[0].Width := ListView1.Columns[0].Width - 1;
  end;
  NewPIDList := TStringList.Create;
  PIDList := TStringList.Create;
  ProcessInfoList := TStringList.Create;
  UpdateInfo;
  Timer1.Enabled := True;
end;

function CustomCompareStr(List: TStringList; Index1, Index2: Integer): Integer;
begin
  if SortType = 0 then
    Result := CompareText(List[Index1], List[Index2])
  else if SortType = 1 then
    Result := CompareText(List[Index2], List[Index1]);
end;

function CustomCompareInt(List: TStringList; Index1, Index2: Integer): Integer;
begin
  if SortType = 0 then
    Result := CompareValue(StrToFloatDef(List[Index1], 0), StrToFloatDef(List[Index2], 0))
  else if SortType = 1 then
    Result := CompareValue(StrToFloatDef(List[Index2], 0), StrToFloatDef(List[Index1], 0));
end;

procedure TForm1.ListView1ColumnClick(Sender: TObject;
  Column: TListColumn);
begin
  if Column.Caption <> SortCaptionNew then
  begin
    SortType := 0;
  end
  else
  begin
    if SortType = 0 then
      SortType := 1
    else
      SortType := 0;
  end;
  SortedColumn := Column.Index;
  SortCaption := Column.Caption;
  SortCaptionNew := Column.Caption;
  NeedUpdateSimple := True;
  UpdateInfo;
end;

procedure TForm1.ListView1CustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  Sender.Canvas.Font.Color := TColor(Item.Data);
end;

procedure TForm1.UpdateInfo;
var
  i, j: Integer;
  ProcessCount: ULONG;
  ProcessInformation: TProcessInformation;
  ProcessHandle: THandle;
  IsBeingDebugged: Boolean;
  ProcessListChanged: Boolean;
begin
  if NeedUpdateSimple = False then
  begin
    ProcessCount := GetProcessInformation(ProcessInformation, ProcessListChanged);
    if (ProcessCount > 0) then
    begin
      if (ProcessListChanged = True) then
      begin
        NewPIDList.Clear;
        for i := 0 to ProcessCount - 1 do
          NewPIDList.Add(IntToStr(ProcessInformation[i].ProcessId));
        if (NewPIDList.Text <> PIDList.Text) then
        begin
          if NewPIDList.Count > 0 then
          begin
            for i := 0 to NewPIDList.Count - 1 do
            begin
              if PIDList.IndexOf(NewPIDList.Strings[i]) = -1 then
              begin
                SetLength(ProcessList, Length(ProcessList) + 1);
                ProcessList[ProcessInfoList.Count] := TProcessInfo.Create;
                ProcessList[ProcessInfoList.Count].ImageName := ProcessInformation[i].ImageName;
                ProcessList[ProcessInfoList.Count].ProcessId := ProcessInformation[i].ProcessId;
                ProcessList[ProcessInfoList.Count].InheritedFromProcessId := ProcessInformation[i].InheritedFromProcessId;
                ProcessHandle := 0;
                IsBeingDebugged := False;
                ProcessHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, True, ProcessInformation[i].ProcessId);
                if ProcessHandle <> 0 then
                begin
                  try
                    if GetProcessIsBeingDebugged(ProcessHandle, IsBeingDebugged) then
                      if IsBeingDebugged then
                        ProcessList[ProcessInfoList.Count].IsBeingDebugged := 'Debugged';
                  finally
                    CloseHandle(ProcessHandle);
                  end;
                end;
                if RefreshFirstTime then
                  ProcessList[ProcessInfoList.Count].New := HighlightDuration + 1
                else
                  ProcessList[ProcessInfoList.Count].New := 0;
                ProcessList[ProcessInfoList.Count].Terminated := 1001;
                ProcessInfoList.AddObject('', ProcessList[ProcessInfoList.Count]);
              end;
            end;
          end;
          if Assigned(PIDList) then
          begin
            for i := 0 to PIDList.Count - 1 do
            begin
              if NewPIDList.IndexOf(PIDList.Strings[i]) = -1 then
              begin
                if Assigned(ProcessInfoList) then
                begin
                  for j := 0 to ProcessInfoList.Count - 1 do
                  begin
                    if PIDList.Strings[i] = IntToStr((ProcessInfoList.Objects[j] as TProcessInfo).ProcessId) then
                    begin
                      if (ProcessInfoList.Objects[j] as TProcessInfo).Terminated = 1001 then
                        (ProcessInfoList.Objects[j] as TProcessInfo).Terminated := 0;
                    end;
                  end;
                end;
              end;
            end;
          end;
          PIDList.Assign(NewPIDList);
        end;
      end;
    end;
    for i := 0 to ProcessInfoList.Count - 1 do
    begin
      IsBeingDebugged := False;
      ProcessHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, True, (ProcessInfoList.Objects[i] as TProcessInfo).ProcessId);
      if ProcessHandle <> 0 then
      begin
        try
          if GetProcessIsBeingDebugged(ProcessHandle, IsBeingDebugged) then
          begin
            if IsBeingDebugged then
              (ProcessInfoList.Objects[i] as TProcessInfo).IsBeingDebugged := 'Debugged'
            else
              (ProcessInfoList.Objects[i] as TProcessInfo).IsBeingDebugged := '';
          end;
        finally
          CloseHandle(ProcessHandle);
        end;
      end;
    end;
    for i := 0 to ProcessInfoList.Count - 1 do
    begin
      if (ProcessInfoList.Objects[i] as TProcessInfo).New < 1001 then
        Inc((ProcessInfoList.Objects[i] as TProcessInfo).New);
      if (ProcessInfoList.Objects[i] as TProcessInfo).Terminated < 1001 then
        Inc((ProcessInfoList.Objects[i] as TProcessInfo).Terminated);
    end;
    i := 0;
    while i < ProcessInfoList.Count do
    begin
      if ((ProcessInfoList.Objects[i] as TProcessInfo).Terminated >= HighlightDuration + 1) and
        ((ProcessInfoList.Objects[i] as TProcessInfo).Terminated < 1001) then
      begin
        ProcessInfoList.Objects[i].Free;
        ProcessInfoList.Delete(i);
        i := -1;
      end;
      Inc(i);
    end;
  end;
  if Assigned(ProcessInfoList) then
  begin
    if ProcessInfoList.Count > 0 then
    begin
      for i := 0 to ProcessInfoList.Count - 1 do
      begin
        if SortCaption = 'Process' then
          ProcessInfoList.Strings[i] := (ProcessInfoList.Objects[i] as TProcessInfo).ImageName;
        if SortCaption = 'Debugged' then
          ProcessInfoList.Strings[i] := (ProcessInfoList.Objects[i] as TProcessInfo).IsBeingDebugged;
        if SortCaption = 'PID' then
          ProcessInfoList.Strings[i] := IntToStr((ProcessInfoList.Objects[i] as TProcessInfo).ProcessId);
      end;
      if (SortCaption = 'Process') or (SortCaption = 'Debugged') then
      begin
        ProcessInfoList.CustomSort(CustomCompareStr);
        ProcessInfoList.CustomSort(CustomCompareStr);
      end;
      if (SortCaption = 'PID') then
      begin
        ProcessInfoList.CustomSort(CustomCompareInt);
        ProcessInfoList.CustomSort(CustomCompareInt);
      end;
    end;
  end;
  LockWindowUpdate(ListView1.Handle);
  try
    if ListView1.Items.Count < ProcessInfoList.Count then
    begin
      for i := ListView1.Items.Count to ProcessInfoList.Count - 1 do
      begin
        with ListView1.Items.Add do
        begin
          Caption := '';
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
          SubItems.Add('');
        end;
      end;
    end
    else if ProcessInfoList.Count < ListView1.Items.Count then
    begin
      for i := 0 to ListView1.Items.Count - ProcessInfoList.Count - 1 do
      begin
        ListView1.Items.Delete(ListView1.Items.Count - 1);
      end;
    end;
    for i := 0 to ProcessInfoList.Count - 1 do
    begin
      ListView1.Items.Item[i].Caption := (ProcessInfoList.Objects[i] as TProcessInfo).ImageName;
      ListView1.Items.Item[i].SubItems[0] := IntToStr((ProcessInfoList.Objects[i] as TProcessInfo).ProcessId);
      ListView1.Items.Item[i].SubItems[1] := (ProcessInfoList.Objects[i] as TProcessInfo).IsBeingDebugged;
      if (ProcessInfoList.Objects[i] as TProcessInfo).Terminated < HighlightDuration + 1 then
        ListView1.Items.Item[i].Data := Pointer(clRed)
      else if (ProcessInfoList.Objects[i] as TProcessInfo).New < HighlightDuration + 1 then
        ListView1.Items.Item[i].Data := Pointer(clGreen)
      else
        ListView1.Items.Item[i].Data := Pointer(clBlack);
      ListView1.Items[i].Selected := False;
      if SelectedProcessId >= 0 then
        if (ProcessInfoList.Objects[i] as TProcessInfo).ProcessId = SelectedProcessId then
          ListView1.Items[i].Selected := True;
    end;
    ListView1.Invalidate;
  finally
    LockWindowUpdate(0);
  end;
  NeedUpdateSimple := False;
  RefreshFirstTime := False;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  UpdateInfo;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  ProcessHandle: THandle;
  IsBeingDebugged: Boolean;
begin
  ProcessHandle := OpenProcess(PROCESS_ALL_ACCESS, True, SelectedProcessId);
  if ProcessHandle <> 0 then
  begin
    IsBeingDebugged := False;
    if GetProcessIsBeingDebugged(ProcessHandle, IsBeingDebugged) then
    begin
      if IsBeingDebugged then
      begin
        if not DetachProcessFromDebugger(ProcessHandle) then
          ShowMessage(SysErrorMessage(GetLastError));
      end
      else
        ShowMessage('The process is not being debugged');
    end;
  end
  else
  begin
    ShowMessage(SysErrorMessage(GetLastError));
  end;
end;

procedure TForm1.ListView1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: Cardinal;
begin
  if Assigned(ListView1.GetItemAt(X, Y)) then
  begin
    SelectedProcessId := StrToIntDef(ListView1.GetItemAt(X, Y).SubItems[0], -1);
    Button1.Enabled := True;
    if Assigned(ProcessInfoList) then
    begin
      if ProcessInfoList.Count > 0 then
      begin
        for i := 0 to ProcessInfoList.Count - 1 do
        begin
          ListView1.Items[i].Selected := False;
          if SelectedProcessId >= 0 then
            if (ProcessInfoList.Objects[i] as TProcessInfo).ProcessId = SelectedProcessId then
              ListView1.Items[i].Selected := True;
        end;
      end;
    end;
  end
  else
  begin
    Button1.Enabled := False;
    SelectedProcessId := -1;
  end;
end;

end.
