
# https://matrix.org/docs/guides/client-server-api
# https://matrix.org/docs/spec/


# Main program

from os import nil
import json
import cps
import types, evq, http, httpserver, httpclient, logger

const log_tag = "matrix"

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
  MatrixClient(
    url: "https://" & server & "/_matrix/client/r0/"
  )


proc login*(mc: MatrixClient, user, password: string) {.cps:C.} =
  let req = % MatrixLoginReq(
    type: "m.login.password",
    user: user,
    password: password
  )

  let rsp = mc.post("login", req)
  if rsp.hasKey "user_id":
    let lr = rsp.to(MatrixLoginRsp)
    mc.token = lr.access_token
  else:
    warn $rsp["error"]


proc sync*(mc: MatrixClient) {.cps:C.} =
  let s = mc.get("sync?access_token=" & mc.token)
  echo s
