
import strutils
import tables
import std/uri
import strformat
import times

import cps

import types
import evq
import conn
import bconn
import http


let body = "Hello, world!"


proc handleHttp(br: Breader, bw: Bwriter) {.cps:C.} =

  let req = newRequest()
  req.read(br)

  if req.meth == "":
    return
  
  if req.contentLength > 0:
    let reqBody = br.read(req.contentLength)
                  
  let date = now().utc().format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
 
  let rsp = newResponse()
  rsp.contentLength = body.len
  rsp.keepAlive = req.keepAlive
  rsp.headers.add("Date", date)

  rsp.write(bw)
  if rsp.contentLength > 0:
    bw.write(body)
    bw.flush()
 
proc doClient(conn: Conn) {.cps:C.} =
  let br = newBreader(conn)
  let bw = newBwriter(conn)
  while not br.eof and not bw.eof:
    handleHttp(br, bw)
  conn.close()


proc listenAndServe*(evq: Evq, port: int) {.cps:C.} =
  let connServer = listen(port)
  while true:
    iowait(connServer, POLLIN)
    let conn = connServer.accept()
    evq.push whelp doClient(conn)


