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
    originTimeout*: Tick
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
  $(t.finishAt, t.timeout, t.originTimeout)

proc slotsToString*(t: TimerWheel, level: Tick): string =
  result = "["
  let slots = t.slots[level]
  for idx in 0 ..< numSlots - 1:
    result.add $(slots[idx][]) & ", "
  result.add $(slots[^1][])
  result.add "]"

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

template scheduleWhere(
  s: var TimerWheel, eventNode: TimerEventNode
): tuple[level: int, scheduleAt: int] =

  # mod (2 ^ n - 1)
  var level = 0
  # decide which level
  while eventNode.value.timeout >= s.duration[level]:
    inc level

    if level >= numLevels:
      doAssert false, "Number is too large "

  # TODO This is wrong
  if level == 0:
    (level, eventNode.value.finishAt and mask)
  else:
    (level, (eventNode.value.finishAt div s.duration[level - 1] - 1) and mask)

proc setTimer*(s: var TimerWheel, eventNode: TimerEventNode, level, scheduleAt: Tick) =
  if eventNode.value.repeatTimes == 0:
    return

  eventNode.value.first = not s.slots[level][scheduleAt].count.bool

  s.slots[level][scheduleAt].append eventNode
  inc s.taskCounter

template setupTimerEvent*(s: var TimerWheel, event: var TimerEvent, 
               timeout: Tick, repeatTimes: int): TimerEventNode =
  event.repeatTimes = repeatTimes
  event.timeout = timeout
  event.finishAt = s.currentTime + event.timeout
  event.originTimeout = timeout
  newDoublyLinkedNode(event)

template updateTimerEventNode*(s: var TimerWheel, eventNode: TimerEventNode) =
  t.value.timeout = t.value.originTimeout
  t.value.finishAt = s.currentTime + t.value.timeout

proc setTimer*(s: var TimerWheel, eventNode: TimerEventNode) =
  ## Returns the number of TimerEvent in TimerEventList.

  let (level, scheduleAt) = scheduleWhere(s, eventNode)
  s.setTimer(eventNode, level, scheduleAt)

proc setTimer*(s: var TimerWheel, event: var TimerEvent, 
               timeout: Tick, repeatTimes: int = 1): TimerEventNode =
  ## Returns the number of TimerEvent in TimerEventList.
  result = setupTimerEvent(s, event, timeout, repeatTimes)
  s.setTimer(result)

proc cancel*(s: var TimerWheel, eventNode: TimerEventNode) =
  let (level, scheduleAt) = scheduleWhere(s, eventNode)

  if s.slots[level][scheduleAt].remove(eventNode):
    dec s.taskCounter

proc execute*(s: var TimerWheel, t: TimerEventNode) =
  if t.value.cb != nil:
    t.value.cb()

    if t.value.repeatTimes < 0:
      updateTimerEventNode(s, t)
      setTimer(s, t)
    elif t.value.repeatTimes >= 1:
      dec t.value.repeatTimes
      updateTimerEventNode(s, t)
      setTimer(s, t)

proc degrade*(s: var TimerWheel, hlevel: Tick) =
  let idx = s.now[hlevel]

  let nodes = move s.slots[hlevel][idx]
  new s.slots[hlevel][idx]

  for node in nodes.nodes:
    # discard s.slots[hlevel][idx].remove(node)
    if node.value.finishAt <= s.currentTime:
      s.execute(node)
    else:
      node.value.timeout = (node.value.finishAt - s.currentTime)

      # 16 -> 31
      # run 15 -> get 16
      var prevLevel = hlevel - 1
      var flag = false

      while prevLevel >= 0:
        if node.value.timeout == s.duration[prevLevel]:
          flag = true
          break
      
        dec prevLevel

      if flag:
        s.setTimer(node, hlevel, s.now[hlevel] + 1)
      else:
        s.setTimer(node)

    dec s.taskCounter
  
  s.now[hlevel] = (s.now[hlevel] + 1) and mask


template run*(s: var TimerWheel, step: Tick, all = true, tail = true) =
  for i in 0 ..< step:
    let idx = s.now[0]

    when all:
      for node in s.slots[0][idx].nodes:
        s.execute(node)
        dec s.taskCounter

    s.slots[0][idx].clear()
    s.now[0] = (idx + 1) and mask
    s.currentTime = (s.currentTime + 1) and (totalBits - 1)

    var hlevel = 0

    while s.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      degrade(s, hlevel)


  when tail:
    let idx = s.now[0]
    for node in s.slots[0][idx].nodes:
      s.execute(node)
      dec s.taskCounter

    s.slots[0][idx].clear()

proc advance*(s: var TimerWheel, step: Tick) =
  run(s, step, true, true)

proc update*(s: var TimerWheel, step: Tick) =
  run(s, step, false, true)
