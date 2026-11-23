# 重新生成《本地制作指南.md》和一键安装脚本 install.sh（改了代码以后运行：python3 make-guide.py .）
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

# ---------- 一键安装脚本 install.sh ----------
END = "CLOTHESLINE_FILE_END"
script = """#!/bin/bash
# 一键做出“晾衣绳”：把全部源码写到 ~/code/Clothesline，然后编译、安装、打开。
# 用法（在“终端”里）：bash install.sh
# 想放到别的文件夹：bash install.sh 文件夹路径
set -euo pipefail

if ! xcode-select -p >/dev/null 2>&1; then
    echo "还没装 Xcode 命令行工具。请先在终端运行：xcode-select --install"
    echo "装好以后再运行一次：bash install.sh"
    exit 1
fi

DIR="${1:-$HOME/code/Clothesline}"
echo "把源码写到 $DIR ……"
mkdir -p "$DIR/Sources/Clothesline"
cd "$DIR"

"""
for path, _ in files:
    code = sources[path]
    assert END not in code, path
    script += f"cat > '{path}' <<'{END}'\n{code}\n{END}\n\n"
script += """chmod +x build-app.sh
echo "开始编译（第一次大约 1 分钟）……"
./build-app.sh
"""
with open(os.path.join(root, "install.sh"), "w", encoding="utf-8") as f:
    f.write(script)
os.chmod(os.path.join(root, "install.sh"), 0o755)

# ---------- 本地制作指南.md ----------
head = """# 晾衣绳（Clothesline）本地制作指南

这份文件里有做出"晾衣绳"需要的**全部源码和步骤**。把它拷到另一台 Mac 上，照着做就能在本机编译出一模一样的 App，不用从 GitHub 下载代码。

## 它能做什么

- 屏幕顶上一根自然下垂的晾衣绳，挂着**最新的 20 张截图和录屏**，最新的在最左边。
- **存成文件的截图**：从截图文件夹里读，默认是桌面。
- **只复制到剪贴板、没存的截图**（比如按 ⌃⇧⌘4，或用微信截图）：会自动存一份到"图片/晾衣绳"，然后也挂上去。
- **点一下**图片就打开。**往上拉、松手**就删除：文件移到废纸篓，图片翻两圈后被风吹走。**往下拖**能把文件拖进微信、Word 等软件。右键有"打开""在访达中显示""删除"。
- 绳子上有两只羊、一只猪、一头牛、一只公鸡来回走，偶尔停下来吃东西。它们点不了。
- 菜单栏上有个 🧺：**点一下**显示或隐藏晾衣绳；**长按**（或右键）出菜单，里面有"开机时自动打开"和"退出"。

## 需要什么

- 一台 Mac，系统是 **macOS 14 或更新**的版本。Apple 芯片和 Intel 芯片都可以，在哪台电脑上编译，就会编出适合那台电脑的版本。
- **Xcode 命令行工具**。在"终端"里运行 `xcode-select -p`：能显示一个路径，就说明已经装好了；没装的话运行 `xcode-select --install`。装这个工具要联网，可能还要管理员权限。
- 除此之外**不需要联网**，也不用任何第三方库。
- 如果是公司电脑，先确认公司允许运行自己编译的程序。

## 最省事的做法：一个文件、一条命令

1. 把仓库里的 **`install.sh`** 拿到那台 Mac 上（GitHub 网页上点下载，或者用 U 盘、邮件、微信"文件传输助手"发过去）。比如放在"下载"文件夹里。
2. 打开"终端"，运行（如果文件不在"下载"里，把路径改成它实际的位置）：

```bash
bash ~/Downloads/install.sh
```

它会把全部源码写到 `~/code/Clothesline`，然后编译、安装、自动打开。第一次大约 1 分钟。

如果中途报错，把终端里显示的错误整段复制给聊天机器人看，它一般能告诉你是哪一步出了问题。

## 手动做法（不用 install.sh 的话）

**1. 建文件夹**（在"终端"里运行）

```bash
mkdir -p ~/code/Clothesline/Sources/Clothesline && cd ~/code/Clothesline
```

**2. 按下面"源码"里的文件名，把每个文件建出来，内容原样复制进去**

一共 8 个文件，路径都是相对 `~/code/Clothesline` 的：

"""
for path, _ in files:
    head += f"- `{path}`\n"
head += """
**3. 编译、安装、打开**

```bash
cd ~/code/Clothesline && chmod +x build-app.sh && ./build-app.sh
```

第一次编译大约要 1 分钟。

## 装好以后

- App 会装到"应用程序"文件夹并自动打开；没有管理员权限的话，会装到自己的 `~/Applications`。
- 如果弹窗问能不能访问"桌面"文件夹，点**允许**，不然找不到截图。
- 如果系统提示"无法验证开发者"，就在"应用程序"里右键点 Clothesline，选**打开**。
- **以后改了代码**：在 `~/code/Clothesline` 里再运行一次 `./build-app.sh` 就行，它会关掉旧的、装好新的、重新打开。

---

## 源码

"""
body = ""
for path, lang in files:
    code = sources[path]
    assert "```" not in code, path
    body += f"### `{path}`\n\n```{lang}\n{code}\n```\n\n"
with open(os.path.join(root, "本地制作指南.md"), "w", encoding="utf-8") as f:
    f.write(head + body.rstrip("\n") + "\n")
print("written guide", len((head + body).splitlines()), "lines; install.sh", len(script.splitlines()), "lines")
