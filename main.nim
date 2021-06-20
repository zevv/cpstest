
# Main program

import cps

import types
import evq
import conn


proc doClient(conn: Conn) {.cps:C.} =
  echo "connected"

  while true:
    let s = conn.recv(1024 * 1024)
    if s.len == 0:
      break
    conn.sendFull(s)

  echo "disconnected"
  conn.close()


proc doServer(evq: Evq, port: int) {.cps:C.} =
  let connServer = listen(evq, port)
  while true:
    iowait(connServer, POLLIN)
    let conn = connServer.accept()
    evq.push whelp doClient(conn)


proc ticker(evq: Evq) {.cps:C.} =
  let conn = dial(evq, "localhost", 8080)
  while true:
    echo "tick"
    sleep(1.0)


var myevq = newEvq()

myevq.push whelp doServer(myevq, 8080)
myevq.push whelp ticker(myevq)

myevq.run()
