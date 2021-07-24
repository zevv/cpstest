
import std/[times]
import cps
import types, evq, conn, bio, http, logger

const log_tag = "httpserver"

let body = "hello\n"

type
  HttpServer = ref object
    running: bool
    date: string
    stats: HttpServerStats

  HttpServerStats = object
    connectionCount: int
    requestCount: int



proc newHttpServer*(): HttpServer =
  HttpServer()

proc doRequest(hs: HttpServer, bio: Bio) {.cps:C.} =

  # Request
  let req = newRequest()
  bio.read(req)
  if req.meth == "":
    return
  if req.contentLength > 0:
    let reqBody = bio.read(req.contentLength)

  dump($req)

  # Response
  let rsp = newResponse()
  rsp.contentLength = body.len
  rsp.statusCode = 200
  rsp.keepAlive = req.keepAlive
  rsp.headers.add("Date", hs.date)
  rsp.headers.add("Server", "cpstest")
  bio.write(rsp)

  if rsp.contentLength > 0:
    discard bio.write(body)
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


proc doService(hs: HttpServer) {.cps:C.} =
  var stats: HttpServerStats
  while hs.running:
    hs.date = now().utc().format("ddd, dd MMM yyyy HH:mm:ss 'GMT'")
    if stats != hs.stats:
      stats = hs.stats
      info $stats.repr
    sleep(1)


proc listenAndServe*(hs: HttpServer, host: string, service: string, certfile="") {.cps:C.} =
  hs.running = true
  
  # Spawn a separate thread for periodic service work
  spawn hs.doService()

  # Create listening socket and spawn a new thread for each
  # incoming connection
  let connServer = listen(host, service, certfile)
  while true:
    iowait(connServer, POLLIN)
    try:
      let conn = connServer.accept()
      spawn hs.doConnection(conn)
    except OsError:
      warn getCurrentExceptionMsg()

