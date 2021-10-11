unit ProcessInfo;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Controls,
  Dialogs, ComCtrls, AccCtrl, TlHelp32, ShlObj, ActiveX, StrUtils, Graphics,
  ShellAPI, AclAPI, Math, PsAPI, ExtCtrls, WinSvc, StdCtrls, Registry;

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  TProcess = record
    ImageName: WideString;
    ProcessId: THandle;
    InheritedFromProcessId: THandle;
  end;

  TProcessInformation = array of TProcess;

function GetProcessInformation(var ProcessInformation: TProcessInformation; var ProcessListChanged: Boolean): ULONG;
function DetachProcessFromDebugger(ProcessHandle: THandle): Boolean;
function GetProcessIsBeingDebugged(ProcessHandle: THandle; var IsBeingDebugged: Boolean): Boolean;

implementation

type
  NTSTATUS = UINT;

const
  STATUS_SUCCESS = NTSTATUS($00000000);
  STATUS_INFO_LENGTH_MISMATCH = NTSTATUS($C0000004);

type
  USHORT = Word;
  LONG = Longint;
  PVOID = Pointer;
  ULONGLONG = UInt64;
  ULONG_PTR = NativeUInt;
  SIZE_T = ULONG_PTR;

type
  UNICODE_STRING = record
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PWideChar;
  end;

  PUNICODE_STRING = ^UNICODE_STRING;

  KPRIORITY = LONG;

  CLIENT_ID = record
    UniqueProcess: THandle;
    UniqueThread: THandle;
  end;

  _KWAIT_REASON = (
    Executive,
    FreePage,
    PageIn,
    PoolAllocation,
    DelayExecution,
    Suspended,
    UserRequest,
    WrExecutive,
    WrFreePage,
    WrPageIn,
    WrPoolAllocation,
    WrDelayExecution,
    WrSuspended,
    WrUserRequest,
    WrEventPair,
    WrQueue,
    WrLpcReceive,
    WrLpcReply,
    WrVirtualMemory,
    WrPageOut,
    WrRendezvous,
    WrKeyedEvent,
    WrTerminated,
    WrProcessInSwap,
    WrCpuRateControl,
    WrCalloutStack,
    WrKernel,
    WrResource,
    WrPushLock,
    WrMutex,
    WrQuantumEnd,
    WrDispatchInt,
    WrPreempted,
    WrYieldExecution,
    WrFastMutex,
    WrGuardedMutex,
    WrRundown,
    MaximumWaitReason);
  KWAIT_REASON = _KWAIT_REASON;

  SYSTEM_THREADS = record
    KernelTime: FILETIME;
    UserTime: FILETIME;
    CreateTime: FILETIME;
    WaitTime: ULONG;
    StartAddress: PVOID;
    ClientId: CLIENT_ID;
    Priority: KPRIORITY;
    BasePriority: LONG;
    ContextSwitches: ULONG;
    ThreadState: ULONG;
    WaitReason: KWAIT_REASON;
  end;

  SYSTEM_PROCESS_INFORMATION = record
    NextEntryOffset: ULONG;
    NumberOfThreads: ULONG;
    WorkingSetPrivateSize: LARGE_INTEGER;
    HardFaultCount: ULONG;
    NumberOfThreadsHighWatermark: ULONG;
    CycleTime: ULONGLONG;
    CreateTime: FILETIME;
    UserTime: FILETIME;
    KernelTime: FILETIME;
    ImageName: UNICODE_STRING;
    BasePriority: KPRIORITY;
    ProcessId: THandle;
    InheritedFromProcessId: THandle;
    HandleCount: ULONG;
    SessionId: ULONG;
    UniqueProcessKey: ULONG_PTR;
    PeakVirtualSize: SIZE_T;
    VirtualSize: SIZE_T;
    PageFaultCount: ULONG;
    PeakWorkingSetSize: SIZE_T;
    WorkingSetSize: SIZE_T;
    QuotaPeakPagedPoolUsage: SIZE_T;
    QuotaPagedPoolUsage: SIZE_T;
    QuotaPeakNonPagedPoolUsage: SIZE_T;
    QuotaNonPagedPoolUsage: SIZE_T;
    PageFileUsage: SIZE_T;
    PeakPageFileUsage: SIZE_T;
    PrivatePageCount: SIZE_T;
    ReadOperationCount: Int64;
    WriteOperationCount: Int64;
    OtherOperationCount: Int64;
    ReadTransferCount: Int64;
    WriteTransferCount: Int64;
    OtherTransferCount: Int64;
    Threads: array [0 .. 0] of SYSTEM_THREADS;
  end;

  PSYSTEM_PROCESS_INFORMATION = ^SYSTEM_PROCESS_INFORMATION;

type
  TNtQuerySystemInformation = function(
    SystemInformationClass: ULONG;
    SystemInformation: PVOID;
    SystemInformationLength: ULONG;
    ReturnLength: PULONG): NTSTATUS; stdcall;

  TNtQueryInformationProcess = function(
    ProcessHandle: THandle;
    ProcessInformationClass: ULONG;
    ProcessInformation: PVOID;
    ProcessInformationLength: ULONG;
    ReturnLength: PULONG): NTSTATUS; stdcall;

  TNtRemoveProcessDebug = function(
    ProcessHandle: THandle;
    DebugObjectHandle: THandle): NTSTATUS; stdcall;

  TNtSetInformationDebugObject = function(
    DebugObjectHandle: THandle;
    DebugObjectInformationClass: ULONG;
    DebugInformation: PVOID;
    DebugInformationLength: ULONG;
    ReturnLength: PULONG
    ): NTSTATUS; stdcall;

  TNtClose = function(Handle: THandle): NTSTATUS; stdcall;

var
  NtQuerySystemInformation: TNtQuerySystemInformation;
  NtQueryInformationProcess: TNtQueryInformationProcess;
  NtRemoveProcessDebug: TNtRemoveProcessDebug;
  NtSetInformationDebugObject: TNtSetInformationDebugObject;
  NtClose: TNtClose;

function GetProcessIsBeingDebugged(ProcessHandle: THandle; var IsBeingDebugged: Boolean): Boolean;
var
  DebugPort: PVOID;
  TargetProcessHandle: THandle;
  SourceProcessHandle: THandle;
  DuplicateResult: BOOL;
  DesiredAccess: ACCESS_MASK;
begin
  Result := False;
  try
    if (@NtQueryInformationProcess <> nil) then
    begin
      DuplicateResult := False;
      TargetProcessHandle := 0;
      DuplicateResult := DuplicateHandle(GetCurrentProcess(), ProcessHandle, GetCurrentProcess(), @TargetProcessHandle, 0, False, DUPLICATE_SAME_ACCESS);
      if DuplicateResult then
      begin
        try
          if NtQueryInformationProcess(
            TargetProcessHandle,
            7,
            @DebugPort,
            SizeOf(PVOID),
            nil
            ) = 0 then
            Result := True;
          if DebugPort <> nil then
            IsBeingDebugged := True;
        finally
          if TargetProcessHandle <> 0 then
            CloseHandle(TargetProcessHandle);
        end;
      end;
    end;
  except
  end;
end;

function DetachProcessFromDebugger(ProcessHandle: THandle): Boolean;
var
  DebugObjectHandle: THandle;
  DebugFlags: ULONG;
  TargetProcessHandle: THandle;
  SourceProcessHandle: THandle;
  DuplicateResult: BOOL;
  DesiredAccess: ACCESS_MASK;
begin
  Result := False;
  try
    if (@NtQueryInformationProcess <> nil) then
    begin
      DebugObjectHandle := 0;
      if NtQueryInformationProcess(
        ProcessHandle,
        30,
        @DebugObjectHandle,
        SizeOf(THandle),
        nil) = 0 then
      begin
        try
          if (@NtSetInformationDebugObject <> nil) and (@NtRemoveProcessDebug <> nil) then
          begin
            DebugFlags := 0;
            NtSetInformationDebugObject(
              DebugObjectHandle,
              2,
              @DebugFlags,
              SizeOf(ULONG),
              nil);

            if NtRemoveProcessDebug(ProcessHandle, DebugObjectHandle) = 0 then
              Result := True;
          end;
        finally
          if DebugObjectHandle <> 0 then
            NtClose(DebugObjectHandle);
        end;
      end;
    end;
  except
  end;
end;

var
  ProcessIdSum, ProcessIdSumNew: Int64;

function GetProcessInformation(var ProcessInformation: TProcessInformation; var ProcessListChanged: Boolean): ULONG;
var
  i: ULONG;
  SystemInformation: PVOID;
  SystemInformationLength: ULONG;
  ReturnLength: ULONG;
  ReturnStatus: NTSTATUS;
  PSPI: PSYSTEM_PROCESS_INFORMATION;
begin
  Result := 0;
  Finalize(ProcessInformation);
  ProcessIdSumNew := 0;
  ProcessListChanged := False;

  SystemInformationLength := $1000;
  GetMem(SystemInformation, SystemInformationLength);
  ReturnStatus := NtQuerySystemInformation(5, SystemInformation, SystemInformationLength, @ReturnLength);
  if (ReturnStatus = STATUS_INFO_LENGTH_MISMATCH) then
  begin
    while (ReturnStatus = STATUS_INFO_LENGTH_MISMATCH) do
    begin
      FreeMem(SystemInformation);
      SystemInformationLength := SystemInformationLength * 2;
      GetMem(SystemInformation, SystemInformationLength);
      ReturnStatus := NtQuerySystemInformation(5, SystemInformation, SystemInformationLength, @ReturnLength);
    end;
  end;
  try
    if ReturnStatus = STATUS_SUCCESS then
    begin
      PSPI := PSYSTEM_PROCESS_INFORMATION(SystemInformation);
      repeat
        try
          SetLength(ProcessInformation, Length(ProcessInformation) + 1);

          ProcessIdSumNew := ProcessIdSumNew + PSPI^.ProcessId;

          if PSPI^.ProcessId = 0 then
            ProcessInformation[Result].ImageName := 'System Idle Process'
          else
            ProcessInformation[Result].ImageName := PSPI^.ImageName.Buffer;

          ProcessInformation[Result].ProcessId := PSPI^.ProcessId;
          ProcessInformation[Result].InheritedFromProcessId := PSPI^.InheritedFromProcessId;

          ProcessIdSumNew := ProcessIdSumNew + PSPI^.ProcessId;

          Inc(Result);

        except
        end;

        if PSPI^.NextEntryOffset = 0 then
          Break;
        PSPI := PSYSTEM_PROCESS_INFORMATION(DWORD(PSPI) + PSPI^.NextEntryOffset);
      until
        False;

    end;
  finally
    if SystemInformation <> nil then
      FreeMem(SystemInformation);
    SystemInformation := nil;
  end;

  if ProcessIdSum <> ProcessIdSumNew then
  begin
    ProcessListChanged := True;
    ProcessIdSum := ProcessIdSumNew;
  end;
end;

function _AddCurrentProcessPrivileges(PrivilegeName: WideString): Boolean;
var
  TokenHandle: THandle;
  TokenPrivileges: TTokenPrivileges;
  ReturnLength: DWORD;
begin
  Result := False;
  try
    if OpenProcessToken(GetCurrentProcess, TOKEN_ADJUST_PRIVILEGES or TOKEN_QUERY, TokenHandle) then
    begin
      try
        LookupPrivilegeValueW(nil, PWideChar(PrivilegeName), TokenPrivileges.Privileges[0].Luid);
        TokenPrivileges.PrivilegeCount := 1;
        TokenPrivileges.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED;
        if AdjustTokenPrivileges(TokenHandle, False, TokenPrivileges, 0, nil, ReturnLength) then
          Result := True;
      finally
        CloseHandle(TokenHandle);
      end;
    end;
  except
  end;
end;

function _Initialize: LongBool;
var
  LibraryHandle: HMODULE;
begin
  _AddCurrentProcessPrivileges('SeDebugPrivilege');

  LibraryHandle := LoadLibrary('ntdll.dll');
  if LibraryHandle <> 0 then
  begin
    try
      @NtQuerySystemInformation := GetProcAddress(LibraryHandle, 'NtQuerySystemInformation');
      @NtQueryInformationProcess := GetProcAddress(LibraryHandle, 'NtQueryInformationProcess');
      @NtRemoveProcessDebug := GetProcAddress(LibraryHandle, 'NtRemoveProcessDebug');
      @NtSetInformationDebugObject := GetProcAddress(LibraryHandle, 'NtSetInformationDebugObject');
      @NtClose := GetProcAddress(LibraryHandle, 'NtClose');
    finally
      LibraryHandle := 0;
      FreeLibrary(LibraryHandle);
    end;
  end;
end;

function _DeInitialize: LongBool;
begin

end;

initialization

_Initialize;

finalization

_DeInitialize;

end.
