#            Nim's Runtime Library
#        (c) Copyright 2016 Eugene Kabanov


#            IO selectors
#        (c) Copyright 2020 Zeshen Xing


import wepoll, os, winlean
import nativesockets

import strutils


export wepoll


when hasThreadSupport:
  type
    SelectorImpl[T] = object
      epollFD: EpollHandle
      maxFD: int
      numFD: int
      fds*: ptr SharedArray[SelectorKey[T]]
      count: int
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      epollFD: EpollHandle
      numFD: int
      fds*: seq[SelectorKey[T]]
      count: int
    Selector*[T] = ref SelectorImpl[T]

type
  SelectEventImpl = object
    efd: EpollEvent
  SelectEvent* = SelectEventImpl

proc newSelector*[T](): Selector[T] =
  # Start with a reasonable size, checkFd() will grow this on demand
  const numFD = 1024

  var epollFD = epoll_create1(0)

  if epollFD == nil:
    raiseOSError(osLastError())

  when hasThreadSupport:
    result = cast[Selector[T]](allocShared0(sizeof(SelectorImpl[T])))
    result.epollFD = epollFD
    result.numFD = numFD
    result.fds = allocSharedArray[SelectorKey[T]](numFD)
  else:
    result = Selector[T]()
    result.epollFD = epollFD
    result.numFD = numFD
    result.fds = newSeq[SelectorKey[T]](numFD)

  for i in 0 ..< numFD:
    result.fds[i].ident = InvalidIdent

proc close*[T](s: Selector[T]) =
  let res = epoll_close(s.epollFD)
  when hasThreadSupport:
    # deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
  
  if res != 0:
    raiseIOSelectorsError(osLastError())

proc newSelectEvent*(): SelectEvent =
  discard
  # result = EpollEvent(events: 0, data: EpollData(u64: 0))

template setKey(s, pident, pevents, pparam, pdata: untyped) =
  var skey = addr(s.fds[pident])
  skey.ident = pident
  skey.events = pevents
  skey.param = pparam
  skey.data = pdata

template clearKey[T](key: ptr SelectorKey[T]) =
  var empty: T
  key.ident = InvalidIdent
  key.events = {}
  key.data = empty

proc changeFd*(s: SocketHandle|int|cint): int {.inline.} =
  result = s.int shr 2

proc restoreFd*(s: SocketHandle|int|cint): int {.inline.} =
  result = s.int shl 2

proc contains*[T](s: Selector[T], fd: SocketHandle|int): bool {.inline.} =
  result = s.fds[fd.changeFd].ident != InvalidIdent

proc registerHandle*[T](s: Selector[T], socket: SocketHandle, events: set[Event], data: T) =
  let fd = socket.changeFd.cint
  s.checkFd(fd)
  doAssert(s.fds[fd].ident == InvalidIdent, "Descriptor $# already registered" % $fd)
  s.setKey(fd, events, 0, data)
  if events != {}:
    var epv = EpollEvent(events: EPOLLRDHUP.uint32)
    epv.data.fd = fd
    if Event.Read in events: epv.events = epv.events or EPOLLIN.uint32
    if Event.Write in events: epv.events = epv.events or EPOLLOUT.uint32
    if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, EpollSocket(socket), addr epv) != 0:
      raiseIOSelectorsError(osLastError())
    inc(s.count)

proc updateHandle*[T](s: Selector[T], socket: int | SocketHandle, events: set[Event]) =
  let maskEvents = {Event.Timer, Event.Signal, Event.Process, Event.Vnode,
                    Event.User, Event.Oneshot, Event.Error}
  let fd = socket.changeFd.cint
  s.checkFd(fd)
  var pkey = addr(s.fds[fd])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the selector!" % $fd)
  doAssert(pkey.events * maskEvents == {})
  if pkey.events != events:
    var epv = EpollEvent(events: EPOLLRDHUP.uint32)
    epv.data.fd = fd

    if Event.Read in events: epv.events = epv.events or EPOLLIN.uint32
    if Event.Write in events: epv.events = epv.events or EPOLLOUT.uint32

    if pkey.events == {}:
      if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, EpollSocket(socket), addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      inc(s.count)
    else:
      if events != {}:
        if epoll_ctl(s.epollFD, EPOLL_CTL_MOD, EpollSocket(socket), addr epv) != 0:
          raiseIOSelectorsError(osLastError())
      else:
        if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, EpollSocket(socket), addr epv) != 0:
          raiseIOSelectorsError(osLastError())
        dec(s.count)
    pkey.events = events

proc unregister*[T](s: Selector[T], socket: int|SocketHandle) =
  let fd = socket.changeFd
  s.checkFd(fd)
  var pkey = addr(s.fds[fd])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the selector!" % $fd)
  if pkey.events != {}:
    if Event.Read in pkey.events or Event.Write in pkey.events or Event.User in pkey.events:
      var epv = EpollEvent()
      if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, EpollSocket(socket), addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      dec(s.count)

  clearKey(pkey)

template checkFd*(s, f) =
  if f >= s.numFD:
    var numFD = s.numFD
    while numFD <= f: numFD *= 2
    when hasThreadSupport:
      s.fds = reallocSharedArray(s.fds, numFD)
    else:
      s.fds.setLen(numFD)
    for i in s.numFD ..< numFD:
      s.fds[i].ident = InvalidIdent
    s.numFD = numFD

const MAX_EPOLL_EVENTS = 64

proc selectInto*[T](s: Selector[T], timeout: int,
                    results: var openArray[ReadyKey]): int =

  var
    resTable: array[MAX_EPOLL_EVENTS, EpollEvent]
    maxres = MAX_EPOLL_EVENTS

  if maxres > len(results):
    maxres = len(results)

  # verifySelectParams(timeout)

  let count = epoll_wait(s.epollFD, addr(resTable[0]), maxres.cint,
                         timeout.cint)


  if count < 0:
    raiseIOSelectorsError(osLastError())
  elif count == 0:
    result = 0
  else:
    var idx = 0
    var k = 0
    while idx < count:
      let fd = resTable[idx].data.fd
      let pevents = resTable[idx].events
      let fevents = s.fds[fd].events
      var rkey = ReadyKey(fd: fd.restoreFd, events: {})

      if (pevents and EPOLLOUT.uint32) != 0:
        rkey.events.incl(Event.Write)

      if (pevents and EPOLLIN.uint32) != 0:
        if Event.Read in fevents:
          rkey.events.incl(Event.Read)

      results[k] = rkey
      inc idx
      inc k
    result = count


proc getData*[T](s: Selector[T], fd: SocketHandle|int): var T {.inline.} =
  let fdi = fd.int
  s.checkFd(fdi)
  if fdi in s:
    result = s.fds[fdi shr 2].data
