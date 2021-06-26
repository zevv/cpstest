
# Main program

import cps

import types
import evq
import strutils
import tables
import strformat
include bconn


type
  Request* = ref object
    meth: string
    path: string
    proto: string
    keepAlive: bool
    contentLength: int
    headers: Table[string, string] # yeah yeah

  Response* = ref object
    body: string
    keepAlive: bool
    headers: Table[string, string] # yeah yeah


proc parseRequest(br: Breader, req: Request) {.cps:C.} =

  # Get request line
  let line = br.readLine()
  if line == "": return
  let ps = splitWhitespace(line)
  (req.meth, req.path, req.proto) = (ps[0], ps[1], ps[2])

  # Get all headers
  while true:
    let line = br.readLine()
    if line.len() == 0:
      break
    let ps = line.split(": ", 2)
    if ps.len == 2:
      req.headers[ps[0].toLower] = ps[1]
  
  req.keepAlive = req.headers.getOrDefault("connection") == "Keep-Alive"
  req.contentLength = parseInt(req.headers.getOrDefault("content-length", "0"))
 
  # Read payload
  let body = br.read(req.contentLength)


proc writeResponse(bw: Bwriter, rsp: Response) {.cps:C.} =
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


proc onRequest(req: Request, rsp: Response) {.cps:C.} =
  discard

proc handleHttp(br: Breader, bw: Bwriter) {.cps:C.} =

  let req = Request()
  parseRequest(br, req)

  if req.meth == "":
    return

  let rsp = Response(
    body: "Hello, world!",
    keepAlive: req.keepAlive,
  )

  onRequest(req, rsp)

  writeResponse(bw, rsp)
 

proc doClient(conn: Conn) {.cps:C.} =
  #echo "connected"

  let br = newBreader(conn)
  let bw = newBwriter(conn)

  while not br.eof and not bw.eof:
    handleHttp(br, bw)

  #echo "disconnected"
  conn.close()


proc listenAndServe*(evq: Evq, port: int) {.cps:C.} =
  let connServer = listen(evq, port)
  while true:
    iowait(connServer, POLLIN)
    let conn = connServer.accept()
    evq.push whelp doClient(conn)


