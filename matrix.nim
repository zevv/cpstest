
# https://matrix.org/docs/guides/client-server-api


# Main program

from os import nil
import json
import cps
import types, evq, http, httpserver, httpclient

type

  MatrixClient = ref object
    url: string
    token: string

  MatrixLoginReq = object
    `type`: string
    user: string
    password: string
   

proc newMatrixClient(server: string): MatrixClient =
  let mc =MatrixClient(
    url: "http://" & server & "/_matrix/client/r0/"
  )
  echo mc.url
  mc

proc doRequest(mc: MatrixClient, meth: string, req: JsonNode) {.cps:C.} =
  let client = httpClient.newClient()
  let rsp = client.request("POST", mc.url & meth, $req)
  echo rsp
  echo rsp.body

proc login(mc: MatrixClient, user, password: string) {.cps:C.} =
  let req = % MatrixLoginReq(
    type: "m.login.password",
    user: user,
    password: password
  )

  mc.doRequest("login", req)

proc matrix() {.cps:C.} =

  let mc = newMatrixClient("tchncs.de")
  mc.login("zevv", "123qwe!@#QWE")


