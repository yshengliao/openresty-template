#!/bin/bash
# openresty-template 整合測試腳本
# 用法：bash test.sh [BASE_URL]
# 預設 BASE_URL=http://localhost:8080

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
PASS=0
FAIL=0
ERRORS=()

# ── 顏色輸出 ──────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_status() {
    local desc="$1"
    local expected="$2"
    local url="$3"
    shift 3
    local actual
    actual=$(curl -s -o /dev/null -w "%{http_code}" "$@" "$url")
    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✅ $desc${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ $desc (expected: $expected, got: $actual)${NC}"
        ERRORS+=("$desc")
        FAIL=$((FAIL + 1))
    fi
}

check_body() {
    local desc="$1"
    local pattern="$2"
    local url="$3"
    shift 3
    local body
    body=$(curl -s "$@" "$url")
    if echo "$body" | grep -q "$pattern"; then
        echo -e "${GREEN}✅ $desc${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ $desc (pattern '$pattern' not found in: $body)${NC}"
        ERRORS+=("$desc")
        FAIL=$((FAIL + 1))
    fi
}

check_no_header() {
    local desc="$1"
    local header="$2"
    local url="$3"
    shift 3
    local headers
    # 用 -D - -o /dev/null 取得 response header（GET），避免觸發不存在的 HEAD.lua
    headers=$(curl -s -D - -o /dev/null "$@" "$url")
    if echo "$headers" | grep -qi "^$header:"; then
        echo -e "${RED}❌ $desc (header '$header' should be absent but was present)${NC}"
        ERRORS+=("$desc")
        FAIL=$((FAIL + 1))
    else
        echo -e "${GREEN}✅ $desc${NC}"
        PASS=$((PASS + 1))
    fi
}

check_header() {
    local desc="$1"
    local header="$2"
    local url="$3"
    shift 3
    local headers
    # 用 -D - -o /dev/null 取得 response header（GET），避免觸發不存在的 HEAD.lua
    headers=$(curl -s -D - -o /dev/null "$@" "$url")
    if echo "$headers" | grep -qi "^$header:"; then
        echo -e "${GREEN}✅ $desc${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ $desc (header '$header' not found)${NC}"
        ERRORS+=("$desc")
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "======================================"
echo " openresty-template 整合測試"
echo " BASE_URL: $BASE_URL"
echo "======================================"
echo ""

# ── 基本端點 ──────────────────────────────────────────────
echo "── 基本端點 ──"
check_status "GET /healthcheck → 200"  "200" "$BASE_URL/healthcheck"
check_body   "GET /healthcheck body = 'ok'" "ok" "$BASE_URL/healthcheck"
check_status "GET /ping → 200"         "200" "$BASE_URL/ping"
check_body   "GET /ping body = 'pong'" "pong" "$BASE_URL/ping"
check_status "GET / → 404"            "404" "$BASE_URL/"

# ── API 端點 ──────────────────────────────────────────────
echo ""
echo "── API 端點 ──"
check_status "GET /api/v1/hello → 200" "200" "$BASE_URL/api/v1/hello"
check_body   "GET /api/v1/hello 含 message" "message" "$BASE_URL/api/v1/hello"
check_body   "GET /api/v1/hello 含 timestamp" "timestamp" "$BASE_URL/api/v1/hello"

# ── Method override ──────────────────────────────────────
echo ""
echo "── Method override ──"
check_status "X-Http-Method 路徑穿越 → 405" "405" "$BASE_URL/api/v1/hello" \
    -H "X-Http-Method: ../../etc/passwd"

check_status "X-Http-Method-Override 非法 → 405" "405" "$BASE_URL/api/v1/hello" \
    -H "X-Http-Method-Override: INVALID_METHOD"

check_status "X-Http-Method 合法 override POST→GET → 200" "200" "$BASE_URL/api/v1/hello" \
    -X POST -H "X-Http-Method: GET"

# ── API 驗證（httparg） ─────────────────────────────────
echo ""
echo "── API 驗證 ──"
# GET /api/v1/example：query 驗證 + assertion.max CAP 行為
check_status "GET /api/v1/example 無 query → 200"               "200" "$BASE_URL/api/v1/example"
check_body   "GET /api/v1/example 含 items"                     "items" "$BASE_URL/api/v1/example"
check_status "GET /api/v1/example?status=unknown → 400"         "400" "$BASE_URL/api/v1/example?status=unknown"
check_status "GET /api/v1/example?limit=999 → 200（max 是 CAP）" "200" "$BASE_URL/api/v1/example?limit=999"
check_body   "GET limit=999 response capped to 100"             '"limit":100' "$BASE_URL/api/v1/example?limit=999"

# POST /api/v1/example：JSON body 驗證
check_status "POST valid body → 200" "200" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"name":"demo","amount":50}'
check_body   "POST valid body 含 created" "created" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"name":"demo","amount":50}'
check_status "POST 缺 name → 400" "400" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"amount":50}'
check_status "POST amount=-1 → 400（non_negative_number）" "400" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"name":"demo","amount":-1}'
check_status "POST amount=abc → 400（type coercion）" "400" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"name":"demo","amount":"abc"}'
check_status "POST amount=99999 → 400（業務 guard >10000）" "400" "$BASE_URL/api/v1/example" \
    -X POST -H 'Content-Type: application/json' -d '{"name":"demo","amount":99999}'

# ── 安全 Headers ─────────────────────────────────────────
echo ""
echo "── 安全 Headers ──"
check_no_header "Server header 已移除" "Server" "$BASE_URL/healthcheck"
check_header    "X-Content-Type-Options: nosniff" "X-Content-Type-Options" "$BASE_URL/api/v1/hello"
check_header    "X-Frame-Options: DENY" "X-Frame-Options" "$BASE_URL/api/v1/hello"
check_header    "Content-Security-Policy" "Content-Security-Policy" "$BASE_URL/api/v1/hello"
check_header    "Referrer-Policy" "Referrer-Policy" "$BASE_URL/api/v1/hello"

# ── 結果摘要 ─────────────────────────────────────────────
echo ""
echo "======================================"
echo " 結果：${PASS} 通過 / ${FAIL} 失敗"
echo "======================================"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "失敗項目："
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    echo ""
    exit 1
fi

echo ""
exit 0
