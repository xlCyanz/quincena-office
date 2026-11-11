# Horario de trabajo: qué días de la semana y entre qué horas se trabaja.
# Los días van de 0 (lunes) a 6 (domingo); se trabaja desde start_hour hasta end_hour,
# sin incluir end_hour (8 a 17 = de 8:00 a 16:59).
class_name WorkSchedule
extends RefCounted

var days: Array[int] = []
var start_hour: int = 0
var end_hour: int = 0


## Crea un horario desde un diccionario {"days", "start_hour", "end_hour"} (como en data/).
static func from_dict(data: Dictionary) -> WorkSchedule:
	var schedule := WorkSchedule.new()
	for day: Variant in data.get("days", []):
		schedule.days.append(int(day))
	schedule.start_hour = int(data.get("start_hour", 0))
	schedule.end_hour = int(data.get("end_hour", 0))
	return schedule


func to_dict() -> Dictionary:
	return {"days": days.duplicate(), "start_hour": start_hour, "end_hour": end_hour}


## Indica si a esa hora de ese día de la semana toca trabajar.
func is_working(weekday: int, hour: int) -> bool:
	return days.has(weekday) and hour >= start_hour and hour < end_hour


## Horas enteras que faltan, contando desde el inicio de la hora actual, hasta la
## próxima hora en que toca trabajar. Devuelve -1 si el horario no tiene ninguna.
@warning_ignore("integer_division")
func hours_until_next_work(weekday: int, hour: int) -> int:
	var hours_per_week: int = GameConstants.DAYS_PER_WEEK * GameConstants.HOURS_PER_DAY
	for offset: int in range(1, hours_per_week + 1):
		var total: int = hour + offset
		var day: int = (weekday + total / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK
		if is_working(day, total % GameConstants.HOURS_PER_DAY):
			return offset
	return -1
