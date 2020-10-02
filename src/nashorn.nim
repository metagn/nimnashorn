import jsffi, macros, strutils

from sequtils import toSeq

var
  nashornFile* {.importc: "__FILE__".}: cstring
  nashornLine* {.importc: "__LINE__".}: cstring
  nashornDir* {.importc: "__DIR__".}: cstring
  nashornCommandLine* {.importc: "$$OPTIONS".}: js

when defined(nashornScripting):
  var
    args* {.importc: "$$ARG".}: JsAssoc[int, cstring]
    env* {.importc: "$$ENV".}: JsAssoc[cstring, cstring]
    latestOut* {.importc: "$$OUT".}: cstring
    latestErr* {.importc: "$$ERR".}: cstring
    latestExitCode* {.importc: "$$EXIT".}: cstring

  proc readLine*(prompt: cstring): cstring {.importc.}
  proc readFile*(filename: cstring): cstring {.importc: "readFully".}
  proc exec*(command: cstring): cstring {.importc: "$$EXEC".}

proc load*(script: cstring) {.importc.}
proc loadWithNewGlobal*(script: cstring) {.importc.}

proc print* {.importc, varargs.}
proc echo* {.importc, varargs.}

proc jsArrayOf*[T](args: varargs[T]): JsAssoc[int, T] {.importcpp: "(@)".}
proc jsArray*(args: varargs[typed]): JsAssoc[int, js] {.importcpp: "(@)".}

template `[]`*(_: type js, args: varargs[untyped]) = jsArray(args)

macro forEach*(name, iter, body: untyped): untyped =
  let sym = $genSym(nskVar, $name)
  let stmtl = newStmtList()
  let iterSym = genSym(ident = "iterValue")
  stmtl.add(newLetStmt(iterSym, iter))
  stmtl.add(newTree(nnkPragma, newColonExpr(ident"emit",
    newTree(nnkBracket,
      newLit("for each (var " & sym & " in "),
      iterSym,
      newLit(") {")))))
  stmtl.add(quote do:
    var `name` {.importc: `sym`.}: js)
  for x in body: stmtl.add(x)
  stmtl.add(newTree(nnkPragma, newColonExpr(ident"emit", newLit"}")))
  result = newBlockStmt(stmtl)

macro forEach*(nameIter: untyped{nkInfix}, body: untyped): untyped =
  result = getAst(forEach(nameIter[1], nameIter[2], body))

type
  JavaPackage* = ref object
  JavaClass* = ref object

{.push hint[XDeclaredButNotUsed]: off.}
type
  JavaWrapper* = concept type T
    mixin toJavaClass
    toJavaClass(type T) is JavaClass
{.pop.}

template toJavaClass*(jc: JavaClass): JavaClass = jc

proc javaToJs*(arg: auto): js {.importc: "Java.from".}
proc jsToJava*(arg: auto, class: JavaClass): js {.importc: "Java.to".}

template jsToJava*(arg: auto, T: typedesc): type(T) =
  jsToJava[T](arg, toJavaClass(type(T)))

template javaPackage*(packagePath: untyped): JavaPackage =
  var jpack: JavaPackage
  {.emit: [jpack, " = Packages.", astToStr(packagePath), ";"].}
  jpack

template javaClass*(packagePath: untyped): JavaClass =
  bind toJs, jsTypeOf
  var jclass: JavaClass
  {.emit: [jclass, " = Packages.", astToStr(packagePath), ";"].}
  jclass

proc javaType*(name: cstring): JavaClass {.importc: "Java.type".}
proc extend*(jc: JavaClass, args: js): JavaClass {.importc: "Java.extend".}
proc javaNew*(class: JavaClass): JsObject {.importcpp: "new (#)(@)", varargs.}
proc super*(anon: js): js {.importc: "Java.super".}

converter typedescToJavaClass*(T: typedesc[JavaWrapper]): JavaClass {.inline.} =
  mixin toJavaClass
  return toJavaClass(T)

proc typedescExpr(node: NimNode): NimNode =
  newTree(nnkBracketExpr, ident"typedesc", node)

macro bindTypeToClass*(nimType, class: untyped): untyped =
  result = newStmtList()

  let procNode = newProc(postfix(ident"toJavaClass", "*"),
    [bindSym"JavaClass", newIdentDefs(ident"_",
      typedescExpr(nimType), newEmptyNode())], newEmptyNode())
  procNode.pragma = newNimNode(nnkPragma)

  if class.kind == nnkDotExpr:
    procNode.addPragma(newColonExpr(ident"importcpp", newLit("(Packages." & repr(class) & ")")))
  else:
    # stores class so it doesnt have to call Java.type every time
    let storedClass = genSym(ident = "storedClass")
    result.add(newLetStmt(storedClass, newCall(bindSym"javaType",
      newCall(ident"cstring", class))))
    procNode.body = newStmtList(newTree(nnkReturnStmt, storedClass))
    procNode.addPragma(ident"inline")

  result.add(procNode)

macro newJavaObject*(T: typedesc[JavaWrapper], args: varargs[untyped]): untyped =
  let classMapper = newCall(ident("toJavaClass"), getTypeInst(T))
  let call = newCall(bindSym"javaNew", classMapper)
  for x in args: call.add(x)
  result = newCall(bindSym"to", call, getTypeInst(T))

proc afterLast(str: string, sub: char | set[char] | string): string {.compileTime.} =
  for a in rsplit(str, sub):
    return a

proc classWrapper(javaClass: string, typeName, body: NimNode): NimNode =
  result = newStmtList()

  var nimType: tuple[name: NimNode, private, noimport: bool]
  case typeName.kind
  of nnkIdent:
    nimType = (name: typeName, private: false, noimport: false)
  of nnkCurlyExpr:
    var temp = true
    for s in typeName:
      if temp:
        if s.kind == nnkIdent: nimType.name = s
        else: error("Invalid java class wrapper type name " & repr(s))
        temp = false
      elif s.kind == nnkIdent:
        if s.eqIdent"private":
          nimType.private = true
        elif s.eqIdent"noimport":
          nimType.noimport = true
  else:
    error("Don't know how to wrap java class to: " & repr(typeName))

  let name = nimType.name
  let noimport = nimType.noimport

  let typeLhs = if nimType.private: name else: postfix(name, "*")
  let javaClassVariableName = ident($name & "Class")
  let tjc = if nimType.private: ident"toJavaClass" else: postfix(ident"toJavaClass", "*")
  let jcv = newLit(javaClass)
  let jtb = bindSym"javaType"
  let tpdsc = typedescExpr(name)
  let jcvn =
    if nimType.private: 
      javaClassVariableName
    else:
      postfix(javaClassVariableName, "*")
  result.add(quote do:
    type `typeLhs` = ref object)
  if not noimport:
    result.add(newLetStmt(jcvn, newCall(jtb, jcv)))
    result.add(quote do:
      proc `tjc`(_: `tpdsc`): JavaClass {.inline.} = `javaClassVariableName`)

  for statement in body:
    var staticMember, imported = false
    case statement.kind
    of nnkProcDef..nnkConverterDef:
      var constructor = false

      for i, p in statement.pragma:
        if p.kind == nnkIdent:
          if p.eqIdent"classmember":
            if noimport:
              error("Import needed for classmember " & $statement[0] & " but option noimport was on")
            staticMember = true
          elif p.eqIdent"constructor":
            if noimport:
              error("Import needed for constructor " & $statement[0] & " but option noimport was on")
            constructor = true
          elif p.eqIdent"importcpp" or p.eqIdent"importc":
            imported = true
            continue
          else: continue
          statement.pragma.del(i)
        elif p.kind == nnkExprColonExpr and p[0].eqIdent"importcpp":
          imported = true

      let selfType = if staticMember: bindSym"JavaClass" else: name

      if constructor:
        let templ = newTree(nnkTemplateDef, statement[0], statement[1],
          statement[2], statement[3], statement[4], statement[5], statement[6])

        var variables: seq[NimNode] = @[]
        for i in 1 ..< templ.params.len:
          let idefs = templ.params[i]
          for i in 0 ..< idefs.len - 2:
            variables.add(idefs[i])

        templ.body = newStmtList(
          newCall(bindSym"to", newCall("javaNew", javaClassVariableName)
            .add(variables), newCall("type", name)))

        result.add(templ)
      else:
        statement.params.insert(1, newIdentDefs(ident"self", selfType, newEmptyNode()))
        if not imported or statement.body.kind != nnkEmpty: statement.addPragma(ident"importcpp")

        result.add(statement)
    of nnkVarSection, nnkLetSection:
      for identDefs in statement:
        let s = toSeq(identDefs)
        let lastVarIdentDefType = s[^2]
        var variables: seq[(NimNode, NimNode)] = @[]
        for i, v in s:
          if i == s.len - 2: break
          variables.add((v, lastVarIdentDefType))
        for variable in variables:
          let (p, t) = variable
          let (n, pr) = if p.kind == nnkPragmaExpr: (p[0], p[1]) else: (p, newEmptyNode())
          var importprag: NimNode
          var getter, setter = false

          for i, prag in pr:
            template eq(a): untyped = prag.eqIdent(a)
            if prag.kind == nnkIdent:
              if eq"classmember":
                if noimport:
                  error("Import needed for classmember " & $statement[0] & " but option noimport was on")
                staticMember = true
              elif eq"importcpp" or eq"importc":
                imported = true
                importprag = prag
              elif eq"getter":
                getter = true
              elif eq"setter":
                setter = true
              else: continue
              pr.del(i)
            elif prag.kind == nnkExprColonExpr and (prag[0].eqIdent"importcpp" or prag[0].eqIdent"importc"):
              imported = true
              importprag = prag

          if not (getter or setter):
            getter = true
            setter = statement.kind == nnkVarSection

          let selfType = if staticMember: bindSym"JavaClass" else: name

          var oldPragmas: seq[NimNode]
          oldPragmas.newSeq(pr.len)
          for i in 0 ..< pr.len:
            oldPragmas[i] = pr[i]
          let accessorPragmas = newTree(nnkPragma, if imported: importprag else: ident"importcpp").add(oldPragmas)

          if getter:
            let procz = newProc(n)
            procz.params = newTree(nnkFormalParams, t, newIdentDefs(ident"self", selfType))
            procz.pragma = copyNimNode(accessorPragmas)
            if not imported:
              let propName = if n.kind == nnkPostfix: $n[1] else: $n
              procz.pragma.add(newColonExpr(ident"importcpp", newLit("#." & propName)))
            result.add(procz)

          if setter:
            let setterName =
              if n.kind == nnkPostfix:
                let (a, b) = unpackPostfix(n)
                postfix(newTree(nnkAccQuoted, a, ident"="), b)
              else:
                newTree(nnkAccQuoted, n, ident"=")
            let procz = newProc(setterName)
            procz.params = newTree(nnkFormalParams, getType(void),
              newIdentDefs(ident"self", selfType),
              newIdentDefs(ident"value", t))
            procz.pragma = accessorPragmas
            result.add(procz)
    else: result.add(statement)

macro wrapClass*(javaClass, body: untyped): untyped =
  let javaClassName =
    case javaClass.kind
    of nnkCurlyExpr:
      repr(javaClass[0])
    of {nnkStrLit..nnkTripleStrLit}:
      javaClass.strVal
    else:
      repr(javaClass)

  var nimType: NimNode
  if javaClass.kind == nnkCurlyExpr:
    var x = javaClass[0]
    while x.kind == nnkDotExpr: x = x[^1]
    nimType = newTree(nnkCurlyExpr, x)
    for i in 1 ..< javaClass.len:
      nimType.add(javaClass[i])
  else:
    nimType = ident(javaClassName.afterLast('.'))

  result = classWrapper(javaClassName, nimType, body)

macro wrapClass*(javaClass, nimClass, body: untyped): untyped =
  let javaClassName =
    if javaClass.kind in {nnkStrLit..nnkTripleStrLit}:
      javaClass.strVal
    else:
      repr(javaClass)

  result = classWrapper(javaClassName, nimClass, body)