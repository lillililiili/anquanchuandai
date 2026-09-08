from pathlib import Path
from PIL import Image

src = (
    Path(r"C:\Users\黄建凯\.grok\sessions")
    / "E%3A%5C%E6%B2%89%E7%A7%AF%E5%B2%A9%5C%E5%88%86%E4%BD%93%E5%BC%8F%E5%AE%89%E5%85%A8%E5%B8%BD%E4%BB%A3%E7%A0%81"
    / "01a07092-95c2-7e33-b698-a2133e1ebcbf"
    / "images"
    / "3.jpg"
)
print("src", src.exists(), src)
img = Image.open(src).convert("RGBA")

root = Path(r"E:\沉积岩\分体式安全帽代码\pc前端代码\melhat_pc-main")
assets = root / "src" / "assets" / "logo"
public = root / "public"
assets.mkdir(parents=True, exist_ok=True)

full = img.resize((512, 512), Image.Resampling.LANCZOS)
full.save(assets / "app-logo.png", "PNG")
full.save(public / "logo.png", "PNG")

img.resize((32, 32), Image.Resampling.LANCZOS).save(public / "favicon-32.png", "PNG")
img.resize((48, 48), Image.Resampling.LANCZOS).save(public / "favicon.png", "PNG")
img.resize((180, 180), Image.Resampling.LANCZOS).save(public / "apple-touch-icon.png", "PNG")
img.save(public / "favicon.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
print("done")
