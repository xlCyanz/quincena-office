# Horario: días (0 lunes … 6 domingo, en que empieza la jornada) y horas [start_hour, end_hour).
# Si end_hour ≤ start_hour cruza la medianoche. El almuerzo es la hora lunch_offset tras la
# entrada; overtime son las últimas horas de la jornada (staff.json: workday y overtime).
class_name WorkSchedule
extends RefCounted

const DAY_NAMES: Array[String] = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]

var days: Array[int] = []
var start_hour: int = 0
var end_hour: int = 0
## Horas extra al final de la jornada (incluidas entre start_hour y end_hour).
var overtime: int = 0


## Crea un horario desde {"days", "start_hour", "end_hour", "overtime"} (overtime opcional).
static func from_dict(data: Dictionary) -> WorkSchedule:
	var schedule := WorkSchedule.new()
	for day: Variant in data.get("days", []):
		if not schedule.days.has(int(day)):
			schedule.days.append(int(day))
	schedule.days.sort()
	schedule.start_hour = int(data.get("start_hour", 0))
	schedule.end_hour = int(data.get("end_hour", 0))
	schedule.overtime = clampi(int(data.get("overtime", 0)), 0, maxi(0, schedule.get_duration() - 1))
	return schedule


## Turno: entra a start_hour esos días; dura teams.shift_hours más las horas extra.
static func make_shift(start: int, shift_days: Array[int], extra_hours: int = 0) -> WorkSchedule:
	var duration: int = int(StaffCatalog.get_teams("shift_hours")) + extra_hours
	return from_dict({"days": shift_days, "start_hour": start,
		"end_hour": posmod(start + duration, GameConstants.HOURS_PER_DAY), "overtime": extra_hours})


func to_dict() -> Dictionary:
	return {"days": days.duplicate(), "start_hour": start_hour, "end_hour": end_hour, "overtime": overtime}


## Horas de cada jornada, con el almuerzo.
func get_duration() -> int:
	if days.is_empty():
		return 0
	var duration: int = posmod(end_hour - start_hour, GameConstants.HOURS_PER_DAY)
	return GameConstants.HOURS_PER_DAY if duration == 0 else duration


## Hora del día en que sale a almorzar.
func get_lunch_hour() -> int:
	return posmod(start_hour + get_lunch_offset(), GameConstants.HOURS_PER_DAY)


## Horas desde la entrada hasta el almuerzo (workday.lunch_offset).
static func get_lunch_offset() -> int:
	return int(StaffCatalog.get_workday("lunch_offset"))


## Horas que lleva la jornada en curso a esa hora (0 = la de entrada), o -1 si no hay.
func get_shift_hour(weekday: int, hour: int) -> int:
	var hours_per_week: int = GameConstants.DAYS_PER_WEEK * GameConstants.HOURS_PER_DAY
	var now: int = weekday * GameConstants.HOURS_PER_DAY + hour
	var duration: int = get_duration()
	for day: int in days:
		var since_start: int = posmod(now - (day * GameConstants.HOURS_PER_DAY + start_hour), hours_per_week)
		if since_start < duration:
			return since_start
	return -1


## Indica si esa hora de la jornada (como get_shift_hour) es extra.
func is_overtime_hour(shift_hour: int) -> bool:
	return overtime > 0 and shift_hour >= get_duration() - overtime


## Indica si una hora del día es de noche (overtime.night_start/night_end).
static func is_night_hour(hour: int) -> bool:
	var night_start: int = int(StaffCatalog.get_overtime("night_start"))
	var night_end: int = int(StaffCatalog.get_overtime("night_end"))
	return hour >= night_start or hour < night_end


## Horas de trabajo por jornada (sin almuerzo) que caen de noche.
func get_night_hours() -> int:
	if days.is_empty():
		return 0
	var count: int = 0
	for shift_hour: int in range(get_duration()):
		if shift_hour != get_lunch_offset() and is_night_hour(posmod(start_hour + shift_hour, GameConstants.HOURS_PER_DAY)):
			count += 1
	return count


## Indica si a esa hora y día hay jornada (el almuerzo cuenta).
func is_working(weekday: int, hour: int) -> bool:
	return get_shift_hour(weekday, hour) >= 0


## Indica si a esa hora le toca almorzar.
func is_lunch(weekday: int, hour: int) -> bool:
	return get_shift_hour(weekday, hour) == get_lunch_offset()


## Horas enteras desde el inicio de la actual hasta la próxima de trabajo; -1 si no hay.
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
	var text: String = "%s %d:00–%d:00" % [day_text, start_hour, end_hour]
	if overtime > 0:
		text += " (%d h extra)" % overtime
	return text
