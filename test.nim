import nativesockets
import sets


var s = initHashSet[int]()

for i in 1 .. 10000:
  s.incl createNativeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP).int

echo s.len
