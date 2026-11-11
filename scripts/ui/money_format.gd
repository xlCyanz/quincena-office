# Formato de cantidades de dinero para el jugador: $20,000 o −$240.
class_name MoneyFormat
extends RefCounted


static func format(amount: int) -> String:
	var digits: String = str(absi(amount))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return ("−$" if amount < 0 else "$") + ",".join(groups)
