"""배포 전 검사: python3 -I usb/릴리스_검사.py --stable|--pre <EV6-dongle-USB-vX.Y.Z.zip>

usb/만들기.sh 가 묶음을 만든 뒤 자동으로 부른다. 하나라도 틀리면 0이 아닌 값으로 끝나고, 만들기.sh 는 묶음을 지운다.
2026-11-23 에 고친 것들이 다시 생기지 않게 하려는 검사다:
  - 차 화면·USB에 보이는 버전 문구가 예전 판으로 남음 (먼저_읽어주세요 4.12.0, 목록 이름 v4.14 / "test" / "beta")
  - HMG-API 모드 서명이 깨지거나 다른 키로 서명됨
  - NOTICE 의 드라이버 해시가 실제 드라이버와 다름
  - 안정판에 RTL8851BU 실험 드라이버가 들어감
  - macOS 숨김 파일(._*, .DS_Store), 채워지지 않은 {{VER}}
  - NEMESIS 설명 길이 제한 (short-desc 64, detailed-desc 256, id 95, depends 511)
"""
import base64, hashlib, io, json, re, sys, zipfile

MOD_UUID = "69f3ba75-ef4c-866a-b63d-a8904ec39279"    # ev6-kr-aa-keep author key (keys/aakeep-author.key)
errors = []


def bad(msg):
    errors.append(msg)


def ini(text):
    """NEMESIS.data -> {section: {key: value}} (quotes taken off)"""
    out, sec = {}, ""
    for l in text.splitlines():
        l = l.strip()
        if not l or l.startswith(("#", ";")):
            continue
        if l.startswith("[") and l.endswith("]"):
            sec = l[1:-1]
            out.setdefault(sec, {})
            continue
        if "=" in l:
            k, v = l.split("=", 1)
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] == '"':
                v = v[1:-1]
            out.setdefault(sec, {})[k.strip()] = v
    return out


def hidden(names, where):
    for n in names:
        b = n.rsplit("/", 1)[-1]
        if b.startswith("._") or b == ".DS_Store" or "__MACOSX" in n:
            bad(f"{where}: macOS 숨김 파일 {n}")


def check_mod(zb, where):
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
    except ImportError:
        bad("python cryptography 가 없어 모드 서명을 검사하지 못함 (pip3 install cryptography)")
        return
    z = zipfile.ZipFile(io.BytesIO(zb))
    names = set(z.namelist())
    hidden(names, where)
    try:
        man_b = z.read("META-HMGAPI/manifest.json")
        sig = base64.b64decode(z.read("META-HMGAPI/signature").strip())
    except KeyError as e:
        bad(f"{where}: 서명 파일 없음 {e}")
        return
    man = json.loads(man_b)
    pub = serialization.load_der_public_key(base64.b64decode(man["key"]))
    try:
        pub.verify(sig, man_b, ec.ECDSA(hashes.SHA256()))
    except Exception:
        bad(f"{where}: 모드 서명이 맞지 않음 (manifest.json 이 서명 뒤에 바뀜)")
    if man.get("uuid") != MOD_UUID:
        bad(f"{where}: 모드가 다른 키로 서명됨 (uuid {man.get('uuid')}, 기대 {MOD_UUID})")
    for p, h in man["files"].items():
        if p not in names:
            bad(f"{where}: 서명 목록의 파일이 없음 {p}")
        elif hashlib.sha256(z.read(p)).hexdigest() != h:
            bad(f"{where}: 서명 뒤에 바뀐 파일 {p}")
    extra = [n for n in names if not n.startswith("META-HMGAPI/") and not n.endswith("/") and n not in man["files"]]
    if extra:
        bad(f"{where}: 서명되지 않은 파일 {extra}")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("--stable", "--pre"):
        print(__doc__)
        return 2
    pre = sys.argv[1] == "--pre"
    bz = zipfile.ZipFile(sys.argv[2])
    names = bz.namelist()
    hidden(names, "묶음")
    top = {n.split("/")[0] for n in names}
    if len(top) != 1:
        bad(f"묶음 맨 위 폴더가 하나가 아님: {sorted(top)}")
    root = sorted(top)[0]
    m = re.fullmatch(r"EV6-dongle-USB-v(\d+\.\d+\.\d+)", root)
    if not m:
        bad(f"묶음 폴더 이름이 EV6-dongle-USB-v<버전> 이 아님: {root}")
        ver = "?"
    else:
        ver = m.group(1)

    def rd(p):
        try:
            return bz.read(f"{root}/{p}")
        except KeyError:
            bad(f"묶음에 {p} 없음")
            return b""

    for n in names:
        if n.endswith((".txt", ".data", ".md")) and b"{{" in bz.read(n):
            bad(f"채워지지 않은 {{{{...}}}}: {n}")

    # 1. the USB list (what NEMESIS Manager shows when the stick is plugged in)
    lst = ini(rd("NEMESIS.data").decode("utf-8"))
    if lst.get("nemesis", {}).get("type") != "list":
        bad("묶음 NEMESIS.data 가 type=list 가 아님")
    want = f"(KR v{ver} beta)" if pre else f"(KR v{ver})"
    for sec, kv in lst.items():
        if not sec.startswith("package."):
            continue
        if f"{root}/{kv.get('path', '')}" not in names:
            bad(f"목록 {sec} 의 파일이 묶음에 없음: {kv.get('path')}")
        nm = kv.get("name", "")
        if "usbwifi.hotspot" in kv.get("path", "") and want not in nm:
            bad(f"목록 이름에 '{want}' 가 없음: {nm}")
        if re.search(r"\btest\b", nm, re.I) or (not pre and re.search(r"beta|시험", nm, re.I)):
            bad(f"목록 이름에 시험판 표시가 남음: {nm}")
        if not re.fullmatch(r"\d{4}-\d\d-\d\d", kv.get("published", "")):
            bad(f"목록 published 날짜 형식이 틀림: {kv.get('published')}")
        if len(kv.get("short-desc", "")) > 64:
            bad(f"목록 short-desc 가 64자를 넘음 ({len(kv['short-desc'])})")

    # 2. version strings the user reads
    rm = rd("먼저_읽어주세요.txt").decode("utf-8")
    for v in set(re.findall(r"(?<![\d.])4\.\d+\.\d+(?![\d.])", rm)):
        if v != ver:
            bad(f"먼저_읽어주세요.txt 에 다른 버전 {v} (이 묶음은 {ver})")
    if ver not in rm:
        bad("먼저_읽어주세요.txt 에 이 버전이 없음")
    cl = rd("설명서/5_변경기록.txt").decode("utf-8")
    first = next((l for l in cl.splitlines() if l.startswith("- **")), "")
    if ver not in first:
        bad(f"변경 기록 맨 위 항목이 {ver} 가 아님: {first[:60]}")
    label = (re.match(r"- \*\*(.*?)\*\*", first) or re.match("(.*)", first)).group(1)   # "4.14.1 안정판"
    if not pre and re.search(r"시험판|로컬 전용|미배포|Pre-release|Beta", label, re.I):
        bad(f"안정판인데 변경 기록 맨 위가 시험판 표시: {first[:60]}")
    if f"| {ver} |" not in rd("설명서/2_설치와연결.txt").decode("utf-8"):
        bad(f"설치와연결 의 설치 순서 표에 {ver} 가 없음")

    # 3. the package inside
    pz = zipfile.ZipFile(io.BytesIO(rd("packages/usbwifi.hotspot.zip")))
    pn = set(pz.namelist())
    hidden(pn, "패키지")
    meta = ini(pz.read("NEMESIS.data").decode("utf-8"))
    n = meta.get("nemesis", {})
    if n.get("package-version") != ver:
        bad(f"패키지 package-version {n.get('package-version')} 가 묶음 버전 {ver} 와 다름")
    if not n.get("detailed-desc", "").startswith(f"EV6 KR {ver}:"):
        bad(f"패키지 detailed-desc 가 'EV6 KR {ver}:' 로 시작하지 않음")
    for k, lim in (("short-desc", 64), ("detailed-desc", 256), ("id", 95), ("depends", 511)):
        if len(n.get(k, "")) > lim:
            bad(f"패키지 {k} 가 {lim}자를 넘음 ({len(n[k])})")
    if re.search(r"\btest\b|beta", n.get("name", ""), re.I):
        bad(f"패키지 이름에 시험판 표시: {n.get('name')}")
    has8851 = [x for x in pn if "8851" in x]
    if not pre:
        if has8851:
            bad(f"안정판에 RTL8851BU 실험 파일: {has8851}")
        for t in (n.get("detailed-desc", ""), pz.read("NOTICE.txt").decode("utf-8")):
            if "8851" in t or "EXPERIMENTAL" in t:
                bad("안정판 설명·NOTICE 에 RTL8851BU/EXPERIMENTAL 문구")
                break
    ko = hashlib.sha256(pz.read("modules/88x2bu.ko")).hexdigest()
    if ko not in pz.read("NOTICE.txt").decode("utf-8"):
        bad("NOTICE.txt 의 88x2bu.ko 해시가 실제 드라이버와 다름")
    if ko not in pz.read("source/driver/SOURCE.txt").decode("utf-8"):
        bad("source/driver/SOURCE.txt 의 해시가 실제 드라이버와 다름")
    check_mod(pz.read("mod/package.zip"), "HMG-API 모드")

    if errors:
        print(f"릴리스 검사 실패 ({len(errors)}개): {sys.argv[2]}")
        for e in errors:
            print("  ✖ " + e)
        return 1
    print(f"릴리스 검사 OK: {root} ({'시험판' if pre else '안정판'}), 모드 서명 OK, 버전 표시 {ver} 로 일치")
    return 0


if __name__ == "__main__":
    sys.exit(main())
