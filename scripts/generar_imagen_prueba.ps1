# Genera la imagen sintética con la que se midieron los hallazgos del paso 3:
# texto impreso, dos columnas, tres tamaños de fuente. No reemplaza a las fotos
# reales del golden set (paso 7) — sirve para tener un caso determinista donde el
# OCR no falla, y así aislar los problemas de la serialización de los del OCR.
#
#   .\scripts\generar_imagen_prueba.ps1 -Destino .\pizarron_test.png
#
# Para probarlo en un emulador:
#   adb push pizarron_test.png /sdcard/Pictures/pizarron_test.png
#   adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE `
#     -d file:///sdcard/Pictures/pizarron_test.png

param(
    [string]$Destino = "pizarron_test.png"
)

Add-Type -AssemblyName System.Drawing

$ancho = 1200
$alto = 1600

$bmp = New-Object System.Drawing.Bitmap($ancho, $alto)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$negro = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)

function Escribir([string]$texto, [single]$puntos, [single]$x, [single]$y) {
    $fuente = New-Object System.Drawing.Font('Segoe UI', $puntos)
    $g.DrawString($texto, $fuente, $negro, $x, $y)
    $fuente.Dispose()
}

# Título
Escribir 'Sprint planning' 54 80 60

# Columna izquierda
Escribir 'Objetivos' 34 100 220
Escribir 'cerrar el checkout' 22 140 300
Escribir 'migrar la base' 22 140 350
Escribir 'medir latencia' 22 140 400
Escribir 'Riesgos' 34 100 500
Escribir 'el proveedor no responde' 22 140 580

# Columna derecha — es la que revela que ordenar por `y` intercala las columnas
Escribir 'Action items' 34 640 220
Escribir 'Ana: revisar metricas' 22 680 300
Escribir 'Beto: deploy el viernes' 22 680 350
Escribir 'Cami: hablar con legales' 22 680 400

$ruta = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Destino))
$bmp.Save($ruta, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
$negro.Dispose()

"Escrito: $ruta"
