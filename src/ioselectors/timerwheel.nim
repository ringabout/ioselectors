import lists, options
import math


const
  widthBits {.intdefine.} = 4
  total {.intdefine.} = 16
  totalBits* = 1 shl total
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels* = total div widthBits
  numSlots = 1 shl widthBits
  mask* = numSlots - 1

static:
  doAssert isPowerOfTwo(widthBits)
  doAssert isPowerOfTwo(total)

type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt*: Tick
    timeout*: Tick
    scheduleAt*: uint8
    repeatTimes*: int
    cb*: Callback
    first*: bool

  TimerEventNode* = DoublyLinkedNode[TimerEvent]

  TimerEventList* = ref object
    data*: DoublyLinkedList[TimerEvent]
    count*: Tick

  TimerWheel* = object
    taskCounter*: Natural
    duration*: array[numLevels, Tick]
    currentTime*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]


proc initTimerWheel*(): TimerWheel =
  for level in 0 ..< numLevels:
    result.duration[level] = numSlots ^ (level + 1)

    for idx in 0 ..< numSlots:
      new result.slots[level][idx]

proc isActive*(s: TimerWheel): bool =
  s.taskCounter != 0

proc initTimerEvent*(cb: Callback): TimerEvent =
  TimerEvent(cb: cb)

proc `$`*(t: TimerEvent): string =
  $(t.finishAt, t.scheduleAt)

proc slotsToString*(t: TimerWheel, level: Tick): string =
  result = "["
  let slots = t.slots[level]
  for idx in 0 ..< numSlots - 1:
    result.add $(slots[idx][]) & ", "
  result.add $(slots[^1][])
  result.add "]"

proc isEmpty*(L: TimerEventList): bool =
  L.data.head == nil and L.data.tail == nil

proc clear*(L: TimerEventList) =
  L.data.head = nil
  L.data.tail = nil
  L.count = 0

proc append*(L: TimerEventList, ev: TimerEventNode) =
  L.data.append(ev)
  inc L.count

proc internalRemove*[T](L: var DoublyLinkedList[T], n: DoublyLinkedNode[T]): bool =
  result = false

  if n == L.tail: 
    L.tail = n.prev
    result = true

  if n == L.head: 
    L.head = n.next
    result = true

  if n.next != nil: 
    n.next.prev = n.prev
    result = true

  if n.prev != nil: 
    n.prev.next = n.next
    result = true

proc remove*(L: TimerEventList, ev: TimerEventNode): bool =
  result = L.data.internalRemove(ev)
  if result:
    dec L.count

iterator mitems*(L: TimerEventList): var TimerEvent =
  for item in L.data.mitems:
    yield item

iterator items*(L: TimerEventList): TimerEvent =
  for item in L.data.items:
    yield item

iterator nodes*(L: TimerEventList): TimerEventNode =
  for item in L.data.nodes:
    yield item

proc setTimer*(s: var TimerWheel, event: TimerEventNode) =
  ## Returns the number of TimerEvent in TimerEventList.
  if event.value.repeatTimes == 0:
    return

  # mod (2 ^ n - 1)
  var level = 0'u8
  # decide which level
  while event.value.timeout >= s.duration[level]:
    inc level

    if level >= numLevels.uint8:
      doAssert false, "Number is too large "

  event.value.finishAt = s.currentTime + event.value.timeout

  let scheduleAt = 
    if level == 0:
      event.value.finishAt and mask
    else:
      (s.now[level] + (event.value.timeout div s.duration[level - 1]) - 1) and mask

  event.value.scheduleAt = scheduleAt.uint8
  event.value.first = not s.slots[level][scheduleAt].count.bool

  s.slots[level][scheduleAt].append event
  inc s.taskCounter

proc setTimer*(s: var TimerWheel, event: var TimerEvent, 
               timeout: Tick, repeatTimes: int = 1): TimerEventNode =
  ## Returns the number of TimerEvent in TimerEventList.
  event.repeatTimes = repeatTimes
  event.timeout = timeout
  result = newDoublyLinkedNode(event)
  s.setTimer(result)

proc cancel*(s: var TimerWheel, eventNode: TimerEventNode) =
  # mod (2 ^ n - 1)
  var level = 0'u8
  # decide which level
  while eventNode.value.timeout >= s.duration[level]:
    inc level

    if level >= numLevels.uint8:
      doAssert false, "Number is too large "


  if s.slots[level][eventNode.value.scheduleAt].remove(eventNode):
    dec s.taskCounter

proc execute*(s: var TimerWheel, t: TimerEventNode) =
  if t.value.cb != nil:
    t.value.cb()

    if t.value.repeatTimes < 0:
      setTimer(s, t)
    elif t.value.repeatTimes >= 1:
      dec t.value.repeatTimes
      setTimer(s, t)

proc degrade*(s: var TimerWheel, hlevel: Tick) =
  let idx = s.now[hlevel] - 1

  if idx >= 0:
    for node in s.slots[hlevel][idx].nodes:
      discard s.slots[hlevel][idx].remove(node)
      if node.value.finishAt <= s.currentTime:
        s.execute(node)
      else:
        node.value.timeout = node.value.finishAt - s.currentTime
        s.setTimer(node)
      dec s.taskCounter

proc advance*(s: var TimerWheel, step: Tick) =
  for i in 0 ..< step:
    let idx = s.now[0]
    for node in s.slots[0][idx].nodes:
      s.execute(node)
      dec s.taskCounter

    s.slots[0][idx].clear()

    s.now[0] = (idx + 1) and mask

    var hlevel = 0

    while s.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      s.now[hlevel] = (s.now[hlevel] + 1) and mask
      degrade(s, hlevel)

    s.currentTime = (s.currentTime + 1) and (totalBits - 1)

proc update*(s: var TimerWheel, step: Tick) =
  for i in 0 ..< step:
    let idx = s.now[0]

    s.now[0] = (idx + 1) and mask

    var hlevel = 0

    while s.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      s.now[hlevel] = (s.now[hlevel] + 1) and mask
      degrade(s, hlevel)

    s.currentTime = (s.currentTime + 1) and (totalBits - 1)

  let idx = s.now[0]
  for node in s.slots[0][idx].nodes:
    s.execute(node)
    dec s.taskCounter

  s.slots[0][idx].clear()
