
# Main program
#
# This is just a bunch of snippets to test all the underlying
# CPS and IO stuff

from os import nil
import posix
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger, process, conn

const log_tag = "main"

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    debug $rsp
    let body = client.readBody(rsp)
  except OSError as e:
    warn "Could not connect to " & url & ": " & e.msg


# A simple periodic ticker
proc ticker() {.cps:C.} =
  var n = 0
  while n < 5:
    sleep(1.0)
    inc n
    debug "tick $1", n


# Offload blocking os.sleep() to a different thread
proc blocker() {.cps:C.} =
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
  spawn newHttpServer().listenAndServe("::", "8080")
  spawn newHttpServer().listenAndServe("::", "8443", "cert.pem")
  sleep(0.1)
  spawn client("https://localhost:8443")
  spawn ticker()
  spawn blocker()
  spawn doMatrix()
  spawn doProcess()


var mylogger = newLogger(llDmp)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

