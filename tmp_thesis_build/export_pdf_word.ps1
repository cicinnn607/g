$ErrorActionPreference = "Stop"
$docx = (Resolve-Path ".\tmp_thesis_build\初稿_完成版.docx").Path
$pdf = (Join-Path (Resolve-Path ".\tmp_thesis_build").Path "初稿_完成版_word.pdf")
if (Test-Path -LiteralPath $pdf) {
  Remove-Item -LiteralPath $pdf -Force
}
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  $doc = $word.Documents.Open($docx)
  try {
    $doc.ExportAsFixedFormat($pdf, 17)
  } finally {
    $doc.Close($false)
  }
} finally {
  $word.Quit()
}
Get-Item -LiteralPath $pdf | Select-Object FullName,Length,LastWriteTime
