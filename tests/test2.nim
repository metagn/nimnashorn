import nashorn, jsffi

wrapClass java.util.Date{private}:
  var year, month, day: int
  proc newDate(): Date {.constructor.}
  proc newDate(year, month, day: int): Date {.constructor.}
  proc parse(s: cstring): Date {.classmember.}
  proc after(`when`: Date): bool
  converter toString: cstring {.importcpp.}

let date = newDate()
print "the current year is", date.year + 1990

let askedDate = readLine("Please input date.")
try:
  print "Parsed date as: ", Date.parse(askedDate).toString()
except:
  print "Invalid date"

let
  date1 = newDate(99, 7, 4)
  date2 = newDate(7, 1, 30)
print "Is", date2.toString(), "after",
  date1.toString() & cstring"?", [false: "yes", true: "no"][date2.after(date1)]