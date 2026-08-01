#!/usr/bin/env python
# 红线 #4 的执行门：git 里不得有模型权重 / 预编译二进制。
#
# 由来：S2 的对抗评审（编号 73）把这道门点名为【纸】——它当时是 ci.sh 里一行手写扩展名清单
#   `\.(gguf|so|dll|bin|safetensors|pt)$`
# 我复核了它：14 个样本文件名只抓住 7 个，放过 .onnx / .tflite / .pth / .dlc / .so.1 / .dylib
# ——而 .tflite 与 .dlc 恰好是本项目端上 SLM 真会产出的两种格式。
#
# 但扩展名清单的病不止"漏了几个"：**改个名就绕过去了**。所以本门有两条臂：
#   A 名字臂：扩展名清单（含 .so.1 这类版本化后缀）。便宜、覆盖广、可被改名击败。
#   B 内容臂：读每个入库文件的头 16 字节认幻数。改名无效，但只认得出已知格式。
# 两条臂互补，**都不是完备的**——见文末 does_not_detect。
#
# S2 的统一结论直接塑造了本门的形状：
#   「11 条可对账的臂里，9 条【每次运行都重算并打印余量】的至今全部准确；
#     两族【打印冻结字面量或只把余量留在注释里】的全部过期。」
# ⇒ 本门每次运行都打印它扫了多少文件、两条臂各命中多少。**不留冻结字面量。**
import re, subprocess, sys, os

# Windows 控制台默认 GBK，编不出 ✅/❌ 会直接抛 UnicodeEncodeError（实测过，不是预防性的）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

# A 臂。(\.[0-9]+)* 收版本化共享库（libc.so.1 / libfoo.so.1.2）。
EXT = re.compile(
    r'\.(gguf|ggml|onnx|tflite|safetensors|pt|pth|npz|h5|hdf5|ckpt|pb|mlmodel|mlpackage'
    r'|dlc|engine|trt|bin|so|dylib|dll|exe|a|lib)(\.[0-9]+)*$', re.I)

# B 臂。只认**权重与可执行**的幻数；图片/视频/音频【故意不认】——
# docs/media/ 里的 png/mp4/gif 是正当入库的素材，认了它们这道门就永远是红的。
MAGIC = [
    (b"GGUF",            "GGUF 模型权重"),
    (b"\x7fELF",         "ELF 可执行/共享库"),
    (b"MZ",              "PE 可执行 (.exe/.dll)"),
    (b"\xcf\xfa\xed\xfe", "Mach-O 64 可执行"),
    (b"\xca\xfe\xba\xbe", "Mach-O fat / Java class"),
]
MAGIC_AT4 = [(b"TFL3", "TFLite 模型权重")]   # TFLite 的 'TFL3' 在偏移 4

def tracked():
    # -z 是必须的，不是讲究：`git ls-files` 默认 core.quotePath=on，把非 ASCII 路径
    # 输出成 "docs/\347\216\260..." 这样的**八进制转义带引号形式** ⇒ 那个字符串在磁盘上打不开。
    # 我第一版就是这么写的，实测 740 个入库文件里有 **20 个读不到头字节**，全是中文名的 docs——
    # 也就是说 **B 内容臂对任何非 ASCII 文件名一律失明**（一个中文名的权重文件会直接穿过去）。
    # -z 走 NUL 分隔，绕开引号与转义。
    out = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout
    return [p for p in out.decode("utf-8", "replace").split("\0") if p.strip()]

def scan(paths, root):
    hits_a, hits_b, read_ok = [], [], 0
    for rel in paths:
        if EXT.search(rel):
            hits_a.append(rel)
        full = os.path.join(root, rel)
        try:
            with open(full, "rb") as fh:
                head = fh.read(16)
        except OSError:
            continue          # 未 checkout / 权限 —— 不算命中，也不假装扫过
        read_ok += 1
        for sig, what in MAGIC:
            if head.startswith(sig):
                hits_b.append(f"{rel}  ({what})")
                break
        else:
            for sig, what in MAGIC_AT4:
                if head[4:4 + len(sig)] == sig:
                    hits_b.append(f"{rel}  ({what})")
                    break
    return hits_a, hits_b, read_ok

def selftest(root):
    """负对照：把三个该抓的东西放进去，两条臂都必须响。不响就是这道门没牙。"""
    import tempfile, shutil
    tmp = tempfile.mkdtemp(prefix="nw_selftest_")
    try:
        cases = [
            ("m.onnx",      b"\x08\x01\x12\x00",      "A", "改名前的 onnx"),
            ("weights.dat", b"GGUF\x03\x00\x00\x00",  "B", "GGUF 改名成 .dat —— A 臂看不见"),
            ("libc.so.1",   b"\x7fELF\x02\x01\x01",   "AB", "版本化共享库"),
        ]
        for name, blob, _, _ in cases:
            with open(os.path.join(tmp, name), "wb") as fh:
                fh.write(blob)
        names = [c[0] for c in cases]
        a, b, _ = scan(names, tmp)
        bad = 0
        for name, _, want, why in cases:
            in_a, in_b = name in a, any(h.startswith(name + " ") for h in b)
            got = ("A" if in_a else "") + ("B" if in_b else "")
            hit = set(want) & set(got)
            print(f"  [{'✅' if hit else '❌'}] {name:<12} 期望臂={want:<2} 实测臂={got or '(无)':<3} — {why}")
            if not hit:
                bad += 1
        return bad
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    if "--self-test" in sys.argv:
        print("[红线#4] 负对照（隔离临时目录，不碰仓库）：")
        bad = selftest(root)
        print(f"[红线#4] 负对照 {'PASS ✅' if bad == 0 else f'FAIL ❌ ({bad} 例没抓住)'}")
        return 1 if bad else 0

    paths = tracked()
    a, b, read_ok = scan(paths, root)
    # 每次运行都重算并打印——本门刻意不留任何冻结字面量（理由见抬头）。
    print(f"[红线#4] 入库文件 {len(paths)} 个，读到头字节 {read_ok} 个；"
          f"A 名字臂命中 {len(a)}，B 内容臂命中 {len(b)}")
    dead = sorted(set(a) | {h.split("  (")[0] for h in b})
    if dead:
        print("[红线#4] ❌ 检出权重/预编译二进制（红线 #4：一律不入库）：")
        for h in a:
            print(f"  - [名字] {h}")
        for h in b:
            print(f"  - [内容] {h}")
        return 1
    print("[红线#4] ✅ 无入库权重/二进制")
    return 0

# does_not_detect（**跑出来的**，不是想出来的）：
#   · **未知格式的权重改名之后两条臂都看不见** —— B 臂只认上面那 6 个幻数。
#     实测：把 safetensors 的 JSON 头存成 `w.dat`，本门 exit 0。
#   · **纯文本权重**（如 numpy 的 .txt dump）两条臂都不认。
#   · **只看 `git ls-files`** —— 已 stage 未 commit、或在 .gitignore 里的文件不在扫描集。
#   · **不判大小** —— 一个 4GB 的 .png 是合法的，一个 2KB 的 .gguf 是违规的；本门按类型不按体积。
#   · 不判素材版权（CC0 与否），那是红线 #4 的另一半，本门不覆盖。
if __name__ == "__main__":
    sys.exit(main())
