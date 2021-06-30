
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient

# Perform an async http request
proc client() {.cps:C.} =
  let client = httpClient.newClient()
  let rsp = client.get("http://zevv.nl/")
  echo rsp

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



var myevq = newEvq()

myevq.push whelp newHttpServer().listenAndServe(8080)
myevq.push whelp client()
myevq.push whelp ticker()
myevq.push whelp blocker()

myevq.run()
