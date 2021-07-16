
# Main program

from os import nil
import cps
import types, evq, http, httpserver, httpclient, matrix

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


proc doMatrix() {.cps:C.} =
  when true:
    let mc = newMatrixClient("matrix.org")
    mc.login("zevver", os.getenv("matrix_password"))
  else:
    let mc = newMatrixClient("tchncs.de")
    mc.login("zevv", os.getenv("matrix_password"))
    #mc.setToken("syt_emV2dmVy_VvTvLIyKgDxtdOIyYXYO_0Mc2Qe")
  mc.sync()



var myevq = newEvq()

#myevq.push whelp newHttpServer().listenAndServe(8080)
#myevq.push whelp client("https://zevv.nl/")
#myevq.push whelp ticker()
#myevq.push whelp blocker()

myevq.push whelp doMatrix()

myevq.run()

