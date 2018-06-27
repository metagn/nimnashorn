import nashorn

wrapClass javafx.scene.control.Button:
  var text*: cstring
  var onAction* {.setter.}: proc(): void
  proc newButton*: Button {.constructor.}

wrapClass FXList{noimport}:
  proc add* {.varargs.}

wrapClass javafx.scene.layout.StackPane:
  let children*: FXList
  proc newStackPane*: StackPane {.constructor.}

wrapClass javafx.scene.Scene:
  proc newScene*(root: auto, width, height: int): Scene {.constructor.}

wrapClass Stage{noimport}:
  var title*: cstring
  var scene*: Scene
  proc show*

var stage {.importc: "$$STAGE".}: Stage

stage.title = "Hello World!"

let button = newButton()
button.text = "Say 'Hello World'"
button.onAction = proc = print "Hello World!"

let root = newStackPane()
root.children.add(button)

stage.scene = newScene(root, 300, 250)
stage.show()