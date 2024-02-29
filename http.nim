
import std/[tables,strutils,uri]
import cps
import bio, types, stream

type
  Headers* = ref object
    headers*: Table[string, seq[string]]
  
  Request* = ref object
    s: Stream
    meth*: string
    uri*: Uri
    keepAlive*: bool
    contentLength*: int
    headers*: Headers

  Response* = ref object
    s: Stream
    headers*: Headers
    statusCode*: int
    reason*: string
    contentLength*: int
    keepAlive*: bool
    body*: string
    written: bool

  StatusCode = distinct int

  ResponseWriter* = ref object
    stream: Stream


proc statusCodeStr(sc: int): string =
  case sc
  of 200: "200 Ok"
  of 201: "201 Created"
  of 403: "403 Forbidden"
  of 404: "404 Not Found"
  else: $sc


# HTTP stream. The reader reads Content-Length from the underlying sink,
# the writer sends data in chunked encoding.

type
  HttpStream = ref object of Stream
    read_avail: int
    sink: Stream
    rsp: Response


proc httpStreamWriteImpl(s: Stream, data: string) {.cps:C.} =
  let hs = s.HttpStream
  #hs.rsp.write()
  let sink = hs.sink
  sink.write tohex(data.len)
  sink.write("\r\n")
  sink.write(data)
  sink.write("\r\n")


proc httpStreamReadImpl(s: Stream, n: int): string {.cps:C.} =
  let sink = s.HttpStream.sink
  var count = min(s.HttpStream.read_avail, n)
  result = sink.read(count)
  s.HttpStream.read_avail -= count


proc httpStreamEofImpl(s: Stream): bool {.cps:C.} =
  s.HttpStream.read_avail == 0


proc newHttpStream*(req: Request, rsp: Response, sink: Stream): Stream =
  HttpStream(
    rsp: rsp,
    read_avail: req.contentLength,
    sink: sink,
    fn_write: whelp httpStreamWriteImpl,
    fn_read: whelp httpStreamReadImpl,
    fn_eof: whelp httpStreamEofImpl,
  )


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

proc read*(headers: Headers, s: Stream) {.cps:C.} =
  while true:
    let line = s.readLine()
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

proc newRequest*(s: Stream): Request {.cps:C.} =
  Request(
    s: s,
    headers: Headers()
  )


proc newRequest*(meth: string, url: string): Request =
  result = Request(
    meth: meth,
    headers: http.Headers(),
  )
  parseUri(url, result.uri)


proc setStream*(req: Request, s: Stream) =
  req.s = s


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


proc read*(req: Request) {.cps:C.} =
  let line = req.s.readLine()
  if line == "":
    req.s.close()
    return
  let ps = splitWhitespace(line, 3)
  let (meth, target, version) = (ps[0], ps[1], ps[2])

  req.meth = meth
  req.headers.read(req.s)
  
  req.keepAlive = req.headers.get("Connection") == "Keep-Alive"
  let host = req.headers.get("Host")
  try:
    req.contentLength = parseInt(req.headers.get("Content-Length"))
  except:
    discard
  
  parseUri("http://" & host & target, req.uri)


proc write*(req: Request) {.cps:C.} =
  req.s.write($req)


#
# Response
#

proc newResponse*(s: Stream): Response =
  Response(
    s: s,
    headers: http.Headers(),
    contentLength: -1,
  )


proc `$`*(rsp: Response): string =
  result.add "HTTP/1.0 " & statusCodeStr(rsp.statusCode) & "\r\n"
  if rsp.contentLength > 0:
    result.add "Content-Length: " & $rsp.contentLength & "\r\n" 
  if rsp.keepAlive:
    result.add "Connection: Keep-Alive\r\n" 
  result.add $rsp.headers


proc read*(s: Stream, rsp: Response) {.cps:C.}=
  let line = s.readLine()
  
  let ps = splitWhitespace(line, 3)
  rsp.statusCode = parseInt(ps[1])
  rsp.reason = ps[2]
  rsp.headers.read(s)
  
  try:
    rsp.contentLength = parseInt(rsp.headers.get("Content-Length"))
  except:
    discard


proc write*(rsp: Response) {.cps:C.} =
  if not rsp.written:
    rsp.s.write $rsp
    rsp.written = true


