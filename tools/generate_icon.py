from pathlib import Path

from PIL import Image, ImageDraw


def main():
    output = Path(__file__).resolve().parents[1] / "assets" / "secure_tiles.ico"
    output.parent.mkdir(parents=True, exist_ok=True)
    size = 256
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((18, 18, 238, 238), radius=58, fill="#5865F2")
    # A compact shield + chat tile mark that remains readable at 16px.
    draw.rounded_rectangle((58, 61, 198, 163), radius=30, fill="#FFFFFF")
    draw.polygon(((86, 154), (74, 194), (118, 163)), fill="#FFFFFF")
    draw.rounded_rectangle((83, 91, 173, 111), radius=10, fill="#5865F2")
    draw.rounded_rectangle((83, 124, 151, 144), radius=10, fill="#5865F2")
    image.save(output, format="ICO", sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == "__main__":
    main()
