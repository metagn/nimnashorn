import nashorn, jsffi

print jsArrayOf(1, 2, 3, 4, 5).jsToJava(javaType("int[]"))
print jsArray(1, 2, "a", "b")

forEach n in jsArrayOf(1, 2, 3, 4, 5):
  print n