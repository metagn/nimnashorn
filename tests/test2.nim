import nashorn

wrapClass java.util.Date{private}:
  var year, month, day: int
  proc newDate(): Date {.constructor.}
  proc newDate(year, month, day: int): Date {.constructor.}
  proc parse(s: cstring): Date {.classmember.}
  proc after(`when`: Date): bool
  converter toString: cstring {.importcpp.}

let date = newDate()
print "did you know that the current year is", date.year + 1990

let askedDate = readLine("you should give me a date so i can parse it")
try:
  print "lol i think you gave me:", Date.parse(askedDate).toString()
except:
  print "wow. thanks for the crappy date. loser"

let
  date1 = newDate(99, 7, 4)
  date2 = newDate(7, 1, 30)
print "hmm i wonder if", date2.toString(), "was after",
  date1.toString() & cstring".... the truth of that is", date2.after(date1)