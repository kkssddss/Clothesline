# Regenerates BUILD-GUIDE.md and the one-step installer install.sh. Run after changing code: python3 make-guide.py .
import sys, os
root = sys.argv[1]
files = [
    ("Package.swift", "swift"),
    ("Sources/Clothesline/App.swift", "swift"),
    ("Sources/Clothesline/LineStore.swift", "swift"),
    ("Sources/Clothesline/ClotheslineView.swift", "swift"),
    ("Sources/Clothesline/Rope.swift", "swift"),
    ("Sources/Clothesline/Animals.swift", "swift"),
    ("build-app.sh", "bash"),
    (".gitignore", "text"),
]
sources = {}
for path, _ in files:
    with open(os.path.join(root, path), encoding="utf-8") as f:
        sources[path] = f.read().rstrip("\n")

# ---------- One-step installer install.sh ----------
END = "CLOTHESLINE_FILE_END"
script = """#!/bin/bash
# Makes Clothesline in one step: writes all the source code to ~/code/Clothesline, then builds, installs and opens it.
# Usage (in Terminal): bash install.sh
# To use another folder: bash install.sh /path/to/folder
set -euo pipefail

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools aren't installed. First run this in Terminal: xcode-select --install"
    echo "When they're installed, run bash install.sh again."
    exit 1
fi

DIR="${1:-$HOME/code/Clothesline}"
echo "Writing the source code to $DIR..."
mkdir -p "$DIR/Sources/Clothesline"
cd "$DIR"

"""
for path, _ in files:
    code = sources[path]
    assert END not in code, path
    script += f"cat > '{path}' <<'{END}'\n{code}\n{END}\n\n"
script += """chmod +x build-app.sh
echo "Building (about 1 minute the first time)..."
./build-app.sh
"""
with open(os.path.join(root, "install.sh"), "w", encoding="utf-8") as f:
    f.write(script)
os.chmod(os.path.join(root, "install.sh"), 0o755)

# ---------- BUILD-GUIDE.md ----------
head = """# Clothesline: Build It Yourself

This file has **all the source code and every step** you need to make Clothesline. Copy it to another Mac, follow the steps, and you'll build the exact same app on that Mac. You don't need to download any code from GitHub.

## What it does

- A naturally sagging clothesline across the top of the screen holds your **20 latest screenshots and screen recordings**, newest on the left.
- **Screenshots saved as files** are read from your screenshot folder (the Desktop by default).
- **Screenshots copied only to the clipboard and never saved** (for example with ⌃⇧⌘4, or from WeChat's screenshot tool) are saved automatically to a "Clothesline" folder in Pictures and hung on the line too.
- **Click** a picture to open it. **Pull it up and let go** to delete it: the file moves to the Trash, and the picture flips twice and blows away in the wind. **Drag it down** to drop the file into WeChat, Word, or any other app. Right-click for Open, Show in Finder, and Move to Trash.
- Two sheep, a pig, a cow, and a rooster walk back and forth on the rope and stop to graze now and then. You can't click them.
- A 🧺 sits in the menu bar. **Click** it to show or hide the clothesline. **Long-press** (or right-click) it for a menu with Open at Login and Quit.

## What you need

- A Mac running **macOS 14 or later**. Apple silicon and Intel both work: whichever Mac you build on, you get a version made for that Mac.
- **Xcode Command Line Tools**. In Terminal, run `xcode-select -p`. If it prints a path, they're already installed. If not, run `xcode-select --install`. Installing them needs an internet connection and may need an administrator password.
- Apart from that, you need **no internet connection** and no third-party libraries.
- On a work computer, first make sure your company allows running apps you build yourself.

## The easy way: one file, one command

1. Get **`install.sh`** from the repo onto that Mac (download it from the GitHub page, or send it over by USB drive, email, or chat). For example, put it in your Downloads folder.
2. Open Terminal and run this (if the file isn't in Downloads, change the path to where it actually is):

```bash
bash ~/Downloads/install.sh
```

It writes all the source code to `~/code/Clothesline`, then builds, installs, and opens the app. The first time takes about 1 minute.

If something goes wrong, copy the whole error from Terminal and paste it into a chatbot. It can usually tell you which step failed.

## The manual way (without install.sh)

**1. Make the folder** (run this in Terminal)

```bash
mkdir -p ~/code/Clothesline/Sources/Clothesline && cd ~/code/Clothesline
```

**2. Create each file named in "Source code" below, and paste its contents in exactly as shown**

There are 8 files. Each path is relative to `~/code/Clothesline`:

"""
for path, _ in files:
    head += f"- `{path}`\n"
head += """
**3. Build, install, and open it**

```bash
cd ~/code/Clothesline && chmod +x build-app.sh && ./build-app.sh
```

The first build takes about 1 minute.

## After it's installed

- The app is installed in your Applications folder and opens by itself. Without administrator rights, it goes in your own `~/Applications` folder instead.
- If a window asks whether the app can access your Desktop folder, click **Allow**. Otherwise it can't find your screenshots.
- If macOS says it can't verify the developer, right-click Clothesline in Applications and choose **Open**.
- **If you change the code later**, run `./build-app.sh` again in `~/code/Clothesline`. It quits the old version, installs the new one, and opens it again.

---

## Source code

Copy everything exactly as it is.

"""
body = ""
for path, lang in files:
    code = sources[path]
    assert "```" not in code, path
    body += f"### `{path}`\n\n```{lang}\n{code}\n```\n\n"
with open(os.path.join(root, "BUILD-GUIDE.md"), "w", encoding="utf-8") as f:
    f.write(head + body.rstrip("\n") + "\n")
print("written guide", len((head + body).splitlines()), "lines; install.sh", len(script.splitlines()), "lines")
