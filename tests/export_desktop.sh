#!/bin/sh
# Exporta los presets de export_presets.cfg a build/, revisa cada paquete con tests/export_check.gd
# y en macOS arranca la app sin ventana buscando errores. Necesita las plantillas de exportación.
# Uso: tests/export_desktop.sh [ruta de Godot]
set -u
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tests/export_check.gd"
FAILED=0

cd "$ROOT" || exit 1
rm -rf build/macos build/windows build/linux
mkdir -p build/macos build/windows build/linux

export_preset() {
	# $1 preset, $2 ruta de salida
	if ! "$GODOT" --headless --path "$ROOT" --export-release "$1" "$2" > "build/export_$3.log" 2>&1; then
		echo "FALLO: no se pudo exportar $1 (ver build/export_$3.log)"
		FAILED=1
		return 1
	fi
	if grep -q "ERROR" "build/export_$3.log"; then
		echo "FALLO: errores al exportar $1:"
		grep "ERROR" "build/export_$3.log" | head -5
		FAILED=1
	fi
	echo "Exportado $1 → $2"
}

check_pack() {
	# $1 nombre, $2 paquete .pck
	if [ ! -f "$2" ]; then
		echo "FALLO: falta el paquete de $1 ($2)"
		FAILED=1
		return
	fi
	# Desde una carpeta vacía: --main-pack busca en la carpeta actual lo que falta en el paquete.
	EMPTY="$ROOT/build/check_run"
	rm -rf "$EMPTY" && mkdir -p "$EMPTY"
	OUT="$(cd "$EMPTY" && "$GODOT" --headless --main-pack "$ROOT/$2" -s "$CHECK" 2>&1)"
	if echo "$OUT" | grep -q "EXPORTACIÓN: OK"; then
		echo "$1: el paquete llega al menú sin herramientas de desarrollo"
	else
		echo "FALLO: revisión del paquete de $1:"
		echo "$OUT" | grep -v "^$" | tail -15
		FAILED=1
	fi
}

export_preset "macOS" "build/macos/Quincena Office.zip" macos
export_preset "Windows" "build/windows/Quincena Office.exe" windows
export_preset "Linux" "build/linux/quincena_office.x86_64" linux

check_pack "Windows" "build/windows/Quincena Office.pck"
check_pack "Linux" "build/linux/quincena_office.pck"

if [ -f "build/macos/Quincena Office.zip" ]; then
	(cd build/macos && unzip -q -o "Quincena Office.zip")
	APP="build/macos/Quincena Office.app"
	check_pack "macOS" "$APP/Contents/Resources/Quincena Office.pck"
	if [ "$(uname)" = "Darwin" ]; then
		# Arranca sin ventana y no da errores.
		RUN="$("$APP/Contents/MacOS/Quincena Office" --headless --quit-after 120 2>&1)"
		CODE=$?
		if [ $CODE -ne 0 ] || echo "$RUN" | grep -q "ERROR"; then
			echo "FALLO: la aplicación de macOS no arrancó limpia (código $CODE):"
			echo "$RUN" | tail -10
			FAILED=1
		elif echo "$RUN" | grep -qi "panku"; then
			echo "FALLO: la aplicación de macOS cargó la consola Panku"
			FAILED=1
		else
			echo "macOS: la aplicación de lanzamiento arranca sin errores"
		fi
	fi
fi

if [ $FAILED -eq 0 ]; then
	echo "RESULTADO: OK"
else
	echo "RESULTADO: FALLO"
fi
exit $FAILED
