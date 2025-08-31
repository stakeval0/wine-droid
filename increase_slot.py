#!/usr/bin/env python3
# append_go_sequence.py
import argparse
import re
from pathlib import Path
import shutil
import sys

NUMERIC_LINE_TMPL = r'^([ \t]*){name}\(\s*(\d+)\s*\)\s*(\\)?[ \t]*(?://.*)?\r?\n?$'

def append_numeric_blocks(file: Path, target: int, name: str, dry: bool) -> None:
    if target <= 0:
        print("--target は正の整数で指定してください。", file=sys.stderr)
        sys.exit(2)

    text = file.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines(keepends=True)

    re_numeric = re.compile(NUMERIC_LINE_TMPL.format(name=re.escape(name)))

    i = 0
    changed = False
    while i < len(lines):
        m = re_numeric.match(lines[i])
        if not m:
            i += 1
            continue

        # ここから「数値 {name}(n) が連続する」ブロックを確定
        last_n = int(m.group(2))
        last_indent = m.group(1)
        last_idx = i
        last_has_bs = bool(m.group(3))

        j = i + 1
        while j < len(lines):
            m2 = re_numeric.match(lines[j])
            if not m2:
                break
            last_n = int(m2.group(2))
            last_indent = m2.group(1)
            last_idx = j
            last_has_bs = bool(m2.group(3))
            j += 1

        # 追記が必要なら、まず既存の末尾行に \ が無ければ付ける
        if last_n + 1 < target:
            if not last_has_bs:
                # 末尾行を「... \」で上書き（コメントは落とす：マクロ継続のため）
                lines[last_idx] = f"{last_indent}{name}({last_n})  \\\n"
                changed = True

            # 末尾に target-1 まで追加（追加分は最後のみ \ なし）
            insert_pos = j
            for nnew in range(last_n + 1, target):
                line = f"{last_indent}{name}({nnew})"
                if nnew != target - 1:
                    line += "  \\\n"
                else:
                    line += "\n"
                lines.insert(insert_pos, line)
                insert_pos += 1
            changed = True
            i = insert_pos
        else:
            i = j  # 次の場所へ

    if not changed:
        print(f"[SKIP] 変更なし: {file}（target={target}）")
        return

    if dry:
        print(f"[DRY]  変更あり（未保存）: {file}")
        return

    bak = file.with_suffix(file.suffix + ".bak")
    shutil.copy2(file, bak)
    file.write_text(''.join(lines), encoding="utf-8")
    print(f"[SAVE] 書き換え完了: {file}（バックアップ: {bak.name}）")

def main():
    ap = argparse.ArgumentParser(
        description="数値 GO(n) 連続ブロックの末尾だけを GO(target-1) まで拡張。末尾に \\ が無ければ付与してから追記します。"
    )
    ap.add_argument("file", type=Path, help="書き換える C/ヘッダファイル")
    ap.add_argument("--target", type=int, required=True, help="末尾を GO(target-1) まで拡張")
    ap.add_argument("--name", type=str, default="GO", help="対象マクロ名（既定: GO）")
    ap.add_argument("--dry-run", action="store_true", help="保存せず変更の有無だけ表示")
    args = ap.parse_args()
    append_numeric_blocks(args.file, args.target, args.name, args.dry_run)

if __name__ == "__main__":
    main()
