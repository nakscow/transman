import io
import threading
import time
import warnings
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta
import FinanceDataReader as fdr
import numpy as np
import pandas as pd
import requests
from tqdm import tqdm

warnings.filterwarnings("ignore")

# =========================================================
# 설정
# =========================================================

API_KEY = "5ca518d43dabbb1941340da0ad37bfca7b721d6c"

MAX_WORKERS = 3
TIMEOUT = 20
SLEEP_SEC = 0.12
MAX_RETRIES = 3

# OpenDart status 코드 중 특정 회사/분기에 국한된 문제가 아니라 API 키·요청 자체에
# 문제가 생긴 "전역" 오류. 이 코드가 한 번이라도 뜨면 이후의 모든 호출도 똑같이
# 실패하므로, 계속 호출을 이어가는 대신 즉시 중단하고 사유를 알려준다.
#   010: 등록되지 않은 키          011: 사용할 수 없는 키
#   012: 접근할 수 없는 IP         020: 요청 제한(사용한도) 초과
#   101: 부적절한 접근             800: 시스템 점검 중
#   900: 정의되지 않은 오류        901: 개인정보 보유기간 만료 키
GLOBAL_ERROR_STATUS = {"010", "011", "012", "020", "101", "800", "900", "901"}

# 스레드 간 공유: 전역 오류 발생 시 모든 워커에게 중단을 알리는 플래그,
# 그리고 진단용으로 어떤 status 코드가 몇 번 나왔는지 집계
stop_event = threading.Event()
stop_reason = {}
status_counter = Counter()
status_lock = threading.Lock()

NOW = datetime.now().strftime("%Y%m%d_%H%M%S")

OUTPUT_FILE = f"OpenDart_5Q_Fundamental_with_PCR_{NOW}.csv"

HEADERS = {"User-Agent": "Mozilla/5.0"}

# 시가총액 300억원 미만 종목은 수집 대상에서 제외 (단위: 원)
MIN_MARKET_CAP = 30_000_000_000

# 보고서 종류별 법정 제출기한(분기말/사업연도말 기준 +45일, 사업보고서는 +90일).
# 실제 제출은 기한 막판에 몰리는 경우가 많아 5일의 여유(BUFFER)를 더해,
# 해당 시점 이후에는 대부분의 상장사가 공시를 마쳤다고 볼 수 있는 날짜를 기준으로 삼는다.
REPORT_DEFS = [
    ("11013", "Q1", lambda y: date(y, 5, 15)),       # 1분기보고서 (분기말 3/31 + 45일)
    ("11012", "Q2", lambda y: date(y, 8, 14)),        # 반기보고서 (반기말 6/30 + 45일)
    ("11014", "Q3", lambda y: date(y, 11, 14)),       # 3분기보고서 (분기말 9/30 + 45일)
    ("11011", "Q4", lambda y: date(y + 1, 3, 31)),    # 사업보고서 (사업연도말 12/31 + 90일)
]
DISCLOSURE_BUFFER_DAYS = 5


def get_recent_quarters(n=5, asof=None):
    """오늘 날짜 기준으로 이미 공시기한이 지난, 가장 최근 n개 분기를
    (year, report_code, qname) 튜플 리스트로 반환한다 (오래된 순 → 최신 순)."""
    if asof is None:
        asof = datetime.now().date()

    candidates = []
    for y in range(asof.year - 2, asof.year + 1):
        for report_code, qlabel, deadline_fn in REPORT_DEFS:
            deadline = deadline_fn(y) + timedelta(days=DISCLOSURE_BUFFER_DAYS)
            if deadline <= asof:
                candidates.append((deadline, str(y), report_code, f"{y}_{qlabel}"))

    candidates.sort(key=lambda x: x[0])
    recent = candidates[-n:]

    return [(year, report_code, qname) for _, year, report_code, qname in recent]


# 최근 5분기 (오늘 날짜 기준으로 자동 계산)
TARGET_Q = get_recent_quarters(5)


# =========================================================
# 숫자 변환
# =========================================================
def to_float(x):
    if pd.isna(x):
        return np.nan

    x = (
        str(x)
        .replace(",", "")
        .replace(" ", "")
        .replace("　", "")
        .strip()
    )

    if x in ["", "-", "nan"]:
        return np.nan

    try:
        return float(x)
    except:
        return np.nan


# =========================================================
# 종목 리스트
# =========================================================
KRX_CACHE_LOOKBACK_DAYS = 10


def fetch_krx_marcap_listing(market):
    """FinanceDataReader가 참조하는 KRX 시가총액 캐시(GitHub raw CSV)를
    직접 조회한다. fdr.StockListing()은 '최근 영업일' 날짜의 캐시 파일을
    바로 찾는데, 장 마감 후 캐시가 생성되기 전(예: 당일 장중)에는 그 날짜의
    파일이 아직 없어 404가 날 수 있다. 이를 대비해 최근 며칠을 거슬러
    올라가며 실제로 존재하는 가장 최신 캐시 파일을 사용한다."""
    mkt_map = {
        "KRX-MARCAP": "ALL",
        "KRX": "ALL",
        "KOSPI": "STK",
        "KOSDAQ": "KSQ",
        "KONEX": "KNX",
    }
    if market not in mkt_map:
        raise ValueError(f"market should be one of {list(mkt_map.keys())}")

    today = datetime.now().date()
    last_err = None

    for i in range(KRX_CACHE_LOOKBACK_DAYS):
        d = today - timedelta(days=i)
        url = (
            "https://raw.githubusercontent.com/FinanceData/fdr_krx_data_cache/"
            f"refs/heads/master/data/listing/krx/{d.strftime('%Y-%m-%d')}.csv"
        )
        try:
            df = pd.read_csv(
                url,
                index_col=0,
                dtype={
                    "Code": str,
                    "Dept": str,
                    "ChangeCode": str,
                    "MarketId": str,
                },
            )
        except Exception as e:
            last_err = e
            continue

        df = df.reset_index(drop=True)
        mkt = mkt_map[market]
        if mkt != "ALL":
            df = df[df["MarketId"] == mkt].reset_index(drop=True)
        return df

    raise RuntimeError(
        f"최근 {KRX_CACHE_LOOKBACK_DAYS}일 내에서 KRX 시세 캐시 파일을 "
        f"찾지 못했습니다 (market={market}): {last_err}"
    )


def get_stock_list():
    try:
        kospi = fdr.StockListing("KOSPI")
        kosdaq = fdr.StockListing("KOSDAQ")
    except Exception as e:
        print(
            f"fdr.StockListing() 조회 실패({e}). "
            "최근 영업일 캐시로 재시도합니다."
        )
        kospi = fetch_krx_marcap_listing("KOSPI")
        kosdaq = fetch_krx_marcap_listing("KOSDAQ")

    df = pd.concat([kospi, kosdaq], ignore_index=True)

    # 우선주/리츠/스팩 제거
    df = df[
        ~df["Name"].str.contains("우$|스팩|리츠", regex=True, na=False)
    ].copy()

    # 시가총액: 단위 통일을 위해 '원' 단위 그대로 사용 (억원 환산 없음)
    df["시가총액"] = pd.to_numeric(df["Marcap"], errors="coerce")

    # 거래정지 종목 제외: 거래정지 상태인 종목은 당일 거래량(Volume)이
    # 0으로 집계되므로 이를 거래정지 판별 기준으로 사용한다.
    volume = pd.to_numeric(df["Volume"], errors="coerce").fillna(0)
    is_halted = volume <= 0

    # 시가총액 300억원 미만 종목 제외
    is_below_min_cap = (
        df["시가총액"].isna() | (df["시가총액"] < MIN_MARKET_CAP)
    )

    before = len(df)
    df = df[~is_halted & ~is_below_min_cap].copy()
    print(
        f"거래정지/시가총액 {MIN_MARKET_CAP:,}원 미만 종목 제외: "
        f"{before}개 -> {len(df)}개"
    )

    out = pd.DataFrame()
    out["stock_code"] = df["Code"].astype(str).str.zfill(6)
    out["corp_name"] = df["Name"]
    out["시가총액"] = df["시가총액"]

    return out


# =========================================================
# corp_code 다운로드
# =========================================================
def get_corp_code_map():
    url = f"https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key={API_KEY}"
    r = requests.get(url)

    try:
        z = zipfile.ZipFile(io.BytesIO(r.content))
    except:
        print(r.text[:1000])
        raise Exception("OpenDart API KEY 오류")

    xml_data = z.read(z.namelist()[0])
    root = ET.fromstring(xml_data)

    rows = []
    for item in root.findall("list"):
        stock_code = item.findtext("stock_code")
        if stock_code is None:
            continue
        stock_code = stock_code.strip()
        if stock_code == "":
            continue

        rows.append(
            {
                "corp_code": item.findtext("corp_code"),
                "corp_name": item.findtext("corp_name"),
                "stock_code": stock_code,
            }
        )

    return pd.DataFrame(rows)


# =========================================================
# OpenDart API 호출
# =========================================================
session = requests.Session()


def fetch_quarter(corp_code, year, report_code, fs_div):
    if stop_event.is_set():
        return None

    url = "https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json"
    params = {
        "crtfc_key": API_KEY,
        "corp_code": corp_code,
        "bsns_year": year,
        "reprt_code": report_code,
        "fs_div": fs_div,
    }

    for attempt in range(MAX_RETRIES):
        time.sleep(SLEEP_SEC)
        try:
            r = session.get(
                url, params=params, headers=HEADERS, timeout=TIMEOUT
            )
            data = r.json()
        except Exception:
            # 네트워크 순단 등 일시적 오류 -> 잠깐 쉬었다가 재시도
            if attempt < MAX_RETRIES - 1:
                time.sleep(2**attempt)
                continue
            return None

        status = data.get("status")

        if status == "000":
            df = pd.DataFrame(data.get("list", []))
            return df if len(df) > 0 else None

        with status_lock:
            status_counter[status] += 1

        if status in GLOBAL_ERROR_STATUS:
            # 키 인증/사용한도 등 전역 오류 -> 재시도해도 계속 실패하므로
            # 남은 모든 요청을 즉시 중단시킨다
            if not stop_event.is_set():
                stop_reason["status"] = status
                stop_reason["message"] = data.get("message", "")
                stop_event.set()
            return None

        # "013"(해당 데이터 없음) 등은 정상적인 개별 케이스이므로 재시도하지 않는다
        return None

    return None


# =========================================================
# 계정 추출
# =========================================================
def extract_amount(df, patterns):
    """OpenDart 재무제표 API(fnlttSinglAcntAll)의 금액은 항상 '원' 단위로
    제공되므로, 별도의 단위 환산 없이 그대로 사용한다."""
    try:
        mask = (
            df["account_nm"]
            .astype(str)
            .str.contains(patterns, regex=True, na=False)
        )
        sub = df[mask]

        if len(sub) == 0:
            return np.nan

        # 당기금액(thstrm_amount) 우선 검색 후 없으면 전기금액 확인
        cols = ["thstrm_amount", "frmtrm_amount"]
        for c in cols:
            if c in sub.columns:
                val = to_float(sub.iloc[0][c])
                if pd.notna(val):
                    return val
        return np.nan
    except:
        return np.nan


# =========================================================
# 종목별 재무 수집
# =========================================================
def fetch_financial(row):
    stock_code = row.stock_code
    corp_code = row.corp_code

    result = {"stock_code": stock_code}

    try:
        for year, report_code, qname in TARGET_Q:
            if stop_event.is_set():
                break

            df = None

            # 연결(CFS) → 개별(OFS) 순으로 시도
            for fs_div in ["CFS", "OFS"]:
                df = fetch_quarter(
                    corp_code, year, report_code, fs_div
                )
                if df is not None:
                    break

            if df is None:
                continue

            # 계정명 공백 정리
            df["account_nm"] = (
                df["account_nm"].astype(str).str.strip()
            )

            # 1. 매출액 추출 (원 단위)
            sales = extract_amount(
                df,
                (
                    "매출액|"
                    "영업수익|"
                    "^수익$|"
                    "보험영업수익|"
                    "이자수익"
                ),
            )
            result[f"{qname}_매출액"] = sales

            # 2. 영업이익 추출 (원 단위)
            op = extract_amount(df, ("영업이익|" "영업손익"))
            result[f"{qname}_영업이익"] = op

            # 3. 당기순이익 추출 (원 단위)
            ni = extract_amount(
                df,
                (
                    "당기순이익|"
                    "분기순이익|"
                    "반기순이익|"
                    "연결당기순이익"
                ),
            )
            result[f"{qname}_당기순이익"] = ni

            # 4. 자본총계 추출 (원 단위)
            equity = extract_amount(df, ("자본총계|" "자본계"))

            # 5. 영업활동현금흐름 추출 (원 단위, ★PCR 계산용)
            ocf = extract_amount(
                df,
                (
                    "영업활동현금흐름|"
                    "영업활동으로인한현금흐름|"
                    "영업활동으로 인한 현금흐름"
                ),
            )
            result[f"{qname}_영업활동현금흐름"] = ocf

            # 6. 영업이익률 계산
            if (
                pd.notna(sales)
                and pd.notna(op)
                and sales != 0
            ):
                result[f"{qname}_영업이익률"] = round(
                    op / sales * 100, 2
                )

            # 7. ROE 계산
            if (
                pd.notna(ni)
                and pd.notna(equity)
                and equity != 0
            ):
                result[f"{qname}_ROE"] = round(
                    ni / equity * 100, 2
                )

    except:
        pass

    return result


# =========================================================
# 병렬수집
# =========================================================
def collect_all(df):
    rows = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [
            executor.submit(fetch_financial, row)
            for row in df.itertuples(index=False)
        ]

        for future in tqdm(
            as_completed(futures), total=len(futures)
        ):
            try:
                rows.append(future.result())
            except:
                pass

            # 전역 오류(사용한도 초과 등)가 감지되면, 아직 시작하지 않은
            # 나머지 요청은 취소해 헛수고를 막는다(이미 실행 중인 요청은 계속됨)
            if stop_event.is_set():
                for f in futures:
                    f.cancel()

    if stop_event.is_set():
        print()
        print("!" * 60)
        print(
            f"OpenDart API 전역 오류(status={stop_reason.get('status')})로 "
            "나머지 종목 수집을 중단했습니다."
        )
        print(f"메시지: {stop_reason.get('message')}")
        print("이미 수집된 데이터만 저장합니다. (예: 사용한도 초과 시 내일 다시 시도)")
        print("!" * 60)

    return pd.DataFrame(rows)


# =========================================================
# 메인 실행부
# =========================================================
def main():
    t0 = time.time()

    print("=" * 60)
    print("수집 대상 최근 5개 분기 (오늘 날짜 기준 자동 산출)")
    print("=" * 60)
    for year, report_code, qname in TARGET_Q:
        print(f"  {qname} (bsns_year={year}, reprt_code={report_code})")
    print()

    # 1. 종목 리스트 구성
    print("=" * 60)
    print("종목리스트 수집")
    print("=" * 60)
    df_stock = get_stock_list()
    print(df_stock.shape)
    print(df_stock.head())
    print()

    # 2. OpenDart 고유번호 매핑
    print("=" * 60)
    print("corp_code 매핑")
    print("=" * 60)
    df_code = get_corp_code_map()
    print(df_code.shape)
    print()

    df_stock = df_stock.merge(
        df_code[["stock_code", "corp_code"]],
        on="stock_code",
        how="left",
    )
    df_stock = df_stock[df_stock["corp_code"].notna()].copy()
    print(df_stock.shape)
    print()

    # 3. 5분기 재무 데이터 병렬 수집
    print("=" * 60)
    print("최근 5분기 재무 및 현금흐름 수집")
    print("=" * 60)
    df_fin = collect_all(df_stock)
    print()
    print(df_fin.shape)
    if status_counter:
        print("OpenDart 비정상 status 코드 집계 (진단용):", dict(status_counter))
    print()

    # 4. 종목 정보와 재무 데이터 데이터프레임 병합
    print("=" * 60)
    print("데이터 병합 및 포맷팅")
    print("=" * 60)
    df_final = df_stock.merge(df_fin, on="stock_code", how="left")

    # 5. 분기별 PCR 연산
    # 시가총액과 영업활동현금흐름 모두 '원' 단위로 통일되어 있으므로
    # 별도의 단위 환산 없이 바로 나눈다.
    print("=" * 60)
    print("분기별 PCR 자동 계산")
    print("=" * 60)
    for year, report_code, qname in TARGET_Q:
        ocf_col = f"{qname}_영업활동현금흐름"
        pcr_col = f"{qname}_PCR"

        if ocf_col in df_final.columns:
            # 안전장치: 시가총액이 존재하고, 영업활동현금흐름이 0보다 큰(흑자) 경우만 PCR 계산
            df_final[pcr_col] = np.where(
                (df_final[ocf_col] > 0)
                & (df_final["시가총액"].notna()),
                round(df_final["시가총액"] / df_final[ocf_col], 2),
                np.nan,
            )

    # 6. 결측치(NaN) 처리
    # OpenDart에 해당 계정이 없거나 조회되지 않아 비어 있는 재무 지표는
    # 종목/시가총액 등 식별 정보를 제외하고 0으로 채운다.
    print("=" * 60)
    print("결측치(NaN) -> 0 채우기")
    print("=" * 60)
    id_cols = ["stock_code", "corp_name", "시가총액", "corp_code"]
    metric_cols = [c for c in df_final.columns if c not in id_cols]
    df_final[metric_cols] = df_final[metric_cols].fillna(0)
    print()

    print(df_final.shape)
    print(df_final.head())
    print()

    # 7. CSV 저장
    print("=" * 60)
    print("최종 파일 저장")
    print("=" * 60)
    df_final.to_csv(
        OUTPUT_FILE, index=False, encoding="utf-8-sig"
    )
    print(f"저장 완료: {OUTPUT_FILE}")
    print()
    print(
        "총 소요시간:",
        round(time.time() - t0, 1),
        "초",
    )


if __name__ == "__main__":
    main()
