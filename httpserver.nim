
# Main program

import cps

import types
import evq
import strutils
import tables
import strformat
import conn
import bconn
import http


type
  Request* = ref object
    meth: string
    path: string
    proto: string
    keepAlive: bool
    contentLength: int
    headers: Headers

  Response* = ref object
    body: string
    keepAlive: bool
    headers: Headers


proc read(req: Request, br: Breader) {.cps:C.} =

  # Get request line
  let line = br.readLine()
  if line == "":
    br.close()
    return
  let ps = splitWhitespace(line, 3)
  (req.meth, req.path, req.proto) = (ps[0], ps[1], ps[2])

  req.headers.read(br)
  
  req.keepAlive = req.headers.getOrDefault("connection") == "Keep-Alive"
  req.contentLength = parseInt(req.headers.getOrDefault("content-length", "0"))
 
  # Read payload
  let body = br.read(req.contentLength)


proc write(rsp: Response, bw: Bwriter) {.cps:C.} =
  bw.write("HTTP/1.1 200 OK\r\n")
  bw.write("Content-Type: text/plain\r\n")
  if rsp.body.len > 0:
    bw.write(&"Content-Length: {rsp.body.len}\r\n")
  if rsp.keepAlive:
    bw.write("Connection: Keep-Alive\r\n")
  rsp.headers.write(bw)
  bw.write(rsp.body)
  bw.flush()

  if not rsp.keepAlive:
    bw.close()


proc newRequest(): Request {.cps:C.} =
  Request(
    headers: Headers()
  )

proc newResponse(): Response {.cps:C.} =
  Response(
    headers: Headers()
  )

proc onRequest(req: Request, rsp: Response) {.cps:C.} =
  discard

proc handleHttp(br: Breader, bw: Bwriter) {.cps:C.} =

  let req = newRequest()
  req.read(br)

  if req.meth == "":
    return

  let rsp = newResponse()
  rsp.body = "Hello, world!"
  rsp.keepAlive = req.keepAlive

  onRequest(req, rsp)
  rsp.write(bw)
 

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


