"""Render Tableo's Modules mark, shared by Windows and Microsoft Store."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
NAVY, PURPLE, CORAL = '#20283E', '#5856D6', '#FF8A65'

def render(size):
    image = Image.new('RGBA', (1024, 1024))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((32, 32, 992, 992), radius=176, fill=NAVY)
    draw.rounded_rectangle((184, 184, 584, 424), radius=40, fill=PURPLE)
    draw.rounded_rectangle((624, 184, 840, 488), radius=40, fill=CORAL)
    draw.rounded_rectangle((384, 464, 648, 840), radius=40, fill=PURPLE)
    return image.resize((size, size), Image.Resampling.LANCZOS)

def main():
    assets = ROOT/'assets/branding'
    assets.mkdir(parents=True, exist_ok=True)
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="32" y="32" width="960" height="960" rx="176" fill="#20283E"/>
  <rect x="184" y="184" width="400" height="240" rx="40" fill="#5856D6"/>
  <rect x="624" y="184" width="216" height="304" rx="40" fill="#FF8A65"/>
  <rect x="384" y="464" width="264" height="376" rx="40" fill="#5856D6"/>
</svg>
'''
    (assets/'tableo-modules.svg').write_text(svg, encoding='utf-8')
    master = render(1024)
    master.save(assets/'tableo-modules.png')
    master.save(ROOT/'windows/runner/resources/app_icon.ico', sizes=[(n,n) for n in [16,24,32,48,64,128,256]])
    store = ROOT/'output/store/modules-assets'
    store.mkdir(parents=True, exist_ok=True)
    for name, size in {'Square44x44Logo':44,'Square150x150Logo':150,'StoreLogo':50}.items():
        render(size).save(store/(name+'.png'))
    preview = Image.new('RGB', (620, 280), '#F3F6F5')
    for size, x, y in [(256,12,12),(150,294,24),(44,480,24),(32,480,104),(16,480,176)]:
        icon = render(size)
        preview.paste(icon,(x,y),icon)
    preview.save(store/'preview.png')

if __name__ == '__main__':
    main()
