import lists
import math


const
  widthBits {.strdefine.} = 8
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels = 32 div widthBits
  numSlots = 1 shl widthBits
  mask = numSlots - 1

assert isPowerOfTwo(widthBits)

type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt*: Tick
    cb*: Callback

  TimerEventList* = DoublyLinkedRing[TimerEvent]

  Timer* = object
    interval*: array[numLevels, Tick]
    ticksPending*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]

  Scheduler* = object
    timer: Timer

proc initScheduler*(): Scheduler =
  for level in 0 ..< numLevels:
    result.timer.interval[level] = numSlots ^ (level + 1)

proc initTimerEvent*(finishAt: Tick, cb: Callback): TimerEvent =
  TimerEvent(finishAt: finishAt, cb: cb)

proc setTimer*(s: var Scheduler, event: TimerEvent, level = 0) =
  # mod (2 ^ n - 1)

  # decide which level


  let scheduleAt = (s.timer.now[level] + event.finishAt) and mask
  s.timer.slots[level][scheduleAt].append event

proc processTimer*(s: var Scheduler, step: Tick, level = 0) =
  var scheduleAt = s.timer.now[level]
  for i in 0 ..< step:
    for event in s.timer.slots[level][scheduleAt and mask]:
      event.cb()

    inc scheduleAt

  s.timer.now[level] = scheduleAt

echo initScheduler()