import timerwheel
import std/monotimes
import times, heapqueue, options
import os

# TODO 
import lists

type
  TimerItem* = object
    finishAt*: MonoTime
    finishTick*: Tick

  Timer* = object
    wheel*: TimerWheel
    queue*: HeapQueue[TimerItem]
    start*: MonoTime
    interval*: Tick ## Units is millisecs.


proc initTimerItem*(finishAt: MonoTime, finishTick: Tick): TimerItem =
  TimerItem(finishAt: finishAt, finishTick: finishTick)

proc `<`*(x, y: TimerItem): bool =
  result = x.finishAt < y.finishAt

proc initTimer*(interval: Tick = 100): Timer =
  result.wheel = initTimerWheel()
  result.queue = initHeapQueue[TimerItem]()
  result.start = getMonoTime()
  result.interval = interval

proc add*(timer: var Timer, event: TimerEventNode, timeout: Tick, 
          repeatTimes: int = 1) =

  timer.wheel.setTimer(event, timeout, repeatTimes)

  if event != nil:
    let event = event.value
    if event.repeatTimes != 0 and event.count == 0:
      timer.queue.push(initTimerItem(getMonoTime() + initDuration(
                       milliseconds = timeout * timer.interval),
                       timer.wheel.currentTime + timeout))

proc add*(timer: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1): TimerEventNode =

  result = newDoublyLinkedNode(event)
  timer.add(result, timeout, repeatTimes)

proc cancel*(s: var Timer, eventNode: TimerEventNode) =
  s.wheel.cancel(eventNode)

proc execute*(s: var Timer, t: TimerEventNode) =
  if t.value.cb != nil:
    t.value.cb()

    if t.value.repeatTimes < 0:
      add(s, t, t.value.timeout, -1)
    elif t.value.repeatTimes >= 1:
      dec t.value.repeatTimes
      add(s, t, t.value.timeout, t.value.repeatTimes)

proc update*(s: var Timer, step: Tick) =
  for i in 0 ..< step:
    let idx = s.wheel.now[0]


    s.wheel.now[0] = (idx + 1) and mask

    var hlevel = 0

    while s.wheel.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      s.wheel.now[hlevel] = (s.wheel.now[hlevel] + 1) and mask
      degrade(s.wheel, hlevel)

    s.wheel.currentTime = (s.wheel.currentTime + 1) and (totalBits - 1)


  let idx = s.wheel.now[0]
  for node in s.wheel.slots[0][idx].nodes:
    s.execute(node)
    dec s.wheel.taskCounter

  s.wheel.slots[0][idx].clear()

proc process*(timer: var Timer): Option[int] = 
  var count = timer.queue.len
  let now = getMonoTime()

  while count > 0 and timer.queue[0].finishAt <= now:
    let 
      item = timer.queue.pop
      distance = item.finishTick - timer.wheel.currentTime

    let timeout =
      if distance >= 0:
        distance
      else:
        0

    timer.update(timeout)
    dec count

  if timer.queue.len == 0:
    result = none(int)
  else:
    let millisecs = (timer.queue[0].finishAt - getMonoTime()).inMilliseconds
    result = some(millisecs.int + 1)

proc poll(timer: var Timer, timeout = 50) =
  sleep(timeout)
  discard process(timer)
