import sys, pathlib

def swap(path, a, b):
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    assert s.count(a) == 1, (path, "A count", s.count(a))
    assert s.count(b) == 1, (path, "B count", s.count(b))
    s = s.replace(a, "\x00PH\x00").replace(b, a).replace("\x00PH\x00", b)
    p.write_text(s, encoding="utf-8")
    print("MUTATED", path)
    print("    ", a, "<->", b)

base = sys.argv[1]
# M4：赴约 ↔ 爽约（Y3 §三·3 点名的那一条，同类型漏网 0/19 的头号实例）
swap(base + "/game_mut_meet/scripts/Story.gd",
     '"两人如约见上了面"',
     '"约会泡了汤 —— 有人没来"')
# M5：手艺弧的「第一次」↔「又一次」（复述标记那一条的真世界实例）
swap(base + "/game_mut_rep/scripts/Story.gd",
     '"%A 看着 %B 把一批活做成了"',
     '"%A 又一次看着 %B 出活"')
