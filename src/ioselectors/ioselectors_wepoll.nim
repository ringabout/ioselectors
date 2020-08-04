#            IO selectors
#        (c) Copyright 2020 Zeshen Xing


import wepoll, os, winlean
import nativesockets

import strutils


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
  let event = EpollEvent(events: 0, data: EpollData(u64: 0))

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

proc changeFd*(s: SocketHandle|int|cint): int =
  result = s.int shr 2

proc restoreFd*(s: SocketHandle|int|cint): int =
  result = s.int shl 2

proc contains*[T](s: Selector[T], fd: SocketHandle|int): bool {.inline.} =
  result = s.fds[fd.changeFd].ident != InvalidIdent


# proc registerHandle*[T](s: Selector[T], fd: int | SocketHandle,
#                         events: set[Event], data: T) =
#   let fdi = int(fd)
#   s.checkFd(fdi)
#   doAssert(s.fds[fdi].ident == InvalidIdent, "Descriptor $# already registered" % $fdi)
#   s.setKey(fdi, events, 0, data)
#   if events != {}:
#     var epv = EpollEvent(events: EPOLLRDHUP)
#     epv.data.u64 = fdi.uint
#     if Event.Read in events: epv.events = epv.events or EPOLLIN
#     if Event.Write in events: epv.events = epv.events or EPOLLOUT
#     if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, fdi.cint, addr epv) != 0:
#       raiseIOSelectorsError(osLastError())
#     inc(s.count)

proc registerHandle*[T](s: Selector[T], socket: SocketHandle, events: set[Event], data: T) =

  # epoll_ctl*(ephnd: EpollHandle; op: cint; 
  #            sock: SOCKET; event: ptr epoll_event): cint
  let fd = socket.changeFd.cint
  s.checkFd(fd)
  doAssert(s.fds[fd].ident == InvalidIdent, "Descriptor $# already registered" % $fd)
  s.setKey(fd, events, 0, data)
  echo "Register: ", s.fds[fd].repr
  if events != {}:
    var epv = EpollEvent(events: EPOLLRDHUP.uint32)
    epv.data.fd = fd
    if Event.Read in events: epv.events = epv.events or EPOLLIN.uint32
    if Event.Write in events: epv.events = epv.events or EPOLLOUT.uint32
    if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, EpollSocket(socket), addr epv) != 0:
      raiseIOSelectorsError(osLastError())
    inc(s.count)
  echo "After Register: ", s.fds[fd].repr

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

# proc updateHandle*[T](s: Selector[T], socket: int|SocketHandle, events: set[Event]) =
#   if events != {}:
#     if socket notin s:
#       return
    
#     let fd = socket.changeFd.EpollSocket
#     var epv = EpollEvent(events: EPOLLRDHUP.uint32)
#     if Event.Read in events: epv.events = epv.events or EPOLLIN.uint32
#     if Event.Write in events: epv.events = epv.events or EPOLLOUT.uint32
#     if epoll_ctl(s.epollFD, EPOLL_CTL_MOD, fd, addr epv) != 0:
#       raiseIOSelectorsError(osLastError())

proc unregister*[T](s: Selector[T], socket: int|SocketHandle) =
  let fd = socket.changeFd
  s.checkFd(fd)
  var pkey = addr(s.fds[fd])
  doAssert(pkey.ident != InvalidIdent,
           "Descriptor $# is not registered in the selector!" % $fd)
  if pkey.events != {}:
    if Event.Read in pkey.events or Event.Write in pkey.events or Event.User in pkey.events:
      var epv = EpollEvent()
      # TODO: Refactor all these EPOLL_CTL_DEL + dec(s.count) into a proc.
      if epoll_ctl(s.epollFD, EPOLL_CTL_DEL, EpollSocket(socket), addr epv) != 0:
        raiseIOSelectorsError(osLastError())
      dec(s.count)

  clearKey(pkey)

template checkFd(s, f) =
  # TODO: I don't see how this can ever happen. You won't be able to create an
  # FD if there is too many. -- DP
  # if f >= s.maxFD:
  #   raiseIOSelectorsError("Maximum number of descriptors is exhausted!")
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


# proc epoll_wait*(ephnd: EpollHandle,
#                  events: ptr epoll_event,
#                  maxevents: cint,
#                  timeout: cint): cint

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

  once:
    echo resTable[0]
    echo count

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


proc getData*[T](s: Selector[T], fd: SocketHandle|int): var T =
  let fdi = fd.int
  s.checkFd(fdi)
  if fdi in s:
    result = s.fds[fdi shr 2].data

# when isMainModule:
#   import net

#   let s = newSelector[int]()
#   let fd = epoll_create1(0)

#   if fd == nil:
#     echo "Error: epoll_create1"
#     raiseIOSelectorsError(osLastError())

#   var sock = newSocket()
#   sock.bindAddr(Port(1234))
#   sock.listen()
#   sock.setSockOpt(OptReusePort, true)

#   let sockfd = getFd(sock)
#   # let sock = socket(wl.AF_INET, 1, 6)
#   registerHandle[int](s, fd, {Read, Write}, sockfd, 12)


#   # for (;;) {
#   #   nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
#   #   if (nfds == -1) {
#   #       perror("epoll_wait");
#   #       exit(EXIT_FAILURE);
#   #   }

#   #   for (n = 0; n < nfds; ++n) {
#   #       if (events[n].data.fd == listen_sock) 
#   #         conn_sock = accept(listen_sock,
#   #                           (struct sockaddr *) &addr, &addrlen);
#   #         if (conn_sock == -1) {
#   #             perror("accept");
#   #             exit(EXIT_FAILURE);
#   #         }
#   #         setnonblocking(conn_sock);
#   #         ev.events = EPOLLIN | EPOLLET;
#   #         ev.data.fd = conn_sock;
#   #         if (epoll_ctl(epollfd, EPOLL_CTL_ADD, conn_sock,
#   #                     &ev) == -1) {
#   #             perror("epoll_ctl: conn_sock");
#   #             exit(EXIT_FAILURE);
#   #         }

#   echo sock.getfd.int

#   import strformat

#   while true:
#     var res: array[MAX_EPOLL_EVENTS, EpollEvent]
#     discard selectInto(s, 120, res)
#     # echo fmt"{res[0].fd = } == {sock.getfd.int = }" 
#     for data in res:
#       if data.data.fd == sock.getfd.int:
#         echo "true"
#         sock.close()

#   # echo res.repr
#   # echo s.repr
#   close(sock)
#   close(s)
