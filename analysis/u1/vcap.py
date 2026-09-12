#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1 V-cap：让 stock_pull 的合成区间在【每个 N】上恒为 [lo/den, hi/den]。
在 work_pull 已经施加过的那条广告上，把 stock_pull 的乘子除以 work_pull_mult。
N=12 上 work_pull_mult ≡ 1.0 ⇒ 分支不进 ⇒ 逐字节不变（可验的负对照）。
用法：vcap.py <gamedir>"""
import io, os, sys

P = os.path.join(sys.argv[1], "scripts", "Sim.gd")
s = io.open(P, encoding="utf-8", newline="").read()

OLD_WP = """			if work_pull_mult != 1.0 and mods_ok and String(adv.get("job", "")) != "" \\
					and _in_shift(_job_of(String(ag["id"]))):
				benefit *= work_pull_mult
"""
NEW_WP = """			var _wp_applied := false
			if work_pull_mult != 1.0 and mods_ok and String(adv.get("job", "")) != "" \\
					and _in_shift(_job_of(String(ag["id"]))):
				benefit *= work_pull_mult
				_wp_applied = true
"""
OLD_SP = """				if not _jb.is_empty() and _job_action(_jb) == action and _in_shift(_jb):
					benefit *= _stock_pull_mult(String(_jb.get("title", "")))
"""
NEW_SP = """				if not _jb.is_empty() and _job_action(_jb) == action and _in_shift(_jb):
					var _spf := _stock_pull_mult(String(_jb.get("title", "")))
					if _wp_applied:
						_spf /= work_pull_mult
					benefit *= _spf
"""
EOL = "\r\n" if "\r\n" in s else "\n"
for old, new in ((OLD_WP, NEW_WP), (OLD_SP, NEW_SP)):
    old = old.replace("\n", EOL)
    new = new.replace("\n", EOL)
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("V-cap applied to", P)
