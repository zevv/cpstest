
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
    reason*: string
    contentLength*: int
    keepAlive*: bool
    body*: string

#
# Headers
#

proc canon(s: string): string =
  let l = s.len
  result = newStringOfCap(l)
  var upper = true
  for c in s:
    result &= (if upper: c.toUpperAscii else: c.toLowerAscii)
    upper = c == '-'

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
    result.add canon(k) & ": " & vs.join(",") & "\r\n"
  result.add "\r\n"

proc get*(headers: Headers, key: string): string =
  let key = key.toLower
  if key in headers.headers:
    return headers.headers[key][0]


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
  var path = req.uri.path
  if path == "": path = "/"
  if req.uri.query.len > 0:
    path.add("?" & req.uri.query)
  result.add req.meth & " " & path & " HTTP/1.1\r\n"
  result.add("Host: " & req.uri.hostname & "\r\n")
  if req.contentLength > 0:
    result.add("Content-Length: " & $req.contentLength & "\r\n")
  result.add $req.headers

proc read*(req: Request, br: Breader) {.cps:C.} =
  let line = br.readLine()
  if line == "":
    br.close()
    return
  let ps = splitWhitespace(line, 3)
  let (meth, target, version) = (ps[0], ps[1], ps[2])

  req.meth = meth
  req.headers.read(br)
  
  req.keepAlive = req.headers.get("Connection") == "Keep-Alive"
  let host = req.headers.get("Host")
  try:
    req.contentLength = parseInt(req.headers.get("Content-Length"))
  except:
    discard
  
  parseUri("http://" & host & target, req.uri)

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
  rsp.reason = ps[2]
  rsp.headers.read(br)
  
  try:
    rsp.contentLength = parseInt(rsp.headers.get("Content-Length"))
  except:
    discard

  

proc write*(rsp: Response, bw: Bwriter) {.cps:C.} =
  bw.write $rsp
