import std/monotimes, heapqueue, options, times


# {.pragma: libKernel32, stdcall, dynlib: "Kernel32.dll".}

# proc queryPerformanceCounter*(
#   lpPerformanceCount: var uint
# ): WINBOOL {.libKernel32, importc: "QueryPerformanceCounter".}

# proc queryPerformanceFrequency*(
#   lpFrequency: var uint
# ): WINBOOL {.libKernel32, importc: "QueryPerformanceFrequency".}


type
  Callback* = proc () {.gcsafe.}

  TimerCallback* = object
    finishAt*: MonoTime
    callback*: Callback

  Timer* = object
    data: HeapQueue[TimerCallback]


proc `<`*(x, y: TimerCallback): bool =
  result = x.finishAt < y.finishAt

proc execute*(t: TimerCallback) =
  if t.callback != nil:
    t.callback()

proc processTimer*(timer: var Timer): Option[int] {.inline.} =
  var count = timer.data.len
  let now = getMonoTime()

  while count > 0 and timer.data[0].finishAt <= now:
    let data = timer.data.pop
    data.execute()
    dec count

  if timer.data.len == 0:
    result = none(int)
  else:
    let millisecs = (timer.data[0].finishAt - getMonoTime()).inMilliseconds
    result = some(millisecs.int + 1)
