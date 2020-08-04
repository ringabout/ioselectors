import net
import sets


var s: HashSet[int]

for i in 0 ..< 1000:
  var socket = newSocket()
  s.incl socket.getfd.int shr 2

echo s.len
# socket.connect("127.0.0.1", Port(1234))
# socket.close()