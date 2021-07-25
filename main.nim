
# Main program
#
# This is just a bunch of snippets to test all the underlying
# CPS and IO stuff

from os import nil
import posix
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger, process, conn

const log_tag = "main"


# HTTP server serving on both HTTP port 8080 and HTTPS port 8443

proc onHttpRoot(rw: http.ResponseWriter) {.cps:C.} =
  rw.write("Hello, world!\r\n");

# TODO #183: This is clumsy, we need a better way for doing cps-compatible
# callbacks
proc genHttpRoot(rw: ResponseWriter): C =
  whelp onHttpRoot(rw)

proc doServer() {.cps:C.} =
  let hs = newHttpServer()
  hs.addPath "/hello", genHttpRoot
  spawn hs.listenAndServe("::", "8080")
  spawn hs.listenAndServe("::", "8443", "cert.pem")
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
proc doProcess() {.cps:C.} =
  info "subprocess starting"
  let p = process.start("/usr/bin/rev", @[])
  discard p.stdin.write("Reverse me")
  p.stdin.close()
  info "subprocess said: " & p.stdout.read(1024)
  let status = p.wait()
  info "subprocess done, status: $1", status


# Run all the tests
proc runStuff() {.cps:C.} =
  info("CpsTest firing up")
  spawn doServer()
  spawn doClient("https://localhost:8443/hello")
  spawn doTicker()
  spawn doBlocker()
  spawn doMatrix()
  spawn doProcess()


var mylogger = newLogger(llDmp)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

