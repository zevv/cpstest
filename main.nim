
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient

# Perform an async http request
proc client(url: string) {.cps:C.} =
  try:
    let client = httpClient.newClient()
    let rsp = client.get(url)
    echo rsp
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



var myevq = newEvq()

myevq.push whelp newHttpServer().listenAndServe(8080)
myevq.push whelp client("http://zevv.nl/")
myevq.push whelp client("http://zovv.nl/")
myevq.push whelp ticker()
myevq.push whelp blocker()

myevq.run()

