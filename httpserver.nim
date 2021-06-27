
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


let body = "Hello, world!"


proc handleHttp(br: Breader, bw: Bwriter) {.cps:C.} =

  let req = newRequest()
  req.read(br)

  if req.meth == "":
    return
  
  echo req
  if req.contentLength > 0:
    let reqBody = br.read(req.contentLength)
    echo reqBody
 
  echo "-------"
  let rsp = newResponse()
  rsp.contentLength = body.len
  rsp.keepAlive = req.keepAlive
  echo rsp

  rsp.write(bw)
  if rsp.contentLength > 0:
    bw.write(body)
    bw.flush()

  echo "-------"
 
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


