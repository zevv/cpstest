
# Main program

import strutils
import tables
import strformat

import cps

import types
import evq
import conn
import bconn
#import httpserver
import httpclient


proc ticker(evq: Evq) {.cps:C.} =
  let client = newHttpClient(evq)
  let rsp = client.get("http://nim-lang.org/index.html")
  while true:
    echo "tick"
    sleep(1.0)


var myevq = newEvq()

#myevq.push whelp httpserver.listenAndServe(myevq, 8080)
myevq.push whelp ticker(myevq)

myevq.run()
