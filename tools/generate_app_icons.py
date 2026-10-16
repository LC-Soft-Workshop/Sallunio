"""Convert the supplied Sallunio artwork without redesigning it."""
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
def main():
    source = ROOT/'assets/branding/sallunio.png'
    image = Image.open(source).convert('RGBA')
    if image.width != image.height or image.getextrema()[3][0] != 0:
        raise ValueError('Square source with real transparency required.')
    image.save(ROOT/'windows/runner/resources/app_icon.ico', sizes=[(n,n) for n in [16,24,32,48,64,128,256]])
    target = ROOT/'output/store/sallunio-assets'
    target.mkdir(parents=True, exist_ok=True)
    for name,size in {'Square44x44Logo':44,'Square150x150Logo':150,'StoreLogo':50,'StoreTile300':300}.items():
        result=image.resize((size,size),Image.Resampling.LANCZOS)
        result.save(target/(name+'.png'))
        if result.getextrema()[3][0] != 0:
            raise ValueError('Transparency lost during conversion.')
if __name__ == '__main__': main()
