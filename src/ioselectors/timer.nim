import timerwheel
import std/monotimes
import times, heapqueue


type
  TimerItem* = object
    finishAt*: MonoTime
    slot*: TimerEventList

  Timer* = object
    data: HeapQueue[TimerItem]


proc `<`*(x, y: TimerItem): bool =
  result = x.finishAt < y.finishAt
