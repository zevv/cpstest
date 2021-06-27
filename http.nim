
import tables
import strutils

import cps

import bconn
import types

type
  Headers* = ref object
    headers*: Table[string, string]

proc read*(headers: Headers, br: Breader) {.cps:C.} =
  while true:
    let line = br.readLine()
    if line.len() == 0:
      break
    let ps = line.split(": ", 2)
    if ps.len == 2:
      headers.headers[ps[0].toLower] = ps[1]

proc write*(headers: Headers, bw: Bwriter) {.cps:C.} =
  var hs = ""
  for k, v in headers.headers:
    hs.add k & ": " & v & "\r\n"
  bw.write(hs)
  bw.write("\r\n")

proc getOrDefault*(headers: Headers, key: string, def: string): string =
  headers.headers.getOrDefault(key, def)

proc `$`*(headers: Headers): string =
  for k, v in headers.headers:
    result.add k & ": " & v & "\n"


