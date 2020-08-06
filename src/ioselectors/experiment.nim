import std/monotimes, heapqueue


# {.pragma: libKernel32, stdcall, dynlib: "Kernel32.dll".}

# proc queryPerformanceCounter*(
#   lpPerformanceCount: var uint
# ): WINBOOL {.libKernel32, importc: "QueryPerformanceCounter".}

# proc queryPerformanceFrequency*(
#   lpFrequency: var uint
# ): WINBOOL {.libKernel32, importc: "QueryPerformanceFrequency".}


type
  CallBack* = proc () {.gcsafe.}

  TimerCallBack* = object
    finishAt*: MonoTime
    callback*: CallBack

  Timer* = object
    data: HeapQueue[TimerCallBack]
