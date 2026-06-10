#!/bin/bash

# 確保指令遇到錯誤時停止
set -e

if [ "$#" -ne 2 ]; then
    echo "用法: $0 <專案名稱> <目標路徑>"
    echo "範例: $0 MyGateway /path/to/my-gateway"
    exit 1
fi

PROJECT_NAME=$1
TARGET_DIR=$2

# 驗證專案名稱只允許英數字、.、_、-
if ! echo "$PROJECT_NAME" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "錯誤：專案名稱只允許英文字母、數字、.、_、- 組成。"
    echo "請勿使用空格、斜線或特殊字元。"
    exit 1
fi

# 將專案名稱轉為小寫做為 Docker Container 名稱使用
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')

# 取得腳本所在的目錄 (模板根目錄)
TEMPLATE_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -d "$TARGET_DIR" ]; then
    echo "錯誤：目標路徑 $TARGET_DIR 已存在，請指定一個新的空目錄。"
    exit 1
fi

echo "開始建立新專案: $PROJECT_NAME 於 $TARGET_DIR ..."
echo "  步驟：複製檔案、更新設定、複製 .env、更新 CLAUDE.md/AGENTS.md 標題、初始化 Git"

# 1. 複製檔案 (排除 .git 與本腳本)
# 優先使用 rsync；無 rsync 的環境（alpine、最小化 CI）改用 tar 複製
mkdir -p "$TARGET_DIR"
if command -v rsync >/dev/null 2>&1; then
    rsync -av --exclude='.git' --exclude='create-project.sh' "$TEMPLATE_DIR/" "$TARGET_DIR/"
else
    echo "（未偵測到 rsync，改用 tar 複製）"
    tar -C "$TEMPLATE_DIR" --exclude='.git' --exclude='create-project.sh' -cf - . \
        | tar -C "$TARGET_DIR" -xf -
fi

# 2. 自動修改 docker-compose.yml
COMPOSE_FILE="$TARGET_DIR/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    # 支援 macOS (BSD sed) 與 Linux (GNU sed)
    if sed --version >/dev/null 2>&1; then
        sed -i "s/image: openresty-template:local/image: ${PROJECT_NAME_LOWER}:local/g" "$COMPOSE_FILE"
        sed -i "s/container_name: openresty-template/container_name: ${PROJECT_NAME_LOWER}/g" "$COMPOSE_FILE"
    else
        sed -i '' "s/image: openresty-template:local/image: ${PROJECT_NAME_LOWER}:local/g" "$COMPOSE_FILE"
        sed -i '' "s/container_name: openresty-template/container_name: ${PROJECT_NAME_LOWER}/g" "$COMPOSE_FILE"
    fi
    echo "已更新 docker-compose.yml"
fi

# 3. 更新 .env.sample 的 SERVICE_NAME
ENV_SAMPLE_FILE="$TARGET_DIR/.env.sample"
if [ -f "$ENV_SAMPLE_FILE" ]; then
    if sed --version >/dev/null 2>&1; then
        sed -i "s/SERVICE_NAME=GatewayTemplate/SERVICE_NAME=${PROJECT_NAME}/g" "$ENV_SAMPLE_FILE"
    else
        sed -i '' "s/SERVICE_NAME=GatewayTemplate/SERVICE_NAME=${PROJECT_NAME}/g" "$ENV_SAMPLE_FILE"
    fi
    echo "已更新 .env.sample 的 SERVICE_NAME"
    # 同時複製一份為 .env，讓新專案可直接 docker compose up
    cp "$ENV_SAMPLE_FILE" "$TARGET_DIR/.env"
    echo "已複製 .env.sample → .env（可直接 docker compose up --build -d）"
fi

# 3b. 更新 CLAUDE.md 標題（第一行）
CLAUDE_MD_FILE="$TARGET_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD_FILE" ]; then
    if sed --version >/dev/null 2>&1; then
        sed -i "1s/openresty-template Agent Guide/${PROJECT_NAME} Agent Guide/" "$CLAUDE_MD_FILE"
    else
        sed -i '' "1s/openresty-template Agent Guide/${PROJECT_NAME} Agent Guide/" "$CLAUDE_MD_FILE"
    fi
    echo "已更新 CLAUDE.md 標題"
fi

# 3c. 更新 AGENTS.md 標題（第一行，僅當包含 openresty-template 時）
# 注意：AGENTS.md 第一行格式為「# AGENTS.md — openresty-template」（無 Agent Guide 字樣）
AGENTS_MD_FILE="$TARGET_DIR/AGENTS.md"
if [ -f "$AGENTS_MD_FILE" ]; then
    AGENTS_FIRST_LINE=$(head -n 1 "$AGENTS_MD_FILE")
    if echo "$AGENTS_FIRST_LINE" | grep -q "openresty-template"; then
        if sed --version >/dev/null 2>&1; then
            sed -i "1s/openresty-template/${PROJECT_NAME}/" "$AGENTS_MD_FILE"
        else
            sed -i '' "1s/openresty-template/${PROJECT_NAME}/" "$AGENTS_MD_FILE"
        fi
        echo "已更新 AGENTS.md 標題"
    fi
fi

# 4. 重新命名 VHost 檔案
VHOST_FILE="$TARGET_DIR/vhost/default.vhost"
if [ -f "$VHOST_FILE" ]; then
    mv "$VHOST_FILE" "$TARGET_DIR/vhost/${PROJECT_NAME_LOWER}.vhost"
    echo "已重命名 vhost 為 ${PROJECT_NAME_LOWER}.vhost"
fi

# 5. 初始化 Git
echo "初始化 Git ..."
cd "$TARGET_DIR"
git init
git add .
if ! git commit -m "feat: initial commit from OpenResty gateway template"; then
    echo ""
    echo "⚠️  警告：Git 初始 commit 失敗（可能尚未設定 user.name / user.email）。"
    echo "   Repository 已初始化，請手動執行："
    echo "     git config user.name '你的名字'"
    echo "     git config user.email 'you@example.com'"
    echo "     git commit -m 'feat: initial commit from OpenResty gateway template'"
fi

echo "專案建立完成！"
echo ""
echo "下一步請執行："
echo "  cd $TARGET_DIR"
echo "  # 確認並編輯 .env（已從 .env.sample 自動複製）"
echo "  docker compose up --build -d"
