
# Main program

import cps

import types
import evq
import conn
import bconn
import strutils
import tables
import strformat


type
  HttpRequest = ref object
    meth: string
    path: string
    proto: string
    keepAlive: bool
    contentLength: int
    headers: Table[string, string] # yeah yeah

  HttpResponse = ref object
    body: string
    keepAlive: bool
    headers: Table[string, string] # yeah yeah


proc parseHttpRequest(br: Breader, req: HttpRequest) {.cps:C.} =

  # Get request line
  br.readLine()
  if br.line == "": return
  let ps = splitWhitespace(br.line)
  (req.meth, req.path, req.proto) = (ps[0], ps[1], ps[2])

  # Get all headers
  while true:
    br.readLine()
    if br.line.len() == 0:
      break
    let ps = br.line.split(": ", 2)
    if ps.len == 2:
      req.headers[ps[0].toLower] = ps[1]
  
  req.keepAlive = req.headers.getOrDefault("connection") == "Keep-Alive"
  req.contentLength = parseInt(req.headers.getOrDefault("content-length", "0"))
 
  # Read payload
  br.read(req.contentLength)


proc writeHttpResponse(bw: Bwriter, rsp: HttpResponse) {.cps:C.} =
  bw.write("HTTP/1.1 200 OK\r\n")
  bw.write("Content-Type: text/plain\r\n")
  if rsp.body.len > 0:
    bw.write(&"Content-Length: {rsp.body.len}\r\n")
  if rsp.keepAlive:
    bw.write("Connection: Keep-Alive\r\n")
  var hs = ""
  for k, v in rsp.headers:
    hs.add k & ": " & v & "\r\n"
  bw.write(hs)
  bw.write("\r\n")
  bw.write(rsp.body)
  bw.flush()

  if not rsp.keepAlive:
    bw.close()


proc handleHttp(br: Breader, bw: Bwriter) {.cps:C.} =

  let req = HttpRequest()
  parseHttpRequest(br, req)

  if req.meth == "":
    return

  let rsp = HttpResponse(
    body: "Hello, world!",
    keepAlive: req.keepAlive,
  )
  rsp.headers["X-Foo"] = "Bar"

  writeHttpResponse(bw, rsp)
 

proc doClient(conn: Conn) {.cps:C.} =
  #echo "connected"

  let br = newBreader(conn)
  let bw = newBwriter(conn)

  while not br.eof and not bw.eof:
    handleHttp(br, bw)

  #echo "disconnected"
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
