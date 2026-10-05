#!/usr/bin/env bash
# timelog.sh · 单批 20 分钟收口流水线打点闸（2026-10-06 产品拍板，计划书 §7.5）
# 用法：
#   bash tools/timelog.sh start <slug> [备注]   # 开工记起点（重置本批日志）
#   bash tools/timelog.sh mark <段名>           # 段末打点（P0开工/P1实现/P2门禁/P3文档/P4提交推送，段间串行自上一打点起算）
#   bash tools/timelog.sh report                # 分段耗时＋总时长＋≤20 分钟判定（收尾仪式第 1 步必须贴这行）
# 判「超」时须在交接文档 §5 变更日志行尾归因三选：工单欠预编译／门禁超时／网络回退。
# 日志落 gitignored tmp/timelog/<slug>.log；同一时刻只跟踪最近一次 start（tmp/timelog/.last）。
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGD="$DIR/tmp/timelog"
mkdir -p "$LOGD"
CUR="$LOGD/.last"
cmd="${1:-}"
case "$cmd" in
  start)
    slug="${2:?用法: timelog.sh start <slug> [备注]}"
    log="$LOGD/$slug.log"
    : > "$log"
    printf '%s' "$slug" > "$CUR"
    printf '%s\t%s\n' "$(date +%s)" "start（${3:-未注}）" >> "$log"
    echo "TIMELOG-START $slug $(date '+%F %T')"
    ;;
  mark)
    [ -f "$CUR" ] || { echo "TIMELOG-ERR 未 start（先 bash tools/timelog.sh start <slug>）"; exit 1; }
    slug="$(cat "$CUR")"; log="$LOGD/$slug.log"
    [ -f "$log" ] || { echo "TIMELOG-ERR 日志缺失 $log"; exit 1; }
    label="${2:?用法: timelog.sh mark <段名>}"
    printf '%s\t%s\n' "$(date +%s)" "$label" >> "$log"
    echo "MARK $label $(date '+%F %T')"
    ;;
  report)
    slug="$(cat "$CUR" 2>/dev/null || true)"
    log="$LOGD/${slug:-_none_}.log"
    [ -f "$log" ] || { echo "TIMELOG-ERR 无日志（$log）"; exit 1; }
    echo "== timelog report · $slug =="
    awk -F'\t' '
      NR==1 { prev=$1; pl="起点"; next }
      { d=$1-prev; printf "  %-24s %dm%02ds（自 %s）\n", $2, int(d/60), d%60, pl; prev=$1; pl=$2; tot+=d }
      END {
        printf "  总计 %dm%02ds — %s\n", int(tot/60), tot%60,
          (tot<=1200 ? "≤20min 达标" : "超20min：变更日志行尾归因（工单欠预编译/门禁超时/网络回退）")
      }' "$log"
    ;;
  *)
    echo "用法: bash tools/timelog.sh start|mark|report（见文件头注释）"; exit 1 ;;
esac
