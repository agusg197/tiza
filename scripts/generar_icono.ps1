# Genera el ícono de launcher de Tiza: una T serif de tiza sobre terracota, con
# un subrayado trazado a mano.
#
# A 48 dp una letra se lee mejor que un objeto dibujado, y la T con serifas ata el
# ícono a la tipografía del encabezado de la app.
#
# Produce dos juegos:
#   - ic_launcher.png            full-bleed, para API 24-25 (minSdk es 24)
#   - ic_launcher_foreground.png transparente y con la obra dentro del 66% central,
#                                para el adaptive icon de API 26+
#
#   .\scripts\generar_icono.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$raiz = Split-Path -Parent $PSScriptRoot
$res = Join-Path $raiz 'android\app\src\main\res'

$terracota = [System.Drawing.Color]::FromArgb(255, 176, 84, 47)
$tiza = [System.Drawing.Color]::FromArgb(255, 246, 241, 230)

# Densidades de Android. El full-bleed usa 48 dp de base; el foreground del
# adaptive icon usa 108 dp, que es lo que pide la especificación.
$densidades = @(
    @{ dir = 'mipmap-mdpi';    factor = 1.0 },
    @{ dir = 'mipmap-hdpi';    factor = 1.5 },
    @{ dir = 'mipmap-xhdpi';   factor = 2.0 },
    @{ dir = 'mipmap-xxhdpi';  factor = 3.0 },
    @{ dir = 'mipmap-xxxhdpi'; factor = 4.0 }
)

function Dibujar {
    param(
        [int]$Lado,
        [bool]$ConFondo,
        [single]$AltoLetra,      # fracción del lado que ocupa la altura de la T
        [single]$SubrayadoY,     # altura del subrayado, en fracción del lado
        [single]$SubrayadoDesde, # extremos horizontales, en fracción del lado
        [single]$SubrayadoHasta
    )

    $bmp = New-Object System.Drawing.Bitmap($Lado, $Lado)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    if ($ConFondo) {
        $fondo = New-Object System.Drawing.SolidBrush($terracota)
        $g.FillRectangle($fondo, 0, 0, $Lado, $Lado)
        $fondo.Dispose()
    }

    $cx = $Lado / 2.0
    # La letra se sube un poco: el subrayado ocupa el espacio de abajo y el
    # conjunto queda ópticamente centrado.
    $cy = $Lado * 0.44

    # La T, centrada por los límites reales del glifo y no por sus métricas de
    # fuente, que traen espacio lateral desparejo.
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $familia = New-Object System.Drawing.FontFamily('Georgia')
    $formato = [System.Drawing.StringFormat]::GenericTypographic
    $path.AddString('T', $familia, [int][System.Drawing.FontStyle]::Bold, $Lado * 0.8,
        (New-Object System.Drawing.PointF(0, 0)), $formato)

    $limites = $path.GetBounds()
    $escala = ($Lado * $AltoLetra) / $limites.Height

    # GDI+ compone en Prepend: la última llamada se aplica primero. O sea, primero
    # centra el glifo en el origen, después escala, después lo lleva al centro.
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate($cx, $cy)
    $m.Scale($escala, $escala)
    $m.Translate(-($limites.X + $limites.Width / 2), -($limites.Y + $limites.Height / 2))
    $path.Transform($m)

    $pincelLetra = New-Object System.Drawing.SolidBrush($tiza)
    $g.FillPath($pincelLetra, $path)

    # El subrayado: una curva suave, como pasada con tiza de un solo movimiento.
    $alfa = [System.Drawing.Color]::FromArgb(150, $tiza.R, $tiza.G, $tiza.B)
    $lapiz = New-Object System.Drawing.Pen($alfa, [single]($Lado * 0.042))
    $lapiz.StartCap = 'Round'
    $lapiz.EndCap = 'Round'
    $y = $Lado * $SubrayadoY
    $x0 = $Lado * $SubrayadoDesde
    $x1 = $Lado * $SubrayadoHasta
    $tramo = $x1 - $x0
    $g.DrawBezier($lapiz,
        (New-Object System.Drawing.PointF([single]$x0, [single]$y)),
        (New-Object System.Drawing.PointF([single]($x0 + $tramo * 0.35), [single]($y - $Lado * 0.035))),
        (New-Object System.Drawing.PointF([single]($x0 + $tramo * 0.69), [single]($y + $Lado * 0.030))),
        (New-Object System.Drawing.PointF([single]$x1, [single]($y - $Lado * 0.010))))

    $lapiz.Dispose()
    $pincelLetra.Dispose()
    $path.Dispose()
    $familia.Dispose()
    $g.Dispose()
    return $bmp
}

foreach ($d in $densidades) {
    $carpeta = Join-Path $res $d.dir
    if (-not (Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta | Out-Null }

    # Full-bleed 48 dp: no hay máscara, así que la obra ocupa el cuadro entero.
    $lado = [int](48 * $d.factor)
    $bmp = Dibujar -Lado $lado -ConFondo $true -AltoLetra 0.44 `
        -SubrayadoY 0.755 -SubrayadoDesde 0.24 -SubrayadoHasta 0.76
    $bmp.Save((Join-Path $carpeta 'ic_launcher.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    # Foreground 108 dp. La máscara circular tiene radio 0.333 desde el centro, así
    # que a x=0.24 sólo llega hasta y=0.708 y un subrayado ancho y bajo se corta —
    # pasó de verdad en la primera versión. Acá va más corto y más arriba: a
    # x=0.34 el círculo llega a y=0.792, con margen sobre el trazo en y=0.66.
    $lado = [int](108 * $d.factor)
    $bmp = Dibujar -Lado $lado -ConFondo $false -AltoLetra 0.30 `
        -SubrayadoY 0.66 -SubrayadoDesde 0.34 -SubrayadoHasta 0.66
    $bmp.Save((Join-Path $carpeta 'ic_launcher_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    "$($d.dir): ic_launcher.png + ic_launcher_foreground.png"
}
