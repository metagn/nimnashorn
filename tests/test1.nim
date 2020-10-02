import nashorn

type Date = ref object
  year, month, day: int

bindTypeToClass(Date, java.util.Date)

let date = newJavaObject(Date)
print "the current year is", date.year + 1900