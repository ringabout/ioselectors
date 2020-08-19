import timerwheel
import std/monotimes
import times, heapqueue, options
import os, lists


export lists, options


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

proc add*(timer: var Timer, event: TimerEventNode) =

  if event != nil:
    timer.wheel.setTimer(event)
    let count = timer.wheel.slots[event.value.level][event.value.scheduleAt].count
    if event.value.repeatTimes != 0 and count == 1:
      timer.queue.push(initTimerItem(getMonoTime() + initDuration(
                       milliseconds = (event.value.finishAt - timer.wheel.currentTime) * timer.interval),
                        event.value.finishAt))

proc add*(timer: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1): TimerEventNode =
  result = setupTimerEvent(timer.wheel, event, timeout, repeatTimes)
  timer.add(result)

proc cancel*(s: var Timer, eventNode: TimerEventNode) =
  s.wheel.cancel(eventNode)

proc execute*(s: var Timer, t: TimerEventNode) =
  if t.value.cb != nil:
    t.value.cb()

    if t.value.repeatTimes < 0:
      updateTimerEventNode(s.wheel, t)
      add(s, t)
    elif t.value.repeatTimes >= 1:
      dec t.value.repeatTimes
      updateTimerEventNode(s.wheel, t)
      add(s, t)

proc update*(s: var Timer, step: Tick) =
  run(s.wheel, step, false, false)

  # Uses our own executor.
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
