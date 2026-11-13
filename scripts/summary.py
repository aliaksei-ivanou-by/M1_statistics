"""Сбор оценок 1-2-1 из блоков ```yaml в отчетах employees/*/ГГГГ-ММ.md.

Использование:
  python scripts/summary.py 2026-10        таблица за месяц (markdown) для summaries/2026-10.md
  python scripts/summary.py --csv          все встречи в CSV (для графиков и дашборда)
  python scripts/summary.py --check        проверка, что блок yaml совпадает с полями отчета
"""
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIELDS = {"motivation": "Мотивация", "burnout": "Выгорание",
          "satisfaction": "Удовлетворённость", "blocker": "Категория блокера"}


def load():
    rows = []
    for path in sorted(ROOT.glob("employees/*/*.md")):
        text = path.read_text(encoding="utf-8")
        name = re.search(r"^# 1-2-1: (.+?) —", text, re.M)
        name = name.group(1).strip() if name else path.parent.name
        for block in re.split(r"(?=^## Встреча )", text, flags=re.M)[1:]:
            meta = re.search(r"```yaml\n(.*?)```", block, re.S)
            if not meta:
                continue
            row = dict(re.findall(r"^(\w+):\s*(.+?)\s*$", meta.group(1), re.M))
            row.update(employee=name, folder=path.parent.name, month=path.stem, _block=block)
            rows.append(row)
    rows.sort(key=lambda r: (r["folder"], r["date"]))
    return rows


def delta(cur, prev, key):
    if prev is None:
        return cur[key]
    d = int(cur[key]) - int(prev[key])
    return cur[key] if d == 0 else f"{cur[key]} ({'↑' if d > 0 else '↓'}{abs(d)})"


def month_table(month):
    rows = load()
    out = ["| Сотрудник | Встреча | Мотивация | Выгорание | Удовлетворённость | Блокер |",
           "|---|---|---|---|---|---|"]
    by_emp = {}
    for r in rows:
        by_emp.setdefault(r["folder"], []).append(r)
    for meetings in sorted(by_emp.values(), key=lambda m: m[0]["employee"]):
        in_month = [m for m in meetings if m["month"] == month]
        if not in_month:
            continue
        cur = in_month[-1]
        earlier = [m for m in meetings if m["date"] < in_month[0]["date"]]
        prev = earlier[-1] if earlier else None
        out.append(f"| {cur['employee']} | {cur['date']} | {delta(cur, prev, 'motivation')} | "
                   f"{delta(cur, prev, 'burnout')} | {delta(cur, prev, 'satisfaction')} | {cur['blocker']} |")
    print("\n".join(out))


def to_csv():
    w = csv.writer(sys.stdout)
    w.writerow(["date", "employee", "folder", "motivation", "burnout", "satisfaction", "blocker"])
    for r in load():
        w.writerow([r["date"], r["employee"], r["folder"], r["motivation"], r["burnout"],
                    r["satisfaction"], r["blocker"]])


def check():
    ok = True
    for r in load():
        for key, label in FIELDS.items():
            m = re.search(rf"^\*\*{label}:\*\* (.+)$", r["_block"], re.M)
            if not m or m.group(1).strip() != r.get(key):
                ok = False
                print(f"{r['folder']} {r['date']}: {key}={r.get(key)!r}, в отчете {m.group(1) if m else None!r}")
    print("OK" if ok else "Найдены расхождения")
    return ok


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--csv":
        to_csv()
    elif arg == "--check":
        sys.exit(0 if check() else 1)
    elif re.fullmatch(r"\d{4}-\d{2}", arg):
        month_table(arg)
    else:
        print(__doc__)
        sys.exit(1)
