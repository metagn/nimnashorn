import nashorn

type Date = ref object
  year, month, day: int

bindTypeToClass(Date, java.util.Date)

let date = newJavaObject(Date)
print "did you know that the current year is", date.year + 1900