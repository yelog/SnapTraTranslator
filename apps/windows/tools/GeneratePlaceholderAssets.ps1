param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\src\SnapTra.Windows\Assets")
)

Add-Type -AssemblyName System.Drawing

$null = New-Item -ItemType Directory -Force -Path $OutputDirectory

function New-PlaceholderBitmap {
    param(
        [int]$Width,
        [int]$Height,
        [string]$FileName,
        [System.Drawing.Color]$Background,
        [System.Drawing.Color]$Accent
    )

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear($Background)

    $brush = New-Object System.Drawing.SolidBrush $Accent
    $fontSize = [Math]::Max(12, [int]($Height / 3))
    $font = New-Object System.Drawing.Font("Segoe UI Semibold", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $text = "S"
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $graphics.DrawEllipse($brush, 4, 4, $Width - 8, $Height - 8)
    $graphics.DrawString($text, $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new(0, 0, $Width, $Height), $format)

    $path = Join-Path $OutputDirectory $FileName
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

    $format.Dispose()
    $font.Dispose()
    $brush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$background = [System.Drawing.Color]::FromArgb(0x11, 0x14, 0x24)
$accent = [System.Drawing.Color]::FromArgb(0x76, 0xA9, 0xFF)

New-PlaceholderBitmap -Width 44 -Height 44 -FileName "Square44x44Logo.png" -Background $background -Accent $accent
New-PlaceholderBitmap -Width 150 -Height 150 -FileName "Square150x150Logo.png" -Background $background -Accent $accent
New-PlaceholderBitmap -Width 310 -Height 150 -FileName "Wide310x150Logo.png" -Background $background -Accent $accent
New-PlaceholderBitmap -Width 310 -Height 310 -FileName "Square310x310Logo.png" -Background $background -Accent $accent
New-PlaceholderBitmap -Width 50 -Height 50 -FileName "StoreLogo.png" -Background $background -Accent $accent
New-PlaceholderBitmap -Width 1240 -Height 600 -FileName "SplashScreen.png" -Background $background -Accent $accent
