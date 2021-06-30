
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient

proc client() {.cps:C.} =
  let client = httpClient.newClient()
  let rsp = client.get("http://zevv.nl/")
  echo rsp


proc ticker() {.cps:C.} =
  while true:
    echo "tick"
    sleep(0.25)


var myevq = newEvq()

myevq.push whelp newHttpServer().listenAndServe(8080)
myevq.push whelp client()
myevq.push whelp ticker()

myevq.run()
