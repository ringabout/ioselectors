import lists
import math


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
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]

  Scheduler* = object
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

proc processTimer*(s: var Scheduler, step: Tick) =
  var level = 0
  while step > s.timer.duration[level]:
    inc level

  var scheduleAt = s.timer.now[level]
  for i in 0 ..< step:
    let index = scheduleAt and mask
    for event in s.timer.slots[level][index]:
      event.cb()

    s.timer.slots[level][index].head = nil

    inc scheduleAt

  s.timer.now[level] = scheduleAt

var s = initScheduler()
var event = initTimerEvent(proc() = echo "Hello")

echo s.timer.duration
echo s.timer.now
s.setTimer(event, 0)
s.setTimer(event, 3)
s.setTimer(event, 5)
s.processTimer(6)
echo s.timer.slots[0]

