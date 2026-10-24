"""Assemble final slide PNGs as a static PDF; preserve image content."""
from pathlib import Path
from reportlab.pdfgen import canvas
root=Path(__file__).resolve().parents[1]
pages=sorted((root/'previews').glob('slide-*.png'))
if len(pages)!=10:
    raise RuntimeError('Expected ten final slide renders')
out=root/'output/spottr-judges-rendered.pdf'
pdf=canvas.Canvas(str(out),pagesize=(960,540),pageCompression=1)
pdf.setTitle('Spottr judges presentation')
pdf.setSubject('Static PDF of ten final slide renders, evidence snapshot 24 October 2026')
for image in pages:
    pdf.drawImage(str(image),0,0,width=960,height=540,preserveAspectRatio=True,mask='auto')
    pdf.showPage()
pdf.save()
print(out)
