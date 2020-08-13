import timerwheel
import std/monotimes
import times, heapqueue, options


type
  TimerItem* = object
    finishAt*: MonoTime
    slot*: TimerEventList

  Timer* = object
    wheel*: TimerWheel
    queue*: HeapQueue[TimerItem]
    now*: MonoTime


proc initTimerItem*(finishAt: MonoTime, slot: TimerEventList): TimerItem =
  TimerItem(finishAt: finishAt, slot: slot)

proc `<`*(x, y: TimerItem): bool =
  result = x.finishAt < y.finishAt

proc initTimer*(): Timer =
  result.wheel = initTimerWheel()
  result.queue = initHeapQueue[TimerItem]()
  result.now = getMonoTime()

proc add*(t: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1, interval: Natural = 100) =
  var evlist = t.wheel.setTimer(event, timeout, repeatTimes)
  if evlist.isSome:
    t.queue.push(initTimerItem(getMonoTime() + initDuration(milliseconds = timeout * interval), evlist.get))
