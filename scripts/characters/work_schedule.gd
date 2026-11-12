# Horario de trabajo: qué días de la semana y entre qué horas se trabaja.
# Los días van de 0 (lunes) a 6 (domingo) y son los días en que empieza cada jornada; se
# trabaja desde start_hour hasta end_hour, sin incluir end_hour (8 a 17 = de 8:00 a
# 16:59). Si end_hour no pasa de start_hour la jornada cruza la medianoche (22 a 7 =
# de 22:00 hasta las 6:59 del día siguiente).
#
# El almuerzo es una hora dentro de la jornada: la que cae lunch_offset horas después de
# la entrada (data/staff.json, workday). Durante esa hora el empleado sale.
class_name WorkSchedule
extends RefCounted

const DAY_NAMES: Array[String] = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]

var days: Array[int] = []
var start_hour: int = 0
var end_hour: int = 0


## Crea un horario desde un diccionario {"days", "start_hour", "end_hour"} (como en data/).
static func from_dict(data: Dictionary) -> WorkSchedule:
	var schedule := WorkSchedule.new()
	for day: Variant in data.get("days", []):
		if not schedule.days.has(int(day)):
			schedule.days.append(int(day))
	schedule.days.sort()
	schedule.start_hour = int(data.get("start_hour", 0))
	schedule.end_hour = int(data.get("end_hour", 0))
	return schedule


## Horario de un turno de equipo: entra a start_hour esos días y la salida la marca la
## duración de la jornada (data/staff.json, teams.shift_hours).
static func make_shift(start: int, shift_days: Array[int]) -> WorkSchedule:
	var duration: int = int(StaffCatalog.get_teams("shift_hours"))
	return from_dict({"days": shift_days, "start_hour": start,
		"end_hour": posmod(start + duration, GameConstants.HOURS_PER_DAY)})


func to_dict() -> Dictionary:
	return {"days": days.duplicate(), "start_hour": start_hour, "end_hour": end_hour}


## Horas que dura cada jornada, contando el almuerzo.
func get_duration() -> int:
	if days.is_empty():
		return 0
	var duration: int = posmod(end_hour - start_hour, GameConstants.HOURS_PER_DAY)
	return GameConstants.HOURS_PER_DAY if duration == 0 else duration


## Hora del día en que sale a almorzar.
func get_lunch_hour() -> int:
	return posmod(start_hour + get_lunch_offset(), GameConstants.HOURS_PER_DAY)


## Horas desde la entrada hasta el almuerzo (data/staff.json, workday.lunch_offset).
static func get_lunch_offset() -> int:
	return int(StaffCatalog.get_workday("lunch_offset"))


## Cuántas horas lleva la jornada que está en curso a esa hora (0 = la de entrada), o
## -1 si a esa hora no hay jornada.
func get_shift_hour(weekday: int, hour: int) -> int:
	var hours_per_week: int = GameConstants.DAYS_PER_WEEK * GameConstants.HOURS_PER_DAY
	var now: int = weekday * GameConstants.HOURS_PER_DAY + hour
	var duration: int = get_duration()
	for day: int in days:
		var since_start: int = posmod(now - (day * GameConstants.HOURS_PER_DAY + start_hour), hours_per_week)
		if since_start < duration:
			return since_start
	return -1


## Indica si a esa hora de ese día de la semana hay jornada (la hora del almuerzo cuenta).
func is_working(weekday: int, hour: int) -> bool:
	return get_shift_hour(weekday, hour) >= 0


## Indica si a esa hora le toca almorzar.
func is_lunch(weekday: int, hour: int) -> bool:
	return get_shift_hour(weekday, hour) == get_lunch_offset()


## Horas enteras que faltan, contando desde el inicio de la hora actual, hasta la
## próxima hora en que toca trabajar. Devuelve -1 si el horario no tiene ninguna.
func hours_until_next_work(weekday: int, hour: int) -> int:
	var hours_per_week: int = GameConstants.DAYS_PER_WEEK * GameConstants.HOURS_PER_DAY
	for offset: int in range(1, hours_per_week + 1):
		var total: int = hour + offset
		@warning_ignore("integer_division")
		var day: int = (weekday + total / GameConstants.HOURS_PER_DAY) % GameConstants.DAYS_PER_WEEK
		if is_working(day, total % GameConstants.HOURS_PER_DAY):
			return offset
	return -1


## Texto para el jugador: "lun–vie 8:00–17:00" o "lun, mié 9:00–13:00".
func describe() -> String:
	if days.is_empty():
		return "sin horario"
	var consecutive: bool = days[-1] - days[0] == days.size() - 1
	var day_text: String
	if consecutive and days.size() > 2:
		day_text = "%s–%s" % [DAY_NAMES[days[0]], DAY_NAMES[days[-1]]]
	else:
		var names: Array[String] = []
		for day: int in days:
			names.append(DAY_NAMES[day])
		day_text = ", ".join(names)
	return "%s %d:00–%d:00" % [day_text, start_hour, end_hour]
