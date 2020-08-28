import winlean


# proc readDirectoryChangesW*(
#   hDirectory: HANDLE,
#   lpBuffer: LPVOID,
#   nBufferLength: DWORD,
#   bWatchSubtree: WINBOOL,
#   dwNotifyFilter: DWORD,
#   lpBytesReturned: LPDWORD,
#   lpOverlapped: LPOVERLAPPED,
#   lpCompletionRoutine: LPOVERLAPPED_COMPLETION_ROUTINE
# ): WINBOOL {.importc: "ReadDirectoryChangesW", 
#   dynlib: "Kernel32.dll"}
