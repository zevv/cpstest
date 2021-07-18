
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger, process, conn

const log_tag = "main"

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    dump $rsp
    let body = client.readBody(rsp)
  except OSError as e:
    warn "Could not connect to " & url & ": " & e.msg

# A simple periodic ticker
proc ticker() {.cps:C.} =
  while true:
    debug "tick"
    sleep(1.0)

# Offload blocking os.sleep() to a different thread
proc blocker() {.cps:C.} =
  while true:
    debug "block"
    onThread:
      os.sleep(4000)
    jield()

# Login to a matrix server
proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))

# Spawn a subprocess, do some stdin/stdout and wait for it to die
proc doProcess() {.cps:C.} =
  info "subprocess starting"
  let p = runProcess("/usr/bin/rev", @[])
  let _ = p.stdin.write("Reverse me")
  p.stdin.close()
  info "subprocess said: " & p.stdout.read(1024)
  p.wait()
  info "subprocess done"

# Run all kinds of stuff
proc runStuff() {.cps:C.} =
  info("CpsTest firing up")
  spawn newHttpServer().listenAndServe(8080)
  spawn client("http://127.0.0.1:8080")
  spawn client("https://zevv.nl/")
  spawn ticker()
  spawn blocker()
  spawn doMatrix()
  spawn doProcess()


var mylogger = newLogger(llDmp)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

