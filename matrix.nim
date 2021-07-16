
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
  
  MatrixLoginRsp = object
    user_id: string
    access_token: string
    home_server: string
    device_id: string



template debug(mc: MatrixClient, s: string) =
  discard

proc post(mc: MatrixClient, meth: string, req: JsonNode): JsonNode {.cps:C.} =
  let client = httpClient.newClient()
  mc.debug("< " & meth & ": " & $ req)
  let rsp = client.request("POST", mc.url & meth, $req)
  result = client.readBody(rsp).parseJson()
  mc.debug("> " & meth & ": " & $result)


proc get(mc: MatrixClient, meth: string): JsonNode {.cps:C.} =
  let client = httpClient.newClient()
  let rsp = client.request("GET", mc.url & meth)
  result = client.readBody(rsp).parseJson()
  mc.debug("> " & meth & ": " & $result)


proc newMatrixClient*(server: string): MatrixClient =
  let mc =MatrixClient(
    url: "https://" & server & "/_matrix/client/r0/"
  )
  echo mc.url
  mc

proc setToken*(mc: MatrixClient, token: string) =
  mc.token = token

proc login*(mc: MatrixClient, user, password: string) {.cps:C.} =
  let req = % MatrixLoginReq(
    type: "m.login.password",
    user: user,
    password: password
  )

  let lr = mc.post("login", req).to(MatrixLoginRsp)
  mc.token = lr.access_token


proc sync*(mc: MatrixClient) {.cps:C.} =
  let s = mc.get("sync?access_token=" & mc.token)
  echo s
