
import std/[times, tables]
import cps
import types, evq, conn, bio, http, logger

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

  HttpServerCallback* = proc(rw: ResponseWriter): bool {.cps:C.}


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
  debug "addPath $1", path


proc doRequest(hs: HttpServer, bio: Bio) {.cps:C.} =

  # Request
  let req = newRequest()
  bio.read(req)
  if req.meth == "":
    return
  if req.contentLength > 0:
    let reqBody = bio.read(req.contentLength)

  dump $req

  # Response
  let rsp = newResponse()
  rsp.headers.add("Date", hs.date)
  rsp.headers.add("Server", "cpstest")
  rsp.keepAlive = req.keepAlive

  if req.uri.path in hs.handlers:
    rsp.statusCode = 200
    rsp.headers.add("Transfer-Encoding", "chunked")
    bio.write(rsp)
    let c = hs.handlers[req.uri.path]
    let rw = newResponseWriter(bio)
    discard c(rw)
    rw.write("")
  else:
    rsp.statusCode = 404
    bio.write(rsp)


  #if rsp.contentLength > 0:
  #  discard bio.write(body)
  bio.flush()

  if not req.keepAlive:
    bio.close()
    bio.close()
  
  inc hs.stats.requestCount
 

proc doConnection(hs: HttpServer, conn: Conn) {.cps:C.} =
  inc hs.stats.connectionCount
  let bio = newBio(conn)
  while not bio.eof and not bio.eof:
    doRequest(hs, bio)
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

