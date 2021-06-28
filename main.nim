
# Main program

import cps
import types, evq, http, httpserver, httpclient


proc ticker() {.cps:C.} =
  let client = httpClient.newClient()
  let rsp = client.get("http://zevv.nl/")
  echo rsp
  while true:
    echo "tick"
    sleep(1.0)


var myevq = newEvq()

myevq.push whelp newHttpServer().listenAndServe(8080)
myevq.push whelp ticker()

myevq.run()
