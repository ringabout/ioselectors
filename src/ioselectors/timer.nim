import timerwheel
import std/monotimes
import times, heapqueue, options
import os


type
  TimerItem* = object
    finishAt*: MonoTime
    slot*: TimerEventList
    timeout*: Tick

  Timer* = object
    wheel*: TimerWheel
    queue*: HeapQueue[TimerItem]
    start*: MonoTime
    interval*: Tick ## Units is millisecs.


proc initTimerItem*(finishAt: MonoTime, slot: TimerEventList, timeout: Tick): TimerItem =
  TimerItem(finishAt: finishAt, slot: slot, timeout: timeout)

proc `<`*(x, y: TimerItem): bool =
  result = x.finishAt < y.finishAt

proc initTimer*(interval: Tick = 100): Timer =
  result.wheel = initTimerWheel()
  result.queue = initHeapQueue[TimerItem]()
  result.start = getMonoTime()
  result.interval = interval

proc add*(timer: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1): bool =
  result = false

  var evlist = timer.wheel.setTimer(event, timeout, repeatTimes)
  if evlist.isSome:
    let list = evlist.get
    if list.count == 1:
      timer.queue.push(initTimerItem(getMonoTime() + initDuration(
                       milliseconds = timeout * timer.interval), list,
                       timeout))

    result = true

proc process*(timer: var Timer): Option[int] = 
  var count = timer.queue.len
  let now = getMonoTime()

  while count > 0 and timer.queue[0].finishAt <= now:
    let item = timer.queue.pop
    if item.slot.data.head != nil:
      let timeout = 
        if item.slot.data.head.value.finishAt - timer.wheel.currentTime >= 0:
          item.slot.data.head.value.finishAt - timer.wheel.currentTime
        else:
          0
      timer.wheel.update(timeout)
    else:
      timer.wheel.update(item.timeout)
    dec count

  if timer.queue.len == 0:
    result = none(int)
  else:
    let millisecs = (timer.queue[0].finishAt - getMonoTime()).inMilliseconds
    result = some(millisecs.int + 1)

proc poll(timer: var Timer, timeout = 50) =
  sleep(timeout)
  discard process(timer)



when isMainModule:
  var t = initTimer(100)
  var count = 0
  var event0 = initTimerEvent(proc() = 
    inc count)


  var event1 = initTimerEvent(proc() = echo "first")
  var event2 = initTimerEvent(proc() = echo "second")


  discard t.add(event1, 10)
  discard t.add(event2, 1)

  poll(t, 100)
  discard t.add(event1, 9)
  echo t
  poll(t, 1000)


# echo t
# echo t.wheel.slotsToString(0)
# while t.wheel.taskCounter != 0:
#   poll(t, 1000)
#   echo t

# echo t
