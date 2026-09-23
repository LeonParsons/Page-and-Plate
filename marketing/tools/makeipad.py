import subprocess, pathlib

FRAMES = [
    ("ipad2.png", "Plan the week.",               "The whole week at a glance, each meal at its own portions."),
    ("ipad4.png", "Cooking for one?",             "Every line follows &#8212; and a quarter tin stays a quarter tin."),
    ("ipad6.png", "One shop for the whole week.", "Straight into a Reminders list. Staples left out."),
]

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>frame</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,600;9..144,700&display=swap">
<style>
  html, body {{ margin: 0; padding: 0; background: #F4EFE5; }}
  body {{ font-family: -apple-system, "SF Pro Text", system-ui, sans-serif; color: #23201B; }}
</style>
</head>
<body>
<div style="width: 1032px; height: 1376px; box-sizing: border-box; background: #F4EFE5; display: flex; flex-direction: column; overflow: hidden;">
  <div style="padding: 62px 80px 30px; flex-shrink: 0;">
    <div style="font-family: Fraunces, Georgia, serif; font-size: 46px; font-weight: 700; line-height: 1.1;">{headline}</div>
    <div style="font-size: 20px; color: #5C554A; margin-top: 12px; line-height: 1.4;">{subline}</div>
  </div>
  <div style="margin: 0 80px; border-radius: 34px 34px 0 0; border: 1px solid #E0D8C9; border-bottom: none; flex-grow: 1; overflow: hidden; background: #FAF7F0;">
    <img src="{shot}" style="display: block; width: 100%; height: 100%; object-fit: cover; object-position: top center;">
  </div>
</div>
</body>
</html>
"""

out = pathlib.Path("frames"); out.mkdir(exist_ok=True)
for n, (shot, headline, subline) in enumerate(FRAMES, start=1):
    html = pathlib.Path(f"ipadframe{n}.html")
    html.write_text(TEMPLATE.format(shot=shot, headline=headline, subline=subline))
    target = out / f"ipad13-{n}.png"
    r = subprocess.run(["swift", "html2png.swift", str(html), "1032", "1376", "2", str(target)],
                       capture_output=True, text=True)
    line = [l for l in (r.stdout + r.stderr).splitlines() if "wrote" in l or "html2png" in l]
    print(f"iPad frame {n}: {line[0] if line else 'FAILED'}")
