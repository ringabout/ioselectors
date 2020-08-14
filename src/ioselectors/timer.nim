import timerwheel
import std/monotimes
import times, heapqueue, options


type
  TimerItem* = object
    finishAt*: MonoTime
    slot*: TimerEventList
    timeout*: Tick

  Timer* = object
    wheel*: TimerWheel
    queue*: HeapQueue[TimerItem]
    now*: MonoTime
    interval*: Tick


proc initTimerItem*(finishAt: MonoTime, slot: TimerEventList, timeout: Tick): TimerItem =
  TimerItem(finishAt: finishAt, slot: slot, timeout: timeout)

proc `<`*(x, y: TimerItem): bool =
  result = x.finishAt < y.finishAt

proc initTimer*(interval: Tick = 100): Timer =
  result.wheel = initTimerWheel()
  result.queue = initHeapQueue[TimerItem]()
  result.now = getMonoTime()
  result.interval = interval

proc add*(timer: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1): bool =
  result = false

  var evlist = timer.wheel.setTimer(event, timeout, repeatTimes)
  if evlist.isSome:
    timer.queue.push(initTimerItem(getMonoTime() + initDuration(
                     milliseconds = timeout * timer.interval), evlist.get,
                     timeout))

    result = true

proc process*(timer: var Timer): Option[int] = 
  var count = timer.queue.len
  let now = getMonoTime()

  while count > 0 and timer.queue[0].finishAt <= now:
    let item = timer.queue.pop
    timer.wheel.advance(item.timeout)
    dec count

  if timer.queue.len == 0:
    result = none(int)
  else:
    let millisecs = (timer.queue[0].finishAt - getMonoTime()).inMilliseconds
    result = some(millisecs.int + 1)
