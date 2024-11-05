#!/bin/bash

set -e
set -o pipefail

# 定义日志相关变量
LOG_DIR="$(git rev-parse --show-toplevel)/logs"
LOG_FILE="$LOG_DIR/post-push.log"

# 创建日志目录（如果不存在）
mkdir -p "$LOG_DIR"

# 记录日志的函数
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# 定义子库配置数组
# 每个子库配置包含三个元素：本地路径、远程仓库地址、分支名
declare -A SUBTREES=(
    ["src/subtree1"]="git@github.com:username/subtree1.git main"
    ["src/subtree2"]="git@github.com:lengmousoul/subtree2.git ros2"
    # 在这里添加更多子库配置
    # ["path/to/subtree3"]="remote_url branch_name"
)

log "Post-push hook triggered!"

# 拉取最新的远程更改
git fetch origin

# 获取当前分支名
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
# 获取本地和远程分支的 SHA
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")

# 检查是否需要向主库推送
if [ -z "$REMOTE_SHA" ] || [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    log "Detected changes in main repository. Attempting to push to main remote..."
    
    # 推送到主库
    if git push origin "$CURRENT_BRANCH"; then
        log "Successfully pushed changes to main repository."
    else
        log "Failed to push changes to main repository."
        exit 1
    fi
else
    log "No changes to push to main repository."
fi

# 遍历所有配置的子库
for SUBTREE_PATH in "${!SUBTREES[@]}"; do
    # 解析远程仓库地址和分支
    SUBTREE_CONFIG=(${SUBTREES[$SUBTREE_PATH]})
    SUBTREE_REMOTE=${SUBTREE_CONFIG[0]}
    SUBTREE_BRANCH=${SUBTREE_CONFIG[1]}
    
    log "Processing subtree: $SUBTREE_PATH"
    
    # 检查子库路径是否存在
    if [ ! -d "$SUBTREE_PATH" ]; then
        log "Warning: Subtree path '$SUBTREE_PATH' does not exist. Skipping."
        continue
    fi
    
    # 检查是否有未提交的更改
    if ! git diff --quiet -- "$SUBTREE_PATH"; then
        log "Warning: Uncommitted changes detected in subtree path '$SUBTREE_PATH'. Skipping."
        continue
    fi
    
    # 检查是否有对该子库的更改
    if git diff --quiet "$LOCAL_SHA" "$REMOTE_SHA" -- "$SUBTREE_PATH"; then
        log "No changes detected for subtree '$SUBTREE_PATH'. Skipping."
        continue
    fi
    
    log "Attempting to push changes for '$SUBTREE_PATH' to '$SUBTREE_REMOTE' on branch '$SUBTREE_BRANCH'..."
    
    # 尝试推送子库更改
    if git subtree push --prefix="$SUBTREE_PATH" "$SUBTREE_REMOTE" "$SUBTREE_BRANCH" >> "$LOG_FILE" 2>&1; then
        log "Successfully pushed subtree '$SUBTREE_PATH' to '$SUBTREE_REMOTE' on branch '$SUBTREE_BRANCH'."
    else
        log "Failed to push subtree '$SUBTREE_PATH' to '$SUBTREE_REMOTE'."
        # 继续处理其他子库，而不是立即退出
        continue
    fi
done

log "Post-push hook completed!"


