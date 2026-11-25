"""Turn the location_text column of the terminal export into a district.

Usage:
    python extract_district.py export.csv lk_town_district.csv output.csv

- export.csv            : result of terminal_location_export.sql saved as CSV
- lk_town_district.csv  : town -> district -> province lookup (edit it freely)
- output.csv            : same rows with town, district and province added and
                          the merchant text (location_text) REMOVED

It also writes output_unmatched_towns.csv: the last part of each address that
could not be matched (usually a town name), with counts, so you can add the
missing towns to the lookup and run the script again. Merchant names are not
written to any output file.
"""
import csv
import re
import sys
from collections import Counter

import pandas as pd

STREET_WORDS = r"(?:ROAD|RD|MAWATHA|MAWATA|MW|STREET|ST|LANE|AVENUE|AVE|PLACE|PEDESA|PATUMAGA)\b"


def load_lookup(path):
    g = pd.read_csv(path)
    g["key"] = g["town"].str.upper().str.strip()
    g = g.drop_duplicates("key")
    pats = []
    for key, dist, prov, town in zip(g.key, g.district, g.province, g.town):
        words = re.split(r"[\s\-\.']+", key)
        body = r"[\s\-\.']*".join(re.escape(w) for w in words if w)
        # whole word, not followed by a street word ("Kandy Road" is not Kandy)
        rx = re.compile(r"(?<![A-Z])" + body + r"(?![A-Z])(?!\s*" + STREET_WORDS + ")")
        pats.append((len(key), rx, town, dist, prov))
    pats.sort(key=lambda p: -p[0])  # longer names first (Nuwara Eliya before Eliya)
    return pats


def clean(text):
    t = str(text).upper()
    t = t.replace("\\N", " ").replace("\\R", " ").replace("\\T", " ").replace("\n", " ").replace("\r", " ")
    return re.sub(r"\s+", " ", t)


def match(text, pats):
    """Return (town, district, province) of the right-most town in the text."""
    t = clean(text)
    best = None
    for length, rx, town, dist, prov in pats:
        for m in rx.finditer(t):
            cand = (m.end(), length, town, dist, prov)
            if best is None or cand[:2] > best[:2]:
                best = cand
    return (best[2], best[3], best[4]) if best else (None, None, None)


def last_part(text):
    t = clean(text)
    parts = [p.strip(" .") for p in re.split(r"[,/]", t) if p.strip(" .")]
    words = parts[-1].split() if parts else []
    return " ".join(words[-2:])  # last two words only: usually the town, never a full merchant name


def main(src, lookup, out):
    df = pd.read_csv(src, dtype=str, keep_default_na=False, na_values=["NULL", ""],
                     encoding="latin1", quoting=csv.QUOTE_MINIMAL)
    pats = load_lookup(lookup)
    res = df["location_text"].fillna("").map(lambda s: match(s, pats) if s else (None, None, None))
    df["town"] = [r[0] for r in res]
    df["district"] = [r[1] for r in res]
    df["province"] = [r[2] for r in res]
    has_text = df["location_text"].notna()
    unmatched = Counter(last_part(s) for s in df.loc[has_text & df["district"].isna(), "location_text"])
    df = df.drop(columns=["location_text"])           # privacy: merchant text removed
    df.to_csv(out, index=False)
    um = out.rsplit(".", 1)[0] + "_unmatched_towns.csv"
    pd.DataFrame(unmatched.most_common(), columns=["last_address_part", "jobs"]).to_csv(um, index=False)
    n, k, d = len(df), int(has_text.sum()), int(df["district"].notna().sum())
    print(f"{n} jobs; {k} with location text; {d} matched to a district "
          f"({d / max(k, 1):.0%} of those with text, {d / n:.0%} of all jobs)")
    print("Unmatched address endings written to", um)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
