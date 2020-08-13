import lists
import math


const
  widthBits {.intdefine.} = 4
  total {.intdefine.} = 16
  totalBits = 1 shl total
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels = total div widthBits
  numSlots = 1 shl widthBits
  mask = numSlots - 1

static:
  doAssert isPowerOfTwo(widthBits)
  doAssert isPowerOfTwo(total)

type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt: Tick
    timeout: Tick
    repeatTimes: int
    cb*: Callback

  TimerEventList* = DoublyLinkedList[TimerEvent]

  Timer* = object
    duration*: array[numLevels, Tick]
    currentTime*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]

  Scheduler* = object
    taskCounter: Natural
    timer: Timer

proc initScheduler*(): Scheduler =
  for level in 0 ..< numLevels:
    result.timer.duration[level] = numSlots ^ (level + 1)

proc isActive*(s: Scheduler): bool =
  s.taskCounter != 0

proc initTimerEvent*(cb: Callback): TimerEvent =
  TimerEvent(cb: cb)

proc `$`*(t: TimerEvent): string =
  $(t.finishAt, )

proc reset(L: var DoublyLinkedList) =
  L.head = nil
  L.tail = nil

# proc cancel*(t: var TimerEvent) =
#   t.cb = nil

proc setTimer*(s: var Scheduler, event: var TimerEvent, timeout: Tick, repeatTimes: int = 1) =
  if repeatTimes == 0:
    # TODO return bool
    return

  # mod (2 ^ n - 1)
  var level = 0
  # decide which level
  while timeout >= s.timer.duration[level]:
    inc level

    if level >= numLevels:
      doAssert false, "Number is too large "

  event.repeatTimes = repeatTimes
  event.timeout = timeout
  event.finishAt = s.timer.currentTime + timeout

  let scheduleAt = 
    if level == 0:
      event.finishAt and mask
    else:
      (s.timer.now[level] + (timeout div s.timer.duration[level - 1]) - 1) and mask

  s.timer.slots[level][scheduleAt].append event
  inc s.taskCounter

proc execute*(s: var Scheduler, t: var TimerEvent) =
  if t.cb != nil:
    t.cb()

    if t.repeatTimes < 0:
      setTimer(s, t, t.timeout, -1)
    elif t.repeatTimes >= 1:
      setTimer(s, t, t.timeout, t.repeatTimes - 1)

proc degradeTimer*(s: var Scheduler, hlevel: Tick) =
  let idx = s.timer.now[hlevel] - 1

  if idx >= 0:
    for event in s.timer.slots[hlevel][idx].mitems:
      if event.finishAt <= s.timer.currentTime:
        s.execute(event)
      else:
        s.setTimer(event, event.finishAt - s.timer.currentTime)
      dec s.taskCounter
    s.timer.slots[hlevel][idx].reset()

proc processTimer*(s: var Scheduler, step: Tick) =
  # if s.taskCounter > 0:
  for i in 0 ..< step:
    let idx = s.timer.now[0]
    for event in s.timer.slots[0][idx].mitems:
      s.execute(event)
      dec s.taskCounter

    s.timer.slots[0][idx].reset()

    s.timer.now[0] = (idx + 1) and mask

    var hlevel = 0

    while s.timer.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      s.timer.now[hlevel] = (s.timer.now[hlevel] + 1) and mask
      degradeTimer(s, hlevel)

    s.timer.currentTime = (s.timer.currentTime + 1) and (totalBits - 1)
