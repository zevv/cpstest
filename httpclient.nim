
import tables
import strutils
import std/uri

import cps

import bconn
import evq
import types
import conn
import http

type
  Client = ref object
    maxFollowRedirects: int

  Request = ref object
    meth: string
    uri: Uri
    headers: Headers

  Response = ref object
    headers: Headers
    statusCode: int
    statusMessage: string

proc newClient*(): Client =
  Client(
    maxFollowRedirects: 5
  )

proc newRequest*(meth: string, url: string): Request =
  result = Request(
    meth: meth,
    headers: http.Headers(),
  )
  parseUri(url, result.uri)

proc `$`*(req: Request): string =
  result.add req.meth & " " & req.uri.path & " HTTP/1.1\r\n"
  result.add("Host: " & req.uri.hostname & "\r\n")
  if req.uri.query.len > 0:
    result.add("?" & req.uri.query)
  result.add $req.headers
  result.add "\r\n"

proc newResponse*(): Response =
  result = Response(
    headers: http.Headers(),
  )

proc send(req: Request, bw: BWriter) {.cps:C.} =
  bw.write($req)
  bw.flush()

proc recv(rsp: Response, br: BReader) {.cps:C.}=
  let line = br.readLine()
  echo line
  
  let ps = splitWhitespace(line, 3)
  rsp.statusCode = parseInt(ps[1])
  rsp.statusMessage = ps[2]
  rsp.headers.read(br)


proc doRequest*(meth: string, client: Client, url: string): Response {.cps:C.} =
  let req = newRequest(meth, url)
  echo $req
  let conn = conn.dial(req.uri.hostname, 80)
  let bw = newBwriter(conn)
  let br = newBreader(conn)
  req.send(bw)
  var rsp = newResponse()
  rsp.recv(br)
  
  return rsp
  
proc get*(client: Client, url: string): Response {.cps:C} =
  var url = url
  var follows = 0
  while follows < client.maxFollowRedirects:
    let rsp = doRequest("GET", client, url)
    let location = rsp.headers.getOrDefault("location", "")
    if location.len == 0:
      return rsp
    else:
      url = location

