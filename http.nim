
import tables
import strutils
import std/uri
import strformat

import cps

import bconn
import types

type
  Headers* = ref object
    headers*: Table[string, string]
  
  Request* = ref object
    meth*: string
    uri*: Uri
    keepAlive*: bool
    contentLength*: int
    headers*: Headers

  Response* = ref object
    headers*: Headers
    statusCode*: int
    statusMessage*: string
    keepAlive*: bool
    body*: string

#
# Headers
#

proc read*(headers: Headers, br: Breader) {.cps:C.} =
  while true:
    let line = br.readLine()
    if line.len() == 0:
      break
    let ps = line.split(": ", 2)
    if ps.len == 2:
      headers.headers[ps[0].toLower] = ps[1]

proc `$`*(headers: Headers): string =
  for k, v in headers.headers:
    result.add k & ": " & v & "\n"

proc write*(headers: Headers, bw: Bwriter) {.cps:C.} =
  bw.write $headers
  bw.write("\r\n")

proc getOrDefault*(headers: Headers, key: string, def: string): string =
  headers.headers.getOrDefault(key, def)


#
# Request
#

proc newRequest*(): Request {.cps:C.} =
  Request(
    headers: Headers()
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

proc read*(req: Request, br: Breader) {.cps:C.} =

  # Get request line
  let line = br.readLine()
  if line == "":
    br.close()
    return
  let ps = splitWhitespace(line, 3)
  let (meth, trailer, proto) = (ps[0], ps[1], ps[2])

  req.headers.read(br)
  
  req.keepAlive = req.headers.getOrDefault("connection", "Close") == "Keep-Alive"
  req.contentLength = parseInt(req.headers.getOrDefault("content-length", "0"))
  let host = req.headers.getOrDefault("host", "")
  
  parseUri("http://" & host & trailer, req.uri)
  echo req.uri
 
  # Read payload
  let body = br.read(req.contentLength)

proc write*(req: Request, bw: BWriter) {.cps:C.} =
  bw.write($req)
  bw.flush()


#
# Response
#

proc newResponse*(): Response =
  result = Response(
    headers: http.Headers(),
  )

proc `$`*(rsp: Response): string =
  result.add("HTTP/1.1 200 OK\r\n")
  result.add("Content-Type: text/plain\r\n")
  if rsp.body.len > 0:
    result.add(&"Content-Length: {rsp.body.len}\r\n")
  if rsp.keepAlive:
    result.add("Connection: Keep-Alive\r\n")
  result.add $rsp.headers
  result.add "\r\n"

proc read*(rsp: Response, br: BReader) {.cps:C.}=
  let line = br.readLine()
  echo line
  
  let ps = splitWhitespace(line, 3)
  rsp.statusCode = parseInt(ps[1])
  rsp.statusMessage = ps[2]
  rsp.headers.read(br)

proc write*(rsp: Response, bw: Bwriter) {.cps:C.} =
  bw.write $rsp
  rsp.headers.write(bw)
  bw.write(rsp.body)
  bw.flush()

  if not rsp.keepAlive:
    bw.close()


