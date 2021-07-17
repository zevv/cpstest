
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient, matrix, resolver

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    echo rsp
    let body = client.readBody(rsp)
  except OSError as e:
    echo "Could not connect to ", url, ": ", e.msg

# A simple periodic ticker
proc ticker() {.cps:C.} =
  while true:
    echo "tick"
    sleep(0.25)

# Offload blocking os.sleep() to a different thread
proc blocker() {.cps:C.} =
  while true:
    echo "block"
    onThread:
      os.sleep(4000)
    jield()

proc doMatrix() {.cps:C.} =
  let mc = newMatrixClient("matrix.org")
  mc.login("zevver", os.getenv("matrix_password"))

proc runStuff() {.cps:C.} =
  spawn newHttpServer().listenAndServe(8080)
  spawn client("https://zevv.nl/")
  spawn ticker()
  spawn blocker()
  spawn doMatrix()

var myevq = newEvq()
myevq.spawn runStuff()
myevq.run()

