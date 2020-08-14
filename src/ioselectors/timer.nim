import timerwheel
import std/monotimes
import times, heapqueue, options
import os


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

proc add*(timer: var Timer, event: var TimerEvent, timeout: Tick, 
          repeatTimes: int = 1): bool =
  result = false

  let eventNode = timer.wheel.setTimer(event, timeout, repeatTimes)
  if eventNode.isSome:
    let event = eventNode.get.value
    if event.count == 0:
      timer.queue.push(initTimerItem(getMonoTime() + initDuration(
                       milliseconds = timeout * timer.interval),
                       timer.wheel.currentTime + timeout))

    result = true

proc cancel*(s: var Timer, eventNode: TimerEventNode) =
  s.wheel.cancel(eventNode)

proc execute*(s: var Timer, t: var TimerEvent) =
  if t.cb != nil:
    t.cb()

    if t.repeatTimes < 0:
      discard add(s, t, t.timeout, -1)
    elif t.repeatTimes >= 1:
      discard add(s, t, t.timeout, t.repeatTimes - 1)

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
  for event in s.wheel.slots[0][idx].mitems:
    s.execute(event)
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



when isMainModule:
  block:
    var t = initTimer(100)
    var count = 0
    var event0 = initTimerEvent(proc() = 
      inc count)


    var event1 = initTimerEvent(proc() = echo "first")
    var event2 = initTimerEvent(proc() = echo "second")

    discard t.add(event1, 10)
    discard t.add(event2, 1)

    poll(t, 100)
    discard t.add(event0, 5)

    discard t.add(event1, 9)
    echo t
    poll(t, 1000)
    doAssert count == 1, $count
    discard t.add(event0, 2)

    poll(t, 200)
    doAssert count == 2, $count

  # block:
  #   var t = initTimer(1)
  #   var count = 0
  #   var event0 = initTimerEvent(proc() = 
  #     inc count)


  #   var event1 = initTimerEvent(proc() = echo "first")
  #   var event2 = initTimerEvent(proc() = echo "second")

  #   discard t.add(event1, 2, -1)
  #   while true:
  #     echo t
  #     # echo t.wheel.slotsToString(0)
  #     poll(t, 2)



# echo t
# echo t.wheel.slotsToString(0)
# while t.wheel.taskCounter != 0:
#   poll(t, 1000)
#   echo t

# echo t
