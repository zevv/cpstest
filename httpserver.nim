
import std/[times]
import cps
import types, evq, conn, bconn, http, logger

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

proc doRequest(hs: HttpServer, br: Breader, bw: Bwriter) {.cps:C.} =

  # Request
  let req = newRequest()
  req.read(br)
  if req.meth == "":
    return
  if req.contentLength > 0:
    let reqBody = br.read(req.contentLength)

  dump($req)

  # Response
  let rsp = newResponse()
  rsp.contentLength = body.len
  rsp.statusCode = 200
  rsp.keepAlive = req.keepAlive
  rsp.headers.add("Date", hs.date)
  rsp.headers.add("Server", "cpstest")
  rsp.write(bw)

  if rsp.contentLength > 0:
    bw.write(body)
  bw.flush()

  if not req.keepAlive:
    br.close()
    bw.close()
  
  inc hs.stats.requestCount
 

proc doConnection(hs: HttpServer, conn: Conn) {.cps:C.} =
  inc hs.stats.connectionCount
  let br = newBreader(conn)
  let bw = newBwriter(conn)
  while not br.eof and not bw.eof:
    doRequest(hs, br, bw)
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

