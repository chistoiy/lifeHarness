#!/usr/bin/env bash
# timelog.sh · 单批 20 分钟收口流水线打点闸（2026-10-06 产品拍板，计划书 §7.5）
# 用法：
#   bash tools/timelog.sh start <slug> [备注] [--from '<YYYY-MM-DD HH:MM:SS>']
#       # 开工记起点；--from 回填首动作时刻（如批在工装可用前已起跑）
#   bash tools/timelog.sh mark <段名>
#       # 段末打点；**窗外动作（构建/上传/装机）段名以「窗外·」开头，不计窗内判定**
#   bash tools/timelog.sh report
#       # 分段耗时＋窗内净耗（≤20 分钟判定按此）＋窗外小计＋表内总计（收尾第 1 步必贴）
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
    slug="${2:?用法: timelog.sh start <slug> [备注] [--from '<ts>']}"
    log="$LOGD/$slug.log"
    shift 2
    from=""; note=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --from) from="${2:?--from 需要时间串}"; shift 2 ;;
        *) note="${note:+$note }$1"; shift ;;
      esac
    done
    if [ -n "$from" ]; then
      ts=$(date -d "$from" +%s) || { echo "TIMELOG-ERR --from 解析失败: $from"; exit 1; }
    else
      ts=$(date +%s)
    fi
    : > "$log"
    printf '%s' "$slug" > "$CUR"
    printf '%s\t%s\n' "$ts" "start（${note:-未注}）" >> "$log"
    echo "TIMELOG-START $slug $(date -d "@$ts" '+%F %T')$( [ -n "$from" ] && echo '（--from 回填）')"
    ;;
  mark)
    [ -f "$CUR" ] || { echo "TIMELOG-ERR 未 start（先 bash tools/timelog.sh start <slug>）"; exit 1; }
    slug="$(cat "$CUR")"; log="$LOGD/$slug.log"
    [ -f "$log" ] || { echo "TIMELOG-ERR 日志缺失 $log"; exit 1; }
    label="${2:?用法: timelog.sh mark <段名>（窗外段用「窗外·」前缀）}"
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
      {
        d=$1-prev
        if ($2 ~ /^窗外/) {
          printf "  %-30s %dm%02ds（自 %s）· 窗外不计\n", $2, int(d/60), d%60, pl
          out+=d
        } else {
          printf "  %-30s %dm%02ds（自 %s）\n", $2, int(d/60), d%60, pl
          tot+=d
        }
        prev=$1; pl=$2
      }
      END {
        printf "  窗内净耗 %dm%02ds — %s\n", int(tot/60), tot%60, \
          (tot<=1200 ? "≤20min 达标" : "超20min：变更日志行尾归因（工单欠预编译/门禁超时/网络回退）")
        printf "  窗外段小计 %dm%02ds · 表内总计 %dm%02ds\n", int(out/60), out%60, int((tot+out)/60), (tot+out)%60
      }' "$log"
    ;;
  *)
    echo "用法: bash tools/timelog.sh start|mark|report（见文件头注释）"; exit 1 ;;
esac
