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
      # fds: seq[SelectorKey[T]]
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
    # result.fds = allocSharedArray[SelectorKey[T]](numFD)
  else:
    result = Selector[T]()
    result.epollFD = epollFD
    result.numFD = numFD
    # result.fds = newSeq[SelectorKey[T]](numFD)

  # for i in 0 ..< numFD:
  #   result.fds[i].ident = InvalidIdent

proc close*[T](s: Selector[T]) =
  let res = epoll_close(s.epollFD)
  when hasThreadSupport:
    # deallocSharedArray(s.fds)
    deallocShared(cast[pointer](s))
  
  if res != 0:
    raiseIOSelectorsError(osLastError())

proc newSelectEvent*(): SelectEvent =
  let event = EpollEvent(events: 0, data: EpollData(u64: 0))


proc registerHandle*[T](s: Selector[T], fd: EpollHandle,
                        events: set[Event], socket: SocketHandle, data: T) =

  # epoll_ctl*(ephnd: EpollHandle; op: cint; 
  #               sock: SOCKET; event: ptr epoll_event): cint

  if events != {}:
    var epv = EpollEvent(events: EPOLLRDHUP.uint32)
    epv.data.fd = socket.cint
    if Event.Read in events: epv.events = epv.events or EPOLLIN.uint32
    if Event.Write in events: epv.events = epv.events or EPOLLOUT.uint32
    if epoll_ctl(s.epollFD, EPOLL_CTL_ADD, socket.culonglong, addr epv) != 0:
      raiseIOSelectorsError(osLastError())
    inc(s.count)


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
    i, k: int

  if maxres > len(results):
    maxres = len(results)

  # verifySelectParams(timeout)

  let count = epoll_wait(s.epollFD, addr(resTable[0]), maxres.cint,
                         timeout.cint)


  if count == 1:
    once:
      echo "Count -> ", count
      echo resTable[0].repr

import net

let s = newSelector[int]()
let fd = epoll_create1(0)

if fd == nil:
  echo "Error: epoll_create1"
  raiseIOSelectorsError(osLastError())

var sock = newSocket()
sock.bindAddr(Port(1234))
sock.listen()

let sockfd = getFd(sock)
# let sock = socket(wl.AF_INET, 1, 6)
registerHandle[int](s, fd, {Read, Write}, sockfd, 12)


# for (;;) {
#   nfds = epoll_wait(epollfd, events, MAX_EVENTS, -1);
#   if (nfds == -1) {
#       perror("epoll_wait");
#       exit(EXIT_FAILURE);
#   }

#   for (n = 0; n < nfds; ++n) {
#       if (events[n].data.fd == listen_sock) 
#         conn_sock = accept(listen_sock,
#                           (struct sockaddr *) &addr, &addrlen);
#         if (conn_sock == -1) {
#             perror("accept");
#             exit(EXIT_FAILURE);
#         }
#         setnonblocking(conn_sock);
#         ev.events = EPOLLIN | EPOLLET;
#         ev.data.fd = conn_sock;
#         if (epoll_ctl(epollfd, EPOLL_CTL_ADD, conn_sock,
#                     &ev) == -1) {
#             perror("epoll_ctl: conn_sock");
#             exit(EXIT_FAILURE);
#         }


while true:
  var res: array[64, ReadyKey]
  discard selectInto(s, 120, res)
  for data in res:
    if data.fd == sock.getfd.int:
      echo "true"

# echo res.repr
# echo s.repr
close(s)
