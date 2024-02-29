
# Main program
#
# This is just a bunch of snippets to test all the underlying
# CPS and IO stuff

from os import nil
import posix
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger, process, conn, stream

const log_tag = "main"


proc onHttpRoot(body: string, rw: http.ResponseWriter) {.cps:C.} =
  rw.write(body)

# TODO #183: This is clumsy, we need a better way for doing cps-compatible
# callbacks
proc genHttpRoot(body: string): HttpServerCallback =
  return proc(rw: ResponseWriter): C =
    whelp onHttpRoot(body, rw)


proc onHttpRoot2(req: http.Request, s: Stream) {.cps:C.} =
  echo "genHttpRoot2"


# HTTP server serving on both HTTP port 8080 and HTTPS port 8443
proc doServer() {.cps:C.} =
  # A bit of a convoluted test to pass around context to the document handler
  # proc
  let body = "Hello, world!\r\n"
  let hs = newHttpServer()
  hs.addPath "/hello", genHttpRoot(body)
  hs.addPath2 "/hello2", whelp onHttpRoot2
  spawn hs.listenAndServe("::", "8080")
  #spawn hs.listenAndServe("::", "8443", "cert.pem")
  sleep(0.1)


# Perform an async http request
proc doClient(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    debug $rsp
    let body = client.readBody(rsp)
  except OSError as e:
    warn "Could not connect to " & url & ": " & e.msg


# A simple periodic ticker
proc doTicker() {.cps:C.} =
  var n = 0
  while n < 5:
    sleep(1.0)
    inc n
    debug "tick $1", n


# Offload blocking os.sleep() to a different thread
proc doBlocker() {.cps:C.} =
  debug "blocker start"
  onThread:
    os.sleep(4000)
  debug "blocker done"


# Login to a matrix server
proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))


# Spawn a subprocess, do some stdin/stdout and wait for it to die
#proc doProcess() {.cps:C.} =
#  info "subprocess starting"
#  let p = process.start("/usr/bin/rev", @[])
#  discard p.stdin.write("Reverse me")
#  p.stdin.close()
#  info "subprocess said: " & p.stdout.read(1024)
#  let status = p.wait()
#  info "subprocess done, status: $1", status


# Run all the tests
proc runStuff() {.cps:C.} =
  info("CpsTest firing up")
  spawn doServer()
  #spawn doClient("https://localhost:8443/hello")
  #spawn doTicker()
  #spawn doBlocker()
  #spawn doMatrix()
#  spawn doProcess()


var mylogger = newLogger(llDmp)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

