
import std/[tables,strutils,uri]
import cps
import bconn, types

type
  Headers* = ref object
    headers*: Table[string, seq[string]]
  
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
    contentLength*: int
    keepAlive*: bool

#
# Headers
#

proc add*(headers: Headers, key: string, val: string) =
  if key notin headers.headers:
    headers.headers[key] = @[]
  headers.headers[key].add val

proc read*(headers: Headers, br: Breader) {.cps:C.} =
  while true:
    let line = br.readLine()
    if line.len() == 0:
      break
    let ps = line.split(": ", 2)
    if ps.len == 2:
      headers.add(ps[0].toLower, ps[1])

proc `$`*(headers: Headers): string =
  for k, vs in headers.headers:
    for v in vs:
      result.add k & ": " & v & "\r\n"
  result.add "\r\n"

proc getOrDefault*(headers: Headers, key: string, def: string): string =
  if key in headers.headers:
    headers.headers[key][0]
  else:
    def


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

proc read*(req: Request, br: Breader) {.cps:C.} =
  let line = br.readLine()
  if line == "":
    br.close()
    return
  let ps = splitWhitespace(line, 3)
  let (meth, trailer, proto) = (ps[0], ps[1], ps[2])

  req.meth = meth
  req.headers.read(br)
  
  req.keepAlive = req.headers.getOrDefault("connection", "Close") == "Keep-Alive"
  req.contentLength = parseInt(req.headers.getOrDefault("content-length", "0"))
  let host = req.headers.getOrDefault("host", "")
  
  parseUri("http://" & host & trailer, req.uri)

proc write*(req: Request, bw: BWriter) {.cps:C.} =
  bw.write($req)


#
# Response
#

proc newResponse*(): Response =
  result = Response(
    headers: http.Headers(),
    contentLength: -1,
  )

proc `$`*(rsp: Response): string =
  result.add("HTTP/1.0 " & $rsp.statuscode & " OK\r\n")
  result.add("Content-Type: text/plain\r\n")
  if rsp.contentLength > 0:
    result.add("Content-Length: " & $rsp.contentLength & "\r\n")
  if rsp.keepAlive:
    result.add("Connection: Keep-Alive\r\n")
  result.add $rsp.headers

proc read*(rsp: Response, br: BReader) {.cps:C.}=
  let line = br.readLine()
  
  let ps = splitWhitespace(line, 3)
  rsp.statusCode = parseInt(ps[1])
  rsp.statusMessage = ps[2]
  rsp.headers.read(br)

proc write*(rsp: Response, bw: Bwriter) {.cps:C.} =
  bw.write $rsp
