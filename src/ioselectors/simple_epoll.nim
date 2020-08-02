import posix, winlean


import times

# Maximum number of events that can be returned
const MAX_EPOLL_EVENTS = 64

proc eventfd(count: cuint, flags: cint): cint
     {.cdecl, importc: "eventfd", header: "<sys/eventfd.h>".}


when hasThreadSupport:
  type
    SelectorImpl[T] = object
      epollFD: cint
      maxFD: int
      numFD: int
      fds: ptr SharedArray[SelectorKey[T]]
      count: int
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      epollFD: cint
      maxFD: int
      numFD: int
      fds: seq[SelectorKey[T]]
      count: int
    Selector*[T] = ref SelectorImpl[T]
type
  SelectEventImpl = object
    efd: cint
  SelectEvent* = ptr SelectEventImpl

proc newSelector*[T](): Selector[T] =
  # Retrieve the maximum fd count (for current OS) via getrlimit()
  var a = RLimit()
  if getrlimit(posix.RLIMIT_NOFILE, a) != 0:
    raiseOSError(osLastError())
  var maxFD = int(a.rlim_max)
  doAssert(maxFD > 0)
  # Start with a reasonable size, checkFd() will grow this on demand
  const numFD = 1024

  var epollFD = epoll_create1(O_CLOEXEC)
  if epollFD < 0:
    raiseOSError(osLastError())

  when hasThreadSupport:
    result = cast[Selector[T]](allocShared0(sizeof(SelectorImpl[T])))
    result.epollFD = epollFD
    result.maxFD = maxFD
    result.numFD = numFD
    result.fds = allocSharedArray[SelectorKey[T]](numFD)
  else:
    result = Selector[T]()
    result.epollFD = epollFD
    result.maxFD = maxFD
    result.numFD = numFD
    result.fds = newSeq[SelectorKey[T]](numFD)

  for i in 0 ..< numFD:
    result.fds[i].ident = InvalidIdent

proc close*[T](s: Selector[T]) =
  let res = posix.close(s.epollFD)
  when hasThreadSupport:
    deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
  if res != 0:
    raiseIOSelectorsError(osLastError())

proc newSelectEvent*(): SelectEvent =
  let fdci = eventfd(0, O_CLOEXEC or O_NONBLOCK)
  if fdci == -1:
    raiseIOSelectorsError(osLastError())
  result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
  result.efd = fdci

proc trigger*(ev: SelectEvent) =
  var data: uint64 = 1
  if posix.write(ev.efd, addr data, sizeof(uint64)) == -1:
    raiseIOSelectorsError(osLastError())

proc close*(ev: SelectEvent) =
  let res = posix.close(ev.efd)
  deallocShared(cast[pointer](ev))
  if res != 0:
    raiseIOSelectorsError(osLastError())

template checkFd(s, f) =
  # TODO: I don't see how this can ever happen. You won't be able to create an
  # FD if there is too many. -- DP
  if f >= s.maxFD:
    raiseIOSelectorsError("Maximum number of descriptors is exhausted!")
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

proc registerHandle*[T](s: Selector[T], fd: int | SocketHandle,
                        events: set[Event], data: T) =
  let fdi = int(fd)
  s.checkFd(fdi)
  doAssert(s.fds[fdi].ident == InvalidIdent, "Descriptor $# already registered" % $fdi)
  s.setKey(fdi, events, 0, data)
  if events != {}:
    var epv = EpollEvent(events: EPOLLRDHUP)
    epv.data.u64 = fdi.uint
    if Event.Read in events: epv.events = epv.events or EPOLLIN
    if Event.Write in events: epv.events = epv.events or EPOLLOUT
    if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, fdi.cint, addr epv) != 0:
      raiseIOSelectorsError(osLastError())
    inc(s.count)

proc updateHandle*[T](s: Selector[T], fd: int | SocketHandle, events: set[Event]) =
  let maskEvents = {Event.Timer, Event.Signal, Event.Process, Event.Vnode,
                    Event.User, Event.Oneshot, Event.Error}
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the selector!" % $fdi)
  doAssert(pkey.events * maskEvents == {})
  if pkey.events != events:
    var epv = EpollEvent(events: EPOLLRDHUP)
    epv.data.u64 = fdi.uint

    if Event.Read in events: epv.events = epv.events or EPOLLIN
    if Event.Write in events: epv.events = epv.events or EPOLLOUT

    if pkey.events == {}:
      if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, fdi.cint, addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      inc(s.count)
    else:
      if events != {}:
        if epoll_ctl(s.epollFD, EPOLL_CTL_MOD, fdi.cint, addr epv) != 0:
          raiseIOSelectorsError(osLastError())
      else:
        if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
          raiseIOSelectorsError(osLastError())
        dec(s.count)
    pkey.events = events

proc unregister*[T](s: Selector[T], fd: int|SocketHandle) =
  let fdi = int(fd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the selector!" % $fdi)
  if pkey.events != {}:
    if Event.Read in pkey.events or Event.Write in pkey.events or Event.User in pkey.events:
      var epv = EpollEvent()
      # TODO: Refactor all these EPOLL_CTL_DEL + dec(s.count) into a proc.
      if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      dec(s.count)
    elif Event.Timer in pkey.events:
      if Event.Finished notin pkey.events:
        var epv = EpollEvent()
        if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
          raiseIOSelectorsError(osLastError())
        dec(s.count)
      if posix.close(cint(fdi)) != 0:
        raiseIOSelectorsError(osLastError())
    elif Event.Signal in pkey.events:
      var epv = EpollEvent()
      if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      var nmask, omask: Sigset
      discard sigemptyset(nmask)
      discard sigemptyset(omask)
      discard sigaddset(nmask, cint(s.fds[fdi].param))
      unblockSignals(nmask, omask)
      dec(s.count)
      if posix.close(cint(fdi)) != 0:
        raiseIOSelectorsError(osLastError())
    elif Event.Process in pkey.events:
      if Event.Finished notin pkey.events:
        var epv = EpollEvent()
        if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
          raiseIOSelectorsError(osLastError())
        var nmask, omask: Sigset
        discard sigemptyset(nmask)
        discard sigemptyset(omask)
        discard sigaddset(nmask, SIGCHLD)
        unblockSignals(nmask, omask)
        dec(s.count)
      if posix.close(cint(fdi)) != 0:
        raiseIOSelectorsError(osLastError())

  clearKey(pkey)

proc unregister*[T](s: Selector[T], ev: SelectEvent) =
  let fdi = int(ev.efd)
  s.checkFd(fdi)
  var pkey = addr(s.fds[fdi])
  doAssert(pkey.ident != InvalidIdent, "Event is not registered in the queue!")
  doAssert(Event.User in pkey.events)
  var epv = EpollEvent()
  if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, fdi.cint, addr epv) != 0:
    raiseIOSelectorsError(osLastError())
  dec(s.count)
  clearKey(pkey)

proc registerEvent*[T](s: Selector[T], ev: SelectEvent, data: T) =
  let fdi = int(ev.efd)
  doAssert(s.fds[fdi].ident == InvalidIdent, "Event is already registered in the queue!")
  s.setKey(fdi, {Event.User}, 0, data)
  var epv = EpollEvent(events: EPOLLIN or EPOLLRDHUP)
  epv.data.u64 = ev.efd.uint
  if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, ev.efd, addr epv) != 0:
    raiseIOSelectorsError(osLastError())
  inc(s.count)

proc selectInto*[T](s: Selector[T], timeout: int,
                    results: var openArray[ReadyKey]): int =
  var
    resTable: array[MAX_EPOLL_EVENTS, EpollEvent]
    maxres = MAX_EPOLL_EVENTS
    i, k: int

  if maxres > len(results):
    maxres = len(results)

  verifySelectParams(timeout)

  let count = epoll_wait(s.epollFD, addr(resTable[0]), maxres.cint,
                         timeout.cint)
  if count < 0:
    result = 0
    let err = osLastError()
    if cint(err) != EINTR:
      raiseIOSelectorsError(err)
  elif count == 0:
    result = 0
  else:
    i = 0
    k = 0
    while i < count:
      let fdi = int(resTable[i].data.u64)
      let pevents = resTable[i].events
      var pkey = addr(s.fds[fdi])
      doAssert(pkey.ident != InvalidIdent)
      var rkey = ReadyKey(fd: fdi, events: {})

      if (pevents and EPOLLERR) != 0 or (pevents and EPOLLHUP) != 0:
        if (pevents and EPOLLHUP) != 0:
          rkey.errorCode = OSErrorCode ECONNRESET
        else:
          # Try reading SO_ERROR from fd.
          var error: cint
          var size = SockLen sizeof(error)
          if getsockopt(SocketHandle fdi, SOL_SOCKET, SO_ERROR, addr(error),
                        addr(size)) == 0'i32:
            rkey.errorCode = OSErrorCode error
        rkey.events.incl(Event.Error)

      if (pevents and EPOLLOUT) != 0:
        rkey.events.incl(Event.Write)

      if (pevents and EPOLLIN) != 0:
        if Event.Read in pkey.events:
          rkey.events.incl(Event.Read)
        elif Event.Timer in pkey.events:
          var data: uint64 = 0
          if posix.read(cint(fdi), addr data,
                        sizeof(uint64)) != sizeof(uint64):
            raiseIOSelectorsError(osLastError())
          rkey.events.incl(Event.Timer)
        elif Event.Signal in pkey.events:
          var data = SignalFdInfo()
          if posix.read(cint(fdi), addr data,
                        sizeof(SignalFdInfo)) != sizeof(SignalFdInfo):
            raiseIOSelectorsError(osLastError())
          rkey.events.incl(Event.Signal)
        elif Event.Process in pkey.events:
          var data = SignalFdInfo()
          if posix.read(cint(fdi), addr data,
                        sizeof(SignalFdInfo)) != sizeof(SignalFdInfo):
            raiseIOSelectorsError(osLastError())
          if cast[int](data.ssi_pid) == pkey.param:
            rkey.events.incl(Event.Process)
          else:
            inc(i)
            continue
        elif Event.User in pkey.events:
          var data: uint64 = 0
          if posix.read(cint(fdi), addr data,
                        sizeof(uint64)) != sizeof(uint64):
            let err = osLastError()
            if err == OSErrorCode(EAGAIN):
              inc(i)
              continue
            else:
              raiseIOSelectorsError(err)
          rkey.events.incl(Event.User)

      if Event.Oneshot in pkey.events:
        var epv = EpollEvent()
        if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, cint(fdi), addr epv) != 0:
          raiseIOSelectorsError(osLastError())
        # we will not clear key until it will be unregistered, so
        # application can obtain data, but we will decrease counter,
        # because epoll is empty.
        dec(s.count)
        # we are marking key with `Finished` event, to avoid double decrease.
        pkey.events.incl(Event.Finished)

      results[k] = rkey
      inc(k)
      inc(i)
    result = k

proc select*[T](s: Selector[T], timeout: int): seq[ReadyKey] =
  result = newSeq[ReadyKey](MAX_EPOLL_EVENTS)
  let count = selectInto(s, timeout, result)
  result.setLen(count)

template isEmpty*[T](s: Selector[T]): bool =
  (s.count == 0)

proc contains*[T](s: Selector[T], fd: SocketHandle|int): bool {.inline.} =
  return s.fds[fd.int].ident != InvalidIdent

proc getData*[T](s: Selector[T], fd: SocketHandle|int): var T =
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    result = s.fds[fdi].data

proc setData*[T](s: Selector[T], fd: SocketHandle|int, data: T): bool =
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    s.fds[fdi].data = data
    result = true

template withData*[T](s: Selector[T], fd: SocketHandle|int, value,
                        body: untyped) =
  mixin checkFd
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    var value = addr(s.getData(fdi))
    body

template withData*[T](s: Selector[T], fd: SocketHandle|int, value, body1,
                        body2: untyped) =
  mixin checkFd
  let fdi = int(fd)
  s.checkFd(fdi)
  if fdi in s:
    var value = addr(s.getData(fdi))
    body1
  else:
    body2

proc getFd*[T](s: Selector[T]): int =
  return s.epollFd.int
