import ioselectors, os


# when isMainModule:
import net

let s = newSelector[int]()
let fd = epoll_create1(0)

if fd == nil:
  echo "Error: epoll_create1"
  raiseIOSelectorsError(osLastError())

var sock = newSocket()
sock.bindAddr(Port(1234))
sock.listen()
sock.setSockOpt(OptReusePort, true)

let sockfd = getFd(sock)
# let sock = socket(wl.AF_INET, 1, 6)
registerHandle[int](s, sockfd, {Read, Write}, 12)

echo sock.getfd.int


while true:
  var res: array[64, ReadyKey]
  discard selectInto(s, 120, res)
  # echo fmt"{res[0].fd = } == {sock.getfd.int = }" 
  # for data in res:
  #   if data.data.fd == sock.getfd.int:
  #     echo "true"
  #     sock.close()

  echo res[0].repr

close(sock)
close(s)

