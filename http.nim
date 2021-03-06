
import std/[tables,strutils,uri]
import cps
import bio, types

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

  StatusCode = distinct int

  ResponseWriter* = ref object
    bio: Bio


proc statusCodeStr(sc: int): string =
  case sc
  of 200: "200 Ok"
  of 201: "201 Created"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  else: $sc

# Chunked encoded writer

proc newResponseWriter*(bio: Bio): ResponseWriter =
  ResponseWriter(bio: bio)


proc write*(rw: ResponseWriter, s: string) {.cps:C.} =
  discard rw.bio.write tohex(s.len)
  discard rw.bio.write("\r\n")
  discard rw.bio.write(s)
  discard rw.bio.write("\r\n")


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

proc read*(bio: Bio, headers: Headers) {.cps:C.} =
  while true:
    let line = bio.readLine()
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


proc read*(bio: Bio, req: Request) {.cps:C.} =
  let line = bio.readLine()
  if line == "":
    bio.close()
    return
  let ps = splitWhitespace(line, 3)
  let (meth, target, version) = (ps[0], ps[1], ps[2])

  req.meth = meth
  bio.read(req.headers)
  
  req.keepAlive = req.headers.get("Connection") == "Keep-Alive"
  let host = req.headers.get("Host")
  try:
    req.contentLength = parseInt(req.headers.get("Content-Length"))
  except:
    discard
  
  parseUri("http://" & host & target, req.uri)


proc write*(bio: Bio, req: Request) {.cps:C.} =
  discard bio.write($req)


#
# Response
#

proc newResponse*(): Response =
  result = Response(
    headers: http.Headers(),
    contentLength: -1,
  )


proc `$`*(rsp: Response): string =
  result.add "HTTP/1.0 " & statusCodeStr(rsp.statusCode) & "\r\n"
  result.add "Content-Type: text/plain\r\n" 
  if rsp.contentLength > 0:
    result.add "Content-Length: " & $rsp.contentLength & "\r\n" 
  if rsp.keepAlive:
    result.add "Connection: Keep-Alive\r\n" 
  result.add $rsp.headers


proc read*(bio: Bio, rsp: Response) {.cps:C.}=
  let line = bio.readLine()
  
  let ps = splitWhitespace(line, 3)
  rsp.statusCode = parseInt(ps[1])
  rsp.reason = ps[2]
  bio.read(rsp.headers)
  
  try:
    rsp.contentLength = parseInt(rsp.headers.get("Content-Length"))
  except:
    discard


proc write*(bio: Bio, rsp: Response) {.cps:C.} =
  discard bio.write $rsp
