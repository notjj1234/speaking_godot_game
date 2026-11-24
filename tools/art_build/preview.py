"""preview.py — quick 1x/3x on-grass + silhouette previews for an in-progress sheet."""
import sys
from PIL import Image

GRASS = (76, 150, 64, 255)


def on_grass(img, scale=1):
    bg = Image.new("RGBA", img.size, GRASS)
    bg.alpha_composite(img)
    return bg.resize((img.width * scale, img.height * scale), Image.NEAREST) if scale != 1 else bg


def silhouette(img, scale=1):
    a = img.getchannel("A").point(lambda v: 255 if v else 0)
    out = Image.new("RGBA", img.size, (235, 235, 235, 255))
    out.paste((0, 0, 0, 255), (0, 0), a)
    return out.resize((img.width * scale, img.height * scale), Image.NEAREST) if scale != 1 else out


def regrid(img, cols, n, per, cw, ch):
    """Re-flow the first n cells of a sheet into rows of `per` for viewing."""
    cells = [img.crop(((i % cols) * cw, (i // cols) * ch, (i % cols) * cw + cw, (i // cols) * ch + ch)) for i in range(n)]
    rows = (n + per - 1) // per
    o = Image.new("RGBA", (per * cw, rows * ch))
    for i, c in enumerate(cells):
        o.paste(c, ((i % per) * cw, (i // per) * ch))
    return o, cells


if __name__ == "__main__" and len(sys.argv) > 4 and sys.argv[1] == "--grid":
    # --grid src cols n per cw ch dst [scale]
    _, _, src, cols, n, per, cw, ch, dst = sys.argv[:9]
    scale = int(sys.argv[9]) if len(sys.argv) > 9 else 3
    im = Image.open(src).convert("RGBA")
    g, cells = regrid(im, int(cols), int(n), int(per), int(cw), int(ch))
    for i, c in enumerate(cells):
        b = c.getbbox()
        print(i, b, (b[2] - b[0], b[3] - b[1]) if b else None, end=" | ")
    print("\ncolors", len({c for c in im.get_flattened_data() if c[3]}))
    a = on_grass(g, scale)
    s = silhouette(g, scale)
    o = Image.new("RGBA", (a.width, a.height * 2), GRASS)
    o.paste(a, (0, 0)); o.paste(s, (0, a.height))
    o.save(dst)
elif __name__ == "__main__":
    src, dst, scale = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 3
    im = Image.open(src).convert("RGBA")
    a = on_grass(im, scale)
    b = silhouette(im, scale)
    o = Image.new("RGBA", (a.width, a.height * 2), GRASS)
    o.paste(a, (0, 0)); o.paste(b, (0, a.height))
    o.save(dst)
