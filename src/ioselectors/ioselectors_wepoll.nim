import wepoll, os, nativesockets, winlean


import strutils

const hasThreadSupport = false

when hasThreadSupport:
  import locks

  type
    SharedArray[T] = UncheckedArray[T]

  proc allocSharedArray[T](nsize: int): ptr SharedArray[T] =
    result = cast[ptr SharedArray[T]](allocShared0(sizeof(T) * nsize))

  proc reallocSharedArray[T](sa: ptr SharedArray[T], nsize: int): ptr SharedArray[T] =
    result = cast[ptr SharedArray[T]](reallocShared(sa, sizeof(T) * nsize))

  proc deallocSharedArray[T](sa: ptr SharedArray[T]) =
    deallocShared(cast[pointer](sa))
type
  Event* {.pure.} = enum
    Read, Write, Timer, Signal, Process, Vnode, User, Error, Oneshot,
    Finished, VnodeWrite, VnodeDelete, VnodeExtend, VnodeAttrib, VnodeLink,
    VnodeRename, VnodeRevoke

type
  IOSelectorsException* = object of CatchableError

  ReadyKey* = object
    fd* : int
    events*: set[Event]
    errorCode*: OSErrorCode

  SelectorKey[T] = object
    ident: int
    events: set[Event]
    param: int
    data: T

const
  InvalidIdent = -1

proc raiseIOSelectorsError[T](message: T) =
  var msg = ""
  when T is string:
    msg.add(message)
  elif T is OSErrorCode:
    msg.add(osErrorMsg(message) & " (code: " & $int(message) & ")")
  else:
    msg.add("Internal Error\n")
  var err = newException(IOSelectorsException, msg)
  raise err

proc setNonBlocking(fd: cint) {.inline.} =
  setBlocking(fd.SocketHandle, false)


##############################################################################
when hasThreadSupport:
  type
    SelectorImpl[T] = object
      epollFD: EpollHandle
      maxFD: int
      numFD: int
      fds: ptr SharedArray[SelectorKey[T]]
      count: int
    Selector*[T] = ptr SelectorImpl[T]
else:
  type
    SelectorImpl[T] = object
      epollFD: EpollHandle
      numFD: int
      fds: seq[SelectorKey[T]]
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

  # if epollFD < 0:
  #   raiseOSError(osLastError())

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
    deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
  
  if res != 0:
    raiseIOSelectorsError(osLastError())

proc newSelectEvent*(): SelectEvent =
  let event = EpollEvent(events: 0, data: EpollData(u64: 0))


  # let fdci = eventfd(0, O_CLOEXEC or O_NONBLOCK)
  # if fdci == -1:
  #   raiseIOSelectorsError(osLastError())
  # result = cast[SelectEvent](allocShared0(sizeof(SelectEventImpl)))
  # result.efd = fdci


proc registerHandle*[T](s: Selector[T], fd: EpollHandle,
                        events: set[Event], socket: Socket) =
  # let fdi = int(fd)
  # s.checkFd(fdi)
  # doAssert(s.fds[fdi].ident == InvalidIdent, "Descriptor $# already registered" % $fdi)
  # s.setKey(fdi, events, 0, data)
  # epoll_ctl*(ephnd: EpollHandle; op: cint; 
  #               sock: SOCKET; event: ptr epoll_event): cint

  if events != {}:
    var epv = EpollEvent(events: EPOLLRDHUP)
    # epv.data.u64 = fd
    if Event.Read in events: epv.events = epv.events or EPOLLIN
    if Event.Write in events: epv.events = epv.events or EPOLLOUT
    if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, socket, addr epv) != 0:
      raiseIOSelectorsError(osLastError())
    inc(s.count)

let s = newSelector[int]()
close(s)
