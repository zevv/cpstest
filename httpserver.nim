
import strutils
import tables
import std/uri
import strformat

import cps

import types
import evq
import conn
import bconn
import http




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
  let connServer = listen(port)
  while true:
    iowait(connServer, POLLIN)
    let conn = connServer.accept()
    evq.push whelp doClient(conn)


