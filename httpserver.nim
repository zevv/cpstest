
import std/[times, tables]
import cps
import types, evq, conn, bio, http, logger, stream

const log_tag = "httpserver"

type
  HttpServer = ref object
    running: bool
    date: string
    stats: HttpServerStats
    handlers: Table[string, HttpServerCallback]

  HttpServerStats = object
    connectionCount: int
    requestCount: int

  HttpServerCallback* = proc(req: Request, rsp: Response, s: Stream) {.cps:C.}


proc doService(hs: HttpServer) {.cps:C.} =
  var stats: HttpServerStats
  while hs.running:
    hs.date = now().utc().format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
    if stats != hs.stats:
      stats = hs.stats
      info $stats.repr
    sleep(1)


proc newHttpServer*(): HttpServer {.cps:C.}=
  let hs = HttpServer(running: true)
  # Spawn a separate thread for periodic service work
  spawn hs.doService()
  hs


proc addPath*(hs: HttpServer, path: string, handler: HttpServerCallback) {.cps:C.} =
  hs.handlers[path] = handler


proc doRequest(hs: HttpServer, s: Stream) {.cps:C.} =

  # Request
  let req = newRequest(s)
  req.read()
  if req.meth == "":
    return

  dump $req

  # Response
  let rsp = newResponse(s)
  rsp.headers.add("Date", hs.date)
  rsp.headers.add("Server", "cpstest")
  rsp.keepAlive = req.keepAlive

  if req.uri.path in hs.handlers:
    rsp.statusCode = 200
    rsp.headers.add("Transfer-Encoding", "chunked")
    #rsp.write()
    let cb = hs.handlers[req.uri.path]
    let sHttp = http.newHttpStream(req, rsp, s)
    var c = cb.call(req, rsp, sHttp)
    mommify c
    s.write("")
  else:
    rsp.statusCode = 404
    rsp.write()


  #if rsp.contentLength > 0:
  #  discard bio.write(body)
  s.flush()

  if not req.keepAlive:
    s.close()
    s.close()
  
  inc hs.stats.requestCount
 

proc doConnection(hs: HttpServer, conn: Conn) {.cps:C.} =
  inc hs.stats.connectionCount
  let s = newBio(conn)
  while not s.eof():
    doRequest(hs, s)
  conn.close()


proc listenAndServe*(hs: HttpServer, host: string, service: string, certfile="") {.cps:C.} =
  # Create listening socket and spawn a new thread for each incoming connection
  let connServer = listen(host, service, certfile)
  while true:
    iowait(connServer, POLLIN)
    try:
      let conn = connServer.accept()
      spawn hs.doConnection(conn)
    except OsError:
      warn getCurrentExceptionMsg()

