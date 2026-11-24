# Original QuickSettings artwork, EolnMsuk, 2026. See ../LICENSE.
# Local vector paths and typography exported through Windows System.Drawing.
# Run from any directory with PowerShell on Windows; no network or extra modules.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\quicksettingsprefs\Resources'))

function Color([string]$hex) { return [Drawing.ColorTranslator]::FromHtml($hex) }
function RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = [Drawing.Drawing2D.GraphicsPath]::new()
    $d = 2 * $r
    $p.AddArc($x,$y,$d,$d,180,90)
    $p.AddArc(($x+$w-$d),$y,$d,$d,270,90)
    $p.AddArc(($x+$w-$d),($y+$h-$d),$d,$d,0,90)
    $p.AddArc($x,($y+$h-$d),$d,$d,90,90)
    $p.CloseFigure()
    return ,$p
}
function DrawMark([Drawing.Graphics]$g, [single]$x, [single]$y, [single]$size) {
    $saved = $g.Save()
    $g.TranslateTransform($x,$y)
    $g.ScaleTransform(($size/1024),($size/1024))
    $tile = RoundPath 0 0 1024 1024 224
    $gradient = [Drawing.Drawing2D.LinearGradientBrush]::new(
        [Drawing.PointF]::new(0,0),[Drawing.PointF]::new(1024,1024),(Color '#2877F4'),(Color '#08BCAA'))
    $g.FillPath($gradient,$tile)
    $inner = RoundPath 158 170 708 684 142
    $pen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(110,255,255,255),34)
    $g.DrawPath($pen,$inner)
    $gear = [Drawing.Drawing2D.GraphicsPath]::new([Drawing.Drawing2D.FillMode]::Alternate)
    $points = [Collections.Generic.List[Drawing.PointF]]::new()
    for ($i=0; $i -lt 80; $i++) {
        $angle = ($i*2*[Math]::PI/80)-[Math]::PI/2
        $radius = if (($i % 8) -in @(0,1,2,3)) { 238 } else { 198 }
        $points.Add([Drawing.PointF]::new([single](511+$radius*[Math]::Cos($angle)),[single](563+$radius*[Math]::Sin($angle))))
    }
    $gear.AddPolygon($points.ToArray())
    $gear.AddEllipse([single]420,[single]472,[single]182,[single]182)
    $white = [Drawing.SolidBrush]::new((Color '#F5FEFF'))
    $g.FillPath($white,$gear)
    $arrow = [Drawing.Pen]::new((Color '#F5FEFF'),55)
    $arrow.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $arrow.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $arrow.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
    $g.DrawLine($arrow,650,350,824,176)
    $g.DrawLines($arrow,[Drawing.PointF[]]@([Drawing.PointF]::new(687,176),[Drawing.PointF]::new(824,176),[Drawing.PointF]::new(824,313)))
    foreach ($item in @($arrow,$white,$gear,$pen,$inner,$gradient,$tile)) { $item.Dispose() }
    $g.Restore($saved)
}
function NewCanvas([int]$width,[int]$height) {
    $bitmap = [Drawing.Bitmap]::new($width,$height,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return @($bitmap,$g)
}
function SaveCanvas($canvas,[string]$name) {
    $canvas[0].Save((Join-Path $assetDirectory $name),[Drawing.Imaging.ImageFormat]::Png)
    $canvas[1].Dispose()
    $canvas[0].Dispose()
}

$icon = NewCanvas 1024 1024
DrawMark $icon[1] 0 0 1024
# Downsample from the same full-resolution mark for all Settings scales.
foreach ($entry in @(@('icon.png',29),@('icon@2x.png',58),@('icon@3x.png',87))) {
    $small = NewCanvas $entry[1] $entry[1]
    $small[1].DrawImage($icon[0],[Drawing.Rectangle]::new(0,0,$entry[1],$entry[1]),0,0,1024,1024,[Drawing.GraphicsUnit]::Pixel)
    SaveCanvas $small $entry[0]
}
SaveCanvas $icon 'package-icon.png'

foreach ($style in @('dark','light','sileo-dark')) {
    $canvas = NewCanvas 1600 600
    $g = $canvas[1]
    $light = $style -eq 'light'
    $scale = if ($style -eq 'sileo-dark') { 0.86 } else { 1.0 }
    $centerY = if ($style -eq 'sileo-dark') { 330 } else { 300 }
    $background = [Drawing.Drawing2D.LinearGradientBrush]::new(
        [Drawing.Rectangle]::new(0,0,1600,600),(Color $(if ($light) {'#F5FAFF'} else {'#0C1728'})),
        (Color $(if ($light) {'#E4F5F5'} else {'#122D42'})),[single]18)
    $g.FillRectangle($background,0,0,1600,600)
    $accent = [Drawing.Pen]::new([Drawing.Color]::FromArgb($(if ($light) {20} else {18}),34,174,207),2)
    foreach ($diameter in @(520,760,1000)) {
        $g.DrawEllipse($accent,[single](1510-$diameter/2),[single](30-$diameter/2),[single]$diameter,[single]$diameter)
    }
    $titleFont = [Drawing.Font]::new('Segoe UI',[single](112*$scale),[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    $subtitleFont = [Drawing.Font]::new('Segoe UI',[single](34*$scale),[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
    $authorFont = [Drawing.Font]::new('Segoe UI',[single](30*$scale),[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
    $titleSize = $g.MeasureString('QuickSettings',$titleFont)
    $markSize = [single](300*$scale)
    $gap = [single](65*$scale)
    $groupWidth = $markSize+$gap+$titleSize.Width
    $left = [single]((1600-$groupWidth)/2)
    DrawMark $g $left ([single]($centerY-$markSize/2)) $markSize
    $textX = [single]($left+$markSize+$gap)
    $textTop = [single]($centerY-137*$scale)
    $titleBrush = [Drawing.SolidBrush]::new((Color $(if ($light) {'#14334B'} else {'#F5FCFF'})))
    $subtitleBrush = [Drawing.SolidBrush]::new((Color $(if ($light) {'#365D73'} else {'#B4D1E1'})))
    $authorBrush = [Drawing.SolidBrush]::new((Color $(if ($light) {'#436B7A'} else {'#81B6C7'})))
    $g.DrawString('QuickSettings',$titleFont,$titleBrush,$textX,$textTop)
    $g.DrawString('App settings. One press away.',$subtitleFont,$subtitleBrush,$textX,([single]($textTop+155*$scale)))
    $g.DrawString('by EolnMsuk',$authorFont,$authorBrush,$textX,([single]($textTop+216*$scale)))
    foreach ($item in @($titleFont,$subtitleFont,$authorFont,$titleBrush,$subtitleBrush,$authorBrush,$accent,$background)) { $item.Dispose() }
    SaveCanvas $canvas "banner-$style.png"
}
Write-Output "Exported original icons and 1600 x 600 banners to $assetDirectory"
