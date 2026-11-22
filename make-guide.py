# 重新生成《本地制作指南.md》（改了代码以后运行：python3 make-guide.py .）
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
head = """# 晾衣绳（Clothesline）本地制作指南

这份文件里有做出"晾衣绳"需要的**全部源码和步骤**。把它拷到另一台 Mac 上，照着做就能在本机编译出一模一样的 App，不用从 GitHub 下载代码。

> 也可以把这份文件交给那台电脑上的 Claude Code，跟它说："按照这个文件，在本机把晾衣绳做出来。"

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

## 步骤

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

第一次编译大约要 1 分钟。做好后，App 会装到"应用程序"文件夹并自动打开；没有管理员权限的话，会装到自己的 `~/Applications`。

**4. 第一次打开时**

- 如果弹窗问能不能访问"桌面"文件夹，点**允许**，不然找不到截图。
- 如果系统提示"无法验证开发者"，就在"应用程序"里右键点 Clothesline，选**打开**。

**以后改了代码**：再运行一次 `./build-app.sh` 就行，它会关掉旧的、装好新的、重新打开。

---

## 源码

"""
body = ""
for path, lang in files:
    with open(os.path.join(root, path), encoding="utf-8") as f:
        code = f.read().rstrip("\n")
    assert "```" not in code, path
    body += f"### `{path}`\n\n```{lang}\n{code}\n```\n\n"
with open(os.path.join(root, "本地制作指南.md"), "w", encoding="utf-8") as f:
    f.write(head + body.rstrip("\n") + "\n")
print("written", len((head + body).splitlines()), "lines")
