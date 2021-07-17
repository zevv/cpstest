
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver, logger

const log_tag = "main"

var ll = newLogger(llDmp)

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    ll.info $rsp
    let body = client.readBody(rsp)
  except OSError as e:
    ll.warn "Could not connect to " & url & ": " & e.msg

# A simple periodic ticker
proc ticker() {.cps:C.} =
  while true:
    ll.debug "tick"
    sleep(0.25)

# Offload blocking os.sleep() to a different thread
proc blocker() {.cps:C.} =
  while true:
    ll.debug "block"
    onThread:
      os.sleep(4000)
    jield()

proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))

proc runStuff() {.cps:C.} =
  ll.info("CpsTest firing up")
  spawn newHttpServer(ll).listenAndServe(8080)
  spawn client("http://127.0.0.1:8080")
  spawn client("https://zevv.nl/")
  spawn ticker()
  spawn blocker()
  spawn doMatrix()

var myevq = newEvq()
myevq.spawn runStuff()
myevq.run()

