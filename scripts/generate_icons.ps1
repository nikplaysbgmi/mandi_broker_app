Add-Type -AssemblyName System.Drawing

$srcPath = Resolve-Path "assets\icon\app_icon.png"
$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$w = $src.Width
$h = $src.Height

# Create base 1024x1024 24bpp (no alpha, 100% opaque) master image
$master = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($master)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# Gradient background (top amber to bottom maroon)
$topColor = [System.Drawing.Color]::FromArgb(255, 213, 89, 38)
$botColor = [System.Drawing.Color]::FromArgb(255, 124, 26, 9)
$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $topColor, $botColor, 90.0)
$g.FillRectangle($brush, $rect)
$brush.Dispose()

# Draw source icon
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose()

function Save-Icon($bmp, $targetWidth, $targetHeight, $destPath) {
    # 24bpp ensures zero transparency / alpha=255 on every single pixel
    $target = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $tg = [System.Drawing.Graphics]::FromImage($target)
    $tg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $tg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $tg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $tRect = New-Object System.Drawing.Rectangle(0, 0, $targetWidth, $targetHeight)
    $tBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($tRect, $topColor, $botColor, 90.0)
    $tg.FillRectangle($tBrush, $tRect)
    $tBrush.Dispose()

    $wrapMode = New-Object System.Drawing.Imaging.ImageAttributes
    $wrapMode.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $destRect = New-Object System.Drawing.Rectangle(0, 0, $targetWidth, $targetHeight)
    $tg.DrawImage($bmp, $destRect, 0, 0, $bmp.Width, $bmp.Height, [System.Drawing.GraphicsUnit]::Pixel, $wrapMode)
    $wrapMode.Dispose()
    $tg.Dispose()
    
    $dir = [System.IO.Path]::GetDirectoryName($destPath)
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $target.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $target.Dispose()
    Write-Host "Generated: $destPath ($targetWidth x $targetHeight)"
}

function Save-Maskable($bmp, $targetSize, $destPath) {
    $target = New-Object System.Drawing.Bitmap($targetSize, $targetSize, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $tg = [System.Drawing.Graphics]::FromImage($target)
    $tg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $tg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $tg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $mRect = New-Object System.Drawing.Rectangle(0, 0, $targetSize, $targetSize)
    $mBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($mRect, $topColor, $botColor, 90.0)
    $tg.FillRectangle($mBrush, $mRect)
    $mBrush.Dispose()

    $pad = [int]($targetSize * 0.1)
    $innerSize = $targetSize - ($pad * 2)
    $wrapMode = New-Object System.Drawing.Imaging.ImageAttributes
    $wrapMode.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $destRect = New-Object System.Drawing.Rectangle($pad, $pad, $innerSize, $innerSize)
    $tg.DrawImage($bmp, $destRect, 0, 0, $bmp.Width, $bmp.Height, [System.Drawing.GraphicsUnit]::Pixel, $wrapMode)
    $wrapMode.Dispose()
    $tg.Dispose()

    $dir = [System.IO.Path]::GetDirectoryName($destPath)
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $target.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $target.Dispose()
    Write-Host "Generated Maskable: $destPath ($targetSize x $targetSize)"
}

# 1. Root Apple Touch Icons (Safari "Add to Home Screen" requests these first)
Save-Icon $master 180 180 "web\apple-touch-icon.png"
Save-Icon $master 180 180 "web\apple-touch-icon-precomposed.png"
Save-Icon $master 180 180 "build\web\apple-touch-icon.png"
Save-Icon $master 180 180 "build\web\apple-touch-icon-precomposed.png"

# 2. Specific iOS Apple Touch Icons
Save-Icon $master 180 180 "web\icons\apple-touch-icon-180x180.png"
Save-Icon $master 167 167 "web\icons\apple-touch-icon-167x167.png"
Save-Icon $master 152 152 "web\icons\apple-touch-icon-152x152.png"
Save-Icon $master 120 120 "web\icons\apple-touch-icon-120x120.png"
Save-Icon $master 180 180 "build\web\icons\apple-touch-icon-180x180.png"
Save-Icon $master 167 167 "build\web\icons\apple-touch-icon-167x167.png"
Save-Icon $master 152 152 "build\web\icons\apple-touch-icon-152x152.png"
Save-Icon $master 120 120 "build\web\icons\apple-touch-icon-120x120.png"

# 3. PWA Icons
Save-Icon $master 192 192 "web\icons\Icon-192.png"
Save-Icon $master 512 512 "web\icons\Icon-512.png"
Save-Icon $master 192 192 "build\web\icons\Icon-192.png"
Save-Icon $master 512 512 "build\web\icons\Icon-512.png"

# 4. Maskable Icons
Save-Maskable $master 192 "web\icons\Icon-maskable-192.png"
Save-Maskable $master 512 "web\icons\Icon-maskable-512.png"
Save-Maskable $master 192 "build\web\icons\Icon-maskable-192.png"
Save-Maskable $master 512 "build\web\icons\Icon-maskable-512.png"

# 5. Favicons
Save-Icon $master 64 64 "web\favicon.png"
Save-Icon $master 64 64 "build\web\favicon.png"

$master.Dispose()
$src.Dispose()
Write-Host "All icons successfully generated in 24bpp (zero transparency, Apple compliant)!"
