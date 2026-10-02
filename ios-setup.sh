#!/usr/bin/env bash
# `cap add ios` 직후 실행: 캘린더/미리알림 권한 안내 문구와 앱 이름을 Info.plist 에 넣는다.
set -euo pipefail
PLIST="ios/App/App/Info.plist"
PB=/usr/libexec/PlistBuddy

setkey () {  # 키가 있으면 바꾸고 없으면 추가
  "$PB" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 string $2" "$PLIST"
}

setkey CFBundleDisplayName "나의 캘린더"
setkey NSCalendarsUsageDescription "아이폰 캘린더의 일정을 보여주고, 앱에서 만든 일정을 캘린더에 저장하기 위해 필요해요."
setkey NSCalendarsFullAccessUsageDescription "아이폰 캘린더의 기존 일정을 불러오고, 앱에서 만든 일정을 캘린더에 저장·수정하기 위해 필요해요."
setkey NSCalendarsWriteOnlyAccessUsageDescription "앱에서 만든 일정을 아이폰 캘린더에 저장하기 위해 필요해요."
setkey NSRemindersUsageDescription "할 일을 아이폰 미리알림과 함께 쓰기 위해 필요해요."
setkey NSRemindersFullAccessUsageDescription "아이폰 미리알림의 할 일을 불러오고, 앱에서 만든 할 일을 미리알림에 저장하기 위해 필요해요."
echo "Info.plist 설정 완료"

# 캘린더 플러그인: 할 일 마감이 자정(00:00)이면 시각 없이 '날짜만'으로 저장 → 아이폰에서 종일 할 일
for f in node_modules/@ebarooni/capacitor-calendar/ios/Plugin/Models/Inputs/{Create,Modify}ReminderInput.swift; do
  perl -0pi -e 's/(\n(\s*)component\.timeZone = Calendar\.current\.timeZone\n)(?!\s*if component\.hour == 0)/$1$2if component.hour == 0 \&\& component.minute == 0 { component.hour = nil; component.minute = nil; component.timeZone = nil }\n/g' "$f"
  [ "$(grep -c 'component.hour = nil' "$f")" = 2 ] || { echo "플러그인 수정 실패: $f"; exit 1; }
done
echo "할 일 종일 처리 수정 완료"
