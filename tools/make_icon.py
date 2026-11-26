from PIL import Image, ImageDraw
import os
os.makedirs("assets/icon", exist_ok=True)
img = Image.new("RGB", (1024, 1024), (17, 17, 20))
d = ImageDraw.Draw(img)
d.ellipse((112, 112, 912, 912), fill=(214, 40, 40))
d.ellipse((192, 192, 832, 832), fill=(17, 17, 20))
d.polygon([(420, 330), (420, 694), (724, 512)], fill=(255, 255, 255))
img.save("assets/icon/icon.png")
