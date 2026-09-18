#!/bin/bash
# ig-autopost — 今日の日付のキューがあれば投稿する。毎日 launchd から呼ばれる。
#
# キューの置き方:
#   ~/.config/ig/queue/YYYY-MM-DD.caption   キャプション本文
#   ~/.config/ig/queue/YYYY-MM-DD.urls      画像の公開URL（1行1枚、2枚以上でカルーセル）
# 投稿に成功すると .done を付けてリネームするので、二重投稿は起きない。

set -uo pipefail

IG="$HOME/.config/ig/ig"
Q="$HOME/.config/ig/queue"
LOG="$HOME/.config/ig/autopost.log"

log()    { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
notify() { osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true; }

TODAY=$(date '+%F')
CAP="$Q/$TODAY.caption"
URLS="$Q/$TODAY.urls"

if [[ ! -f "$CAP" || ! -f "$URLS" ]]; then
  log "$TODAY: 予約なし"
  exit 0
fi

if [[ ! -x "$IG" ]]; then
  log "$TODAY: ig が見つかりません ($IG)"
  notify "Instagram 自動投稿" "ig コマンドが見つからず投稿できませんでした"
  exit 1
fi

urls=()
while IFS= read -r u; do
  [[ -n "${u// /}" ]] && urls+=("$u")
done < "$URLS"

if (( ${#urls[@]} == 0 )); then
  log "$TODAY: URL が空です"
  notify "Instagram 自動投稿" "画像URLが空のため投稿できませんでした"
  exit 1
fi

# 投稿前に全URLが取得可能か確認する（Meta 側が取得できないと必ず失敗するため）
for u in "${urls[@]}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$u")
  if [[ "$code" != "200" ]]; then
    log "$TODAY: 画像が取得できません ($code) $u"
    notify "Instagram 自動投稿" "画像を取得できず中止しました"
    exit 1
  fi
done

if (( ${#urls[@]} >= 2 )); then
  out=$(IG_YES=1 "$IG" carousel "$(cat "$CAP")" "${urls[@]}" 2>&1)
else
  out=$(IG_YES=1 "$IG" post "${urls[0]}" "$(cat "$CAP")" 2>&1)
fi

if [[ $? -eq 0 ]] && grep -q '公開しました' <<<"$out"; then
  log "$TODAY: 成功 — $(grep '公開しました' <<<"$out" | tail -1)"
  notify "Instagram 自動投稿" "$TODAY の投稿を公開しました"
  mv "$CAP" "$CAP.done"
  mv "$URLS" "$URLS.done"
  exit 0
else
  log "$TODAY: 失敗 — ${out//$'\n'/ | }"
  notify "Instagram 自動投稿" "投稿に失敗しました。autopost.log を確認してください"
  exit 1
fi
