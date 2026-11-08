param([string]$Script, [string]$Out, [string]$Model = "", [string]$SaveAs = "")
if (Get-Process SketchUp -ErrorAction SilentlyContinue) { throw "SketchUp is running" }
$env:MB_MODEL = $Model; $env:MB_SCRIPT = $Script; $env:MB_OUT = $Out; $env:MB_SAVE_AS = $SaveAs
$p = Start-Process "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -ArgumentList '-RubyStartup "D:\OneDrive\Learning\Code\Gemini\model-builder\hosts\sketchup\dev\autorun_script.rb"' -PassThru
if (-not $p.WaitForExit(280000)) { Stop-Process $p -Force; "TIMEOUT" }
Get-Content (Join-Path $Out "status.txt")
