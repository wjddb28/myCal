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
