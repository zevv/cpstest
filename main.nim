
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger

const log_tag = "main"

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    info $rsp
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

proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))

proc runStuff() {.cps:C.} =
  info("CpsTest firing up")
  spawn newHttpServer().listenAndServe(8080)
  spawn client("http://127.0.0.1:8080")
  spawn client("https://zevv.nl/")
  spawn ticker()
  spawn blocker()
  spawn doMatrix()

var mylogger = newLogger(llDmp)
var myevq = newEvq(mylogger)
myevq.spawn runStuff()
myevq.run()

