
# Main program
#
# This is just a bunch of snippets to test all the underlying
# CPS and IO stuff

from os import nil
import posix
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger, process, conn, stream

const log_tag = "main"


proc onHttpHello(req: http.Request, rsp: http.Response, s: Stream) {.cps:C.} =

  rsp.headers.add("Content-Type", "text/plain")
  rsp.write()

  while not s.eof:
    let data = s.read(8)

  s.write("Hello, ")
  s.write("world!\r\n")


proc onHttpWebsocket(req: http.Request, rsp: http.Response, s: Stream) {.cps:C.} =
  rsp.headers.add("Sec-WebSocket-Protocol", "cps")
  rsp.headers.add("Connection", "Upgrade")
  rsp.headers.add("Upgrade", "websocket")
  rsp.headers.add("Sec-WebSocket-Accept", "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
  rsp.write()


# HTTP server serving on both HTTP port 8080 and HTTPS port 8443
proc doServer() {.cps:C.} =
  let body = "Hello, world!\r\n"
  let hs = newHttpServer()
  hs.addPath "/hello", whelp onHttpHello
  hs.addPath "/ws", whelp onHttpWebsocket
  spawn hs.listenAndServe("::", "8080")
  spawn hs.listenAndServe("::", "8443", "cert.pem")
  sleep(0.1)


# Perform an async http request
proc doClient(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    ldbg $rsp
    let body = client.readBody(rsp)
  except OSError as e:
    warn "Could not connect to " & url & ": " & e.msg


# A simple periodic ticker
proc doTicker() {.cps:C.} =
  var n = 0
  while n < 5:
    sleep(1.0)
    inc n
    ldbg "tick $1", n


# Offload blocking os.sleep() to a different thread
proc doBlocker() {.cps:C.} =
  ldbg "blocker start"
  onThread:
    os.sleep(4000)
  ldbg "blocker done"


# Login to a matrix server
proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))


# Spawn a subprocess, do some stdin/stdout and wait for it to die
#proc doProcess() {.cps:C.} =
#  linf "subprocess starting"
#  let p = process.start("/usr/bin/rev", @[])
#  discard p.stdin.write("Reverse me")
#  p.stdin.close()
#  linf "subprocess said: " & p.stdout.read(1024)
#  let status = p.wait()
#  linf "subprocess done, status: $1", status


# Run all the tests
proc runStuff() {.cps:C.} =
  linf("CpsTest firing up")
  spawn doServer()
  #spawn doClient("https://localhost:8443/hello")
  #spawn doTicker()
  #spawn doBlocker()
  #spawn doMatrix()
#  spawn doProcess()


var mylogger = newLogger(llInf)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

