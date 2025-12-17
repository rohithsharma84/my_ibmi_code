
#!/QOpenSys/pkgs/bin/bash
# export_source_to_ifs.sh - periodic one-way export of IBM i source members to IFS
# Features:
# - --export-path (alias: --base-path) points to export ROOT; final base path is <ROOT>/<LIBRARY>
#   Default: $HOME/source/<LIBRARY>
# - Uses QSYS2.SYSMEMBERSTAT for member metadata and LAST_SOURCE_UPDATE_TIMESTAMP
# - CPYTOSTMF to IFS (UTF-8 LF), then touch -t to set file mtime to the source timestamp
# - Maintains index.csv and snapshot index_<timestamp>.csv (keep last 7 snapshots)
# - Moves deleted members to SRCPF/deleted/
# - Progress messages every 50 ("Exported n files..." or "Would export...")
# - Options: --dry-run, --srcpf <SRCPF>
#
# Requirements in PASE: db2util, jq
#   yum install db2util jq
#
# References:
# SYSMEMBERSTAT: https://www.ibm.com/docs/en/i/7.6.0?topic=services-sysmemberstat-view
# CPYTOSTMF:     https://www.ibm.com/docs/en/i/7.4?topic=ssw_ibm_i_74/cl/cpytostmf.html
# AIX touch -t:  https://www.ibm.com/docs/en/aix/7.1.0?topic=t-touch-command
# db2util:       https://github.com/IBM/ibmi-db2util

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

validate_objname() {
  local name="$1"
  [[ -z "$name" ]] && die "Name is required."
  [[ ${#name} -le 10 ]] || die "Name must be <= 10 characters."
  [[ "$name" =~ ^[A-Za-z0-9#@$]+$ ]] || die "Name must contain only Aâ€“Z, 0â€“9, #, @, $."
}

uppercase() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

ts_sql_to_touch() {
  # Input: "YYYY-MM-DD HH:MM:SS[.fraction]"
  # Output: "YYYYMMDDHHMM.SS" for touch -t
  local in="$1"
  echo "$in" | awk '{
    split($0, parts, /[ \.]/);
    split(parts[1], d, /-/);
    split(parts[2], t, /:/);
    printf("%s%s%s%s%s.%s", d[1], d[2], d[3], t[1], t[2], t[3]);
  }'
}

# Split RPG/RPGLE, CBL/CBLLE, CLP/CLLE into distinct extensions
map_ext() {
  local st="$1"
  case "$st" in
    RPG)            echo "rpg" ;;
    RPGLE)          echo "rpgle" ;;
    SQLRPGLE)       echo "sqlrpgle" ;;
    CLP)            echo "clp" ;;
    CLLE)           echo "clle" ;;
    CMD)            echo "cmd" ;;
    DSPF)           echo "dspf" ;;
    PRTF)           echo "prtf" ;;
    LF)             echo "lf" ;;
    PF)             echo "pf" ;;
    C)              echo "c" ;;
    CBL)            echo "cbl" ;;
    CBLLE)          echo "cblle" ;;
    SQL)            echo "sql" ;;
    TXT)            echo "txt" ;;
    *)              echo "mbr" ;;
  esac
}

# ---------- Parse args ----------
[[ $# -ge 1 ]] || die "Usage: $0 <LIBRARY> [--export-path <root>] [--dry-run] [--srcpf <SRCPF>]"

LIBRARY_RAW="$1"; shift
validate_objname "$LIBRARY_RAW"
LIBRARY="$(uppercase "$LIBRARY_RAW")"

# export root default is $HOME/source; final base path is <root>/<LIBRARY>
EXPORT_ROOT_DEFAULT="${HOME:-/home/$(id -un)}/source"
EXPORT_ROOT="$EXPORT_ROOT_DEFAULT"
DRY_RUN=false
FILTER_SRCPF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export-path|--base-path)
      shift
      [[ $# -gt 0 ]] || die "--export-path requires a value"
      EXPORT_ROOT="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --srcpf)
      shift
      [[ $# -gt 0 ]] || die "--srcpf requires a value"
      validate_objname "$1"
      FILTER_SRCPF="$(uppercase "$1")"
      shift
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

# Final base path is <export-root>/<LIBRARY>
BASE_IFS_PATH="${EXPORT_ROOT%/}/$LIBRARY"

# ---------- Check dependencies ----------
need_cmd db2util
need_cmd jq

# ---------- Prep paths ----------
mkdir -p "$BASE_IFS_PATH"
mkdir -p "$BASE_IFS_PATH/tracking"
INDEX_PATH="$BASE_IFS_PATH/tracking/index.csv"

SNAP_TS="$(date +%Y%m%d_%H%M%S)"
SNAP_PATH="$BASE_IFS_PATH/tracking/index_${SNAP_TS}.csv"
CHANGES_PATH="$BASE_IFS_PATH/tracking/changes_${SNAP_TS}.csv"
PREVIEW_PATH="$BASE_IFS_PATH/tracking/index_preview_${SNAP_TS}.csv" # only for --dry-run

START_TIME=$(date +%s)

echo "Starting copy for library: $LIBRARY"
echo "Export root: $EXPORT_ROOT"
echo "IFS base path: $BASE_IFS_PATH"
$DRY_RUN && echo "Mode: DRY-RUN (no changes will be made)"

# ---------- Load existing index ----------
declare -A idx_ts
declare -A idx_ext
declare -A idx_path

if [[ -f "$INDEX_PATH" ]]; then
  while IFS='|' read -r lib srcpf member srctype ext last_ts ifs_path; do
    [[ "$lib" == "LIBRARY" ]] && continue
    [[ -z "$srcpf" || -z "$member" ]] && continue
    key="${srcpf}|${member}"
    idx_ts["$key"]="$last_ts"
    idx_ext["$key"]="$ext"
    idx_path["$key"]="$ifs_path"
  done < "$INDEX_PATH"
fi

echo "LIBRARY|SRCPF|MEMBER|SOURCE_TYPE|EXT|LAST_SOURCE_UPDATE_TS|IFS_PATH" > "$SNAP_PATH"
echo "ACTION|LIBRARY|SRCPF|MEMBER|SOURCE_TYPE|EXT|LAST_SOURCE_UPDATE_TS|IFS_PATH" > "$CHANGES_PATH"
$DRY_RUN && echo "LIBRARY|SRCPF|MEMBER|SOURCE_TYPE|EXT|LAST_SOURCE_UPDATE_TS|IFS_PATH" > "$PREVIEW_PATH"

GLOBAL_EXPORTED=0
GLOBAL_WOULD_EXPORT=0
GLOBAL_DELETED=0
PER_FILE_COUNT=0

build_srcpf_query() {
  if [[ -n "$FILTER_SRCPF" ]]; then
    echo "SELECT SYSTEM_TABLE_NAME AS SRCPF
          FROM QSYS2.SYSTABLES
          WHERE SYSTEM_TABLE_SCHEMA='${LIBRARY}'
            AND FILE_TYPE='S'
            AND SYSTEM_TABLE_NAME='${FILTER_SRCPF}'"
  else
    echo "SELECT SYSTEM_TABLE_NAME AS SRCPF
          FROM QSYS2.SYSTABLES
          WHERE SYSTEM_TABLE_SCHEMA='${LIBRARY}'
            AND FILE_TYPE='S'"
  fi
}

srcpf_json="$(db2util -o json "$(build_srcpf_query)")" || die "db2util SYSTABLES failed"
mapfile -t SRCPF_LIST < <(echo "$srcpf_json" | jq -r '.records[]? | .SRCPF | gsub(" +$"; "")')

if [[ -n "$FILTER_SRCPF" && ${#SRCPF_LIST[@]} -eq 0 ]]; then
  die "Source file '$FILTER_SRCPF' not found in library '$LIBRARY'."
fi

for SRCPF in "${SRCPF_LIST[@]}"; do
  [[ -z "$SRCPF" ]] && continue

  echo "Processing source file: $SRCPF"
  SRCPF_DIR="$BASE_IFS_PATH/$SRCPF"
  mkdir -p "$SRCPF_DIR"
  mkdir -p "$SRCPF_DIR/deleted"
  PER_FILE_COUNT=0

  members_json="$(db2util -o json "
    SELECT SYSTEM_TABLE_MEMBER AS MEMBER,
           SOURCE_TYPE,
           VARCHAR_FORMAT(LAST_SOURCE_UPDATE_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') AS LASTSRCUPD
    FROM QSYS2.SYSMEMBERSTAT
    WHERE SYSTEM_TABLE_SCHEMA='${LIBRARY}'
      AND SYSTEM_TABLE_NAME='${SRCPF}'
      AND SOURCE_TYPE IS NOT NULL
  ")" || die "db2util SYSMEMBERSTAT failed for $SRCPF"

  declare -A current_set
  mapfile -t MEMBERS < <(echo "$members_json" | jq -r '.records[]? | [(.MEMBER | rtrimstr(" ")), .SOURCE_TYPE, .LASTSRCUPD] | @tsv')

  for row in "${MEMBERS[@]}"; do
    IFS=$'\t' read -r MEMBER SRCTYPE LASTSRCUPD <<< "$row"
    [[ -z "$MEMBER" ]] && continue

    current_set["$MEMBER"]=1
    PER_FILE_COUNT=$((PER_FILE_COUNT + 1))

    EXT="$(map_ext "$SRCTYPE")"
    TARGET_FILE="$SRCPF_DIR/${MEMBER}.${EXT}"

    key="${SRCPF}|${MEMBER}"
    prev_ts="${idx_ts[$key]:-}"
    need_export=0
    if [[ -z "$prev_ts" ]]; then
      need_export=1
      echo "NEW|$LIBRARY|$SRCPF|$MEMBER|$SRCTYPE|$EXT|$LASTSRCUPD|$TARGET_FILE" >> "$CHANGES_PATH"
    elif [[ "$LASTSRCUPD" > "$prev_ts" ]]; then
      need_export=1
      echo "UPDATE|$LIBRARY|$SRCPF|$MEMBER|$SRCTYPE|$EXT|$LASTSRCUPD|$TARGET_FILE" >> "$CHANGES_PATH"
    fi

    if (( need_export )); then
      if $DRY_RUN; then
        GLOBAL_WOULD_EXPORT=$((GLOBAL_WOULD_EXPORT + 1))
        if (( GLOBAL_WOULD_EXPORT % 50 == 0 )); then
          echo "Would export $GLOBAL_WOULD_EXPORT files..."
        fi
      else
        # Build CL command in a single line to avoid broken quotes
        CLCMD="CPYTOSTMF FROMMBR('/QSYS.LIB/$LIBRARY.LIB/$SRCPF.FILE/$MEMBER.MBR') TOSTMF('$TARGET_FILE') STMFOPT(*REPLACE) STMFCCSID(1208) ENDLINFMT(*LF)"
        
        # Temporarily disable exit on error to capture output
        set +e
        CPYOUT="$(/QOpenSys/usr/bin/system "$CLCMD" 2>&1)"
        CPYRC=$?
        set -e
        
        if [[ $CPYRC -eq 0 ]]; then
          TOUCH_TS="$(ts_sql_to_touch "$LASTSRCUPD")"
          touch -m -t "$TOUCH_TS" "$TARGET_FILE"
          GLOBAL_EXPORTED=$((GLOBAL_EXPORTED + 1))
          if (( GLOBAL_EXPORTED % 50 == 0 )); then
            echo "Exported $GLOBAL_EXPORTED files..."
          fi
        else
          echo "ERROR: Failed to export $SRCPF/$MEMBER (exit code: $CPYRC)"
          echo "Command: $CLCMD"
          echo "Output: $CPYOUT"
          echo "Continuing with next member..."
        fi
      fi
    fi

    echo "$LIBRARY|$SRCPF|$MEMBER|$SRCTYPE|$EXT|$LASTSRCUPD|$TARGET_FILE" >> "$SNAP_PATH"
    $DRY_RUN && echo "$LIBRARY|$SRCPF|$MEMBER|$SRCTYPE|$EXT|$LASTSRCUPD|$TARGET_FILE" >> "$PREVIEW_PATH"

    idx_ts["$key"]="$LASTSRCUPD"
    idx_ext["$key"]="$EXT"
    idx_path["$key"]="$TARGET_FILE"
  done

  # Deletions
  if [[ -f "$INDEX_PATH" ]]; then
    while IFS='|' read -r lib srcpf member srctype ext last_ts ifs_path; do
      [[ "$lib" == "LIBRARY" ]] && continue
      [[ "$srcpf" != "$SRCPF" ]] && continue
      if [[ -z "${current_set[$member]:-}" ]]; then
        old_ext="${ext:-$(map_ext "$srctype")}"
        SRC_FILE="$SRCPF_DIR/${member}.${old_ext}"
        DEL_FILE="$SRCPF_DIR/deleted/${member}.${old_ext}"
        # Only process if the source file still exists (not already deleted)
        if [[ -f "$SRC_FILE" ]]; then
          echo "DELETE|$LIBRARY|$SRCPF|$member|$srctype|$old_ext|${last_ts:-}|$DEL_FILE" >> "$CHANGES_PATH"

          if $DRY_RUN; then
            echo "Would move deleted member: $member"
          else
            mv -f "$SRC_FILE" "$DEL_FILE"
            echo "Moved deleted member to: $DEL_FILE"
          fi
          GLOBAL_DELETED=$((GLOBAL_DELETED + 1))
        fi

        echo "$LIBRARY|$SRCPF|$member|$srctype|$old_ext|${last_ts:-}|$DEL_FILE" >> "$SNAP_PATH"
        $DRY_RUN && echo "$LIBRARY|$SRCPF|$member|$srctype|$old_ext|${last_ts:-}|$DEL_FILE" >> "$PREVIEW_PATH"
      fi
    done < "$INDEX_PATH"
  fi

  echo -e "Completed: $SRCPF ($PER_FILE_COUNT members)\n"
  unset current_set
  declare -A current_set
done

# Persist index / snapshots
if $DRY_RUN; then
  echo "DRY-RUN: index.csv NOT updated."
  echo "Preview index: $PREVIEW_PATH"
  
  # Keep only the most recent preview file
  previews=( $(ls -1t "$BASE_IFS_PATH/tracking"/index_preview_*.csv 2>/dev/null || true) )
  if (( ${#previews[@]} > 1 )); then
    for f in "${previews[@]:1}"; do
      rm -f "$f"
    done
  fi
else
  # Update index.csv
  if [[ -n "$FILTER_SRCPF" && -f "$INDEX_PATH" ]]; then
    # Merge mode: Keep entries from other SRCPFs, replace entries for filtered SRCPF
    TEMP_INDEX="${INDEX_PATH}.tmp"
    
    # Copy header
    head -1 "$INDEX_PATH" > "$TEMP_INDEX"
    
    # Copy all entries EXCEPT the filtered SRCPF
    tail -n +2 "$INDEX_PATH" | while IFS='|' read -r lib srcpf member srctype ext last_ts ifs_path; do
      if [[ "$srcpf" != "$FILTER_SRCPF" ]]; then
        echo "$lib|$srcpf|$member|$srctype|$ext|$last_ts|$ifs_path"
      fi
    done >> "$TEMP_INDEX"
    
    # Append new entries for the filtered SRCPF
    tail -n +2 "$SNAP_PATH" >> "$TEMP_INDEX"
    
    # Replace index with merged version
    mv -f "$TEMP_INDEX" "$INDEX_PATH"
    echo "Updated index.csv (merged data for $FILTER_SRCPF)"
  else
    # Full replacement mode
    cp -f "$SNAP_PATH" "$INDEX_PATH"
  fi
  
  # Keep only last 7 index snapshots
  snapshots=( $(ls -1t "$BASE_IFS_PATH/tracking"/index_*.csv 2>/dev/null || true) )
  if (( ${#snapshots[@]} > 7 )); then
    to_delete_count=$(( ${#snapshots[@]} - 7 ))
    for f in "${snapshots[@]:7}"; do
      rm -f "$f"
    done
  fi
  
  # Keep only last 7 changes files
  changes=( $(ls -1t "$BASE_IFS_PATH/tracking"/changes_*.csv 2>/dev/null || true) )
  if (( ${#changes[@]} > 7 )); then
    to_delete_count=$(( ${#changes[@]} - 7 ))
    for f in "${changes[@]:7}"; do
      rm -f "$f"
    done
  fi
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo "Copy complete. Files in: $BASE_IFS_PATH"
if $DRY_RUN; then
  echo "Total that would be exported in this run: $GLOBAL_WOULD_EXPORT | Deleted: $GLOBAL_DELETED"
else
  echo "Total exported in this run: $GLOBAL_EXPORTED | Deleted: $GLOBAL_DELETED"
fi
if [[ $MINUTES -gt 0 ]]; then
  echo "Time taken: ${MINUTES}m ${SECONDS}s"
else
  echo "Time taken: ${SECONDS}s"
fi
echo
