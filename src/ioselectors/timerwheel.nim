import lists
import math

import sugar


const
  widthBits {.strdefine.} = 4
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels = 16 div widthBits
  numSlots = 1 shl widthBits
  mask = numSlots - 1

assert isPowerOfTwo(widthBits)

type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt: Tick
    cb*: Callback

  TimerEventList* = DoublyLinkedRing[TimerEvent]

  Timer* = object
    duration*: array[numLevels, Tick]
    ticksPending*: Tick
    currentTime*: Tick
    now*: array[numLevels, Tick]
    bits*: uint32
    slots*: array[numLevels, array[numSlots, TimerEventList]]

  Scheduler* = object
    taskCounter: Natural
    timer: Timer

proc initScheduler*(): Scheduler =
  for level in 0 ..< numLevels:
    result.timer.duration[level] = numSlots ^  (level + 1)

proc initTimerEvent*(cb: Callback): TimerEvent =
  TimerEvent(cb: cb)

proc setTimer*(s: var Scheduler, event: var TimerEvent, timeout: Tick) =
  # mod (2 ^ n - 1)
  var level = 0
  # decide which level
  while timeout > s.timer.duration[level]:
    inc level

  if level > numLevels:
    return

  event.finishAt = s.timer.now[level] + timeout

  let scheduleAt = 
    if level == 0:
      event.finishAt and mask
    else:
      (s.timer.now[level] + timeout div s.timer.duration[level - 1] - 1) and mask


  s.timer.slots[level][scheduleAt].append event
  inc s.taskCounter

proc degradeTimer*(s: var Scheduler, hlevel: Tick) =
  let idx = s.timer.now[hlevel] - 1
  for event in s.timer.slots[hlevel][idx].mitems:
    if event.finishAt <= s.timer.currentTime:
      event.cb()
    s.setTimer(event, event.finishAt - s.timer.currentTime)
  s.timer.slots[hlevel][idx].head = nil

proc processTimer*(s: var Scheduler, step: Tick) =
  let level = 0

  var scheduleAt = s.timer.now[level]
  inc(s.timer.currentTime, step)

  if s.taskCounter > 0:
    for i in 0 ..< step:
      let index = scheduleAt and mask
      for event in s.timer.slots[level][index]:
        event.cb()
        dec s.taskCounter

      s.timer.slots[level][index].head = nil

      scheduleAt = (scheduleAt + 1) and mask

      var hlevel = level + 1
      if scheduleAt == 0 and hlevel < numLevels - 1:
        inc s.timer.now[hlevel]
        degradeTimer(s, hlevel)
        while s.timer.now[hlevel] == 0 and hlevel < numLevels - 1:
          inc hlevel
          degradeTimer(s, hlevel)
          inc s.timer.now[hlevel]

  s.timer.now[level] = scheduleAt


when isMainModule:
  var s = initScheduler()
  var event = initTimerEvent(proc() = echo "first")
  var event2 = initTimerEvent(proc() = echo "second")

  echo s.timer.duration
  echo s.timer.now
  s.setTimer(event, 0)
  s.setTimer(event, 3)
  s.setTimer(event, 7)
  s.setTimer(event2, 18)
  s.setTimer(event2, 19)
  s.setTimer(event2, 28)
  s.setTimer(event2, 29)
  s.setTimer(event2, 37)
  s.setTimer(event2, 62)
  echo s.timer.slots
  s.processTimer(17)
  s.processTimer(4)
  echo s.timer.slots
