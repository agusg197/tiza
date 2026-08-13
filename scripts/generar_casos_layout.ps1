# Genera los layouts hostiles del paso 7 como imágenes.
#
#   .\scripts\generar_casos_layout.ps1 -Destino .\casos
#
# Son los mismos cuatro casos que test/xy_cut_test.dart cubre con geometría escrita a
# mano, pero como PNG. La diferencia no es cosmética: los tests usan cajas
# idealizadas, y MLKit devuelve cajas cuyo alto depende de si el renglón tiene
# ascendentes y descendentes (medido en el paso 3: ±20% sobre texto impreso perfecto).
# La condición de "canaleta >= 4 alturas de texto" se apoya justo en esa altura, así
# que conviene verificarla contra las cajas de verdad y no contra las que yo elegí.
#
# Después de generarlos, por cada uno: empujarlo al dispositivo, pasarlo por la app y
# tocar GUARDAR COMO FIXTURE. El README explica el flujo completo.

param(
    [string]$Destino = "casos"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ancho = 1200
$alto = 1600

# Cada caso es una lista de renglones: texto, puntos, x, y.
$casos = @{
    'tres-columnas' = @(
        @('Roadmap Q3', 54, 80, 60),
        @('Backend', 34, 100, 250),
        @('cola de jobs', 22, 140, 330),
        @('cache de sesiones', 22, 140, 380),
        @('migrar postgres', 22, 140, 430),
        @('Mobile', 34, 560, 250),
        @('camara nueva', 22, 600, 330),
        @('offline', 22, 600, 380),
        @('Infra', 34, 940, 250),
        @('terraform', 22, 980, 330),
        @('alertas', 22, 980, 380)
    )
    'columnas-desparejas' = @(
        @('Retro sprint 14', 54, 80, 60),
        @('Salio bien', 34, 100, 230),
        @('deploy sin downtime', 22, 140, 310),
        @('menos bugs', 22, 140, 360),
        @('buena comunicacion', 22, 140, 410),
        @('demo a tiempo', 22, 140, 460),
        # Arranca más abajo y tiene menos renglones: ordenar por y intercala fuerte.
        @('A mejorar', 34, 680, 380),
        @('estimaciones', 22, 720, 460),
        @('tests lentos', 22, 720, 510)
    )
    'secciones-indentadas' = @(
        # El caso del bug: encabezados cortos con bullets corridos a la derecha. El
        # hueco de sangría pasa el 4% del ancho, y sin la condición de las alturas de
        # texto el algoritmo lo cortaba como si fueran dos columnas.
        @('Notas de la reunion', 54, 80, 60),
        @('Objetivos', 34, 100, 230),
        @('cerrar la propuesta', 22, 340, 310),
        @('revisar el pricing', 22, 340, 360),
        @('hablar con compras', 22, 340, 410),
        @('Riesgos', 34, 100, 500),
        @('el cliente no confirma', 22, 340, 580),
        @('falta el legal', 22, 340, 630)
    )
    'canaleta-angosta' = @(
        # Dos columnas con la canaleta por debajo del umbral: el algoritmo no corta y
        # las columnas se intercalan. Es un límite conocido, no un bug.
        @('Decision', 54, 80, 60),
        @('Pros', 34, 100, 230),
        @('es rapido pero hay que mantenerlo', 22, 100, 310),
        @('el equipo ya lo conoce bien', 22, 100, 360),
        @('Contras', 34, 520, 230),
        @('poco flexible', 22, 520, 410),
        @('sin soporte', 22, 520, 460)
    )
}

# Acepta tanto una ruta relativa como una absoluta: Join-Path sobre una ruta que ya
# es absoluta produce algo que GetFullPath rechaza.
$carpeta = if ([System.IO.Path]::IsPathRooted($Destino)) {
    [System.IO.Path]::GetFullPath($Destino)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Destino))
}
if (-not (Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta | Out-Null }

$negro = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)

foreach ($nombre in $casos.Keys | Sort-Object) {
    $bmp = New-Object System.Drawing.Bitmap($ancho, $alto)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $g.TextRenderingHint = 'AntiAliasGridFit'

    foreach ($renglon in $casos[$nombre]) {
        $fuente = New-Object System.Drawing.Font('Segoe UI', [single]$renglon[1])
        $g.DrawString($renglon[0], $fuente, $negro, [single]$renglon[2], [single]$renglon[3])
        $fuente.Dispose()
    }

    $ruta = Join-Path $carpeta "$nombre.png"
    $bmp.Save($ruta, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    "$nombre.png"
}

$negro.Dispose()
"Escritos en: $carpeta"
