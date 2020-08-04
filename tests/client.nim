import net


var socket = newSocket()
socket.connect("127.0.0.1", Port(1234))
socket.send("12345678")
