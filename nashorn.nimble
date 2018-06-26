# Package

version       = "0.1.0"
author        = "hlaaftana"
description   = "Nim bindings for Java Nashorn\'s JS API"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 0.18.0"

import ospaths

task buildTests, "builds tests":
  for f in listFiles("tests"):
    let (dir, name, ext) = splitFile(f)
    if ext == ".nim":
      exec "nim js -o:bin/" & name & ".js tests/" & name

task buildTestsRelease, "builds tests in release mode":
  for f in listFiles("tests"):
    let (dir, name, ext) = splitFile(f)
    if ext == ".nim":
      exec "nim js -d:release -o:bin/" & name & ".js tests/" & name