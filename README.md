# 나의 캘린더

다중·반복·기간·일반 일정과 할 일을 구분해서 쓰는 캘린더 앱.
아이폰 앱으로 설치하면 **아이폰 캘린더·미리알림을 직접** 읽고 씁니다.

| 실행 방법 | 연동 |
|---|---|
| **아이폰 앱** (이 문서의 설치 방법) | 아이폰 캘린더·미리알림 직접 사용 (+ 아이폰에 추가한 구글 계정 → 구글·노션 캘린더) |
| **PC** — `start.bat` 더블클릭 | 구글 캘린더 API, iCloud(앱 암호), ICS 파일 |

## 폴더 구조

```
www/index.html                 앱 화면 전체 (PC·아이폰 공용)
server.py, start.bat           PC용 로컬 서버 (iCloud 중계 포함)
capacitor.config.json          아이폰 앱 설정 (앱 이름, 번들 ID)
scripts/ios-setup.sh           캘린더·미리알림 권한 안내 문구 설정
.github/workflows/ios.yml      GitHub에서 아이폰 앱 파일(.ipa)을 자동으로 빌드
```

---

## 아이폰에 설치하기 (Mac 없이, 무료)

Mac이 없으므로 **GitHub의 무료 클라우드 Mac**에서 앱을 빌드하고,
Windows용 **Sideloadly**로 무료 Apple ID를 사용해 아이폰에 설치합니다.

### 1단계 · GitHub에 올리기 (처음 한 번)

1. [github.com](https://github.com)에서 계정 만들기
2. 오른쪽 위 **＋ → New repository** → 이름 `my-calendar`, **Private** 선택 → Create
3. [GitHub Desktop](https://desktop.github.com)을 설치하고 로그인
4. **File → Add local repository** → 이 폴더(`C:\유정\캘린더앱`) 선택 → “create a repository” 누르기
5. **Publish repository** → 방금 만든 `my-calendar`로 올리기 (Private 유지)

### 2단계 · 앱 파일 받기 (약 10~15분, 자동)

1. GitHub의 저장소 페이지 → **Actions** 탭 → **아이폰 앱 빌드**
   - 올리면 자동으로 시작돼요. 안 보이면 **Run workflow**를 누르세요.
2. 초록 체크 ✅가 뜨면 그 실행을 누르고 → 아래쪽 **Artifacts → MyCalendar-ipa** 다운로드
3. 받은 zip의 압축을 풀면 `MyCalendar.ipa`가 나와요.

> 빨간 ✕가 뜨면 그 실행의 로그를 Claude에게 보여주세요. 첫 빌드는 한두 번 손봐야 할 수 있어요.

### 3단계 · 아이폰에 설치

1. PC에 설치할 것
   - [Sideloadly](https://sideloadly.io) (Windows)
   - **애플 웹사이트 버전**의 iTunes와 iCloud (Microsoft Store 버전은 안 돼요). Sideloadly 안내를 따르세요.
2. 아이폰을 USB로 PC에 연결 → 아이폰에서 “이 컴퓨터를 신뢰” 허용
3. Sideloadly에 `MyCalendar.ipa`를 끌어다 놓고 → Apple ID 입력 → **Start**
   - Apple ID 암호가 Sideloadly를 거쳐 애플로 전송돼요. 걱정되면 설치용 보조 Apple ID를 써도 돼요.
4. 아이폰 설정
   - **설정 → 개인정보 보호 및 보안 → 개발자 모드** 켜기 (재시동됨)
   - **설정 → 일반 → VPN 및 기기 관리** → 내 Apple ID → **신뢰**
5. 앱 실행 → 캘린더·미리알림 권한 창에서 **전체 접근 허용**

### 7일마다 해야 할 것

무료 Apple ID로 설치한 앱은 **7일 뒤 실행이 안 돼요.** 그 전에 Sideloadly로 같은 `.ipa`를 다시 설치하면 됩니다.
일정은 아이폰 캘린더·미리알림에 저장돼 있어서 **재설치해도 사라지지 않아요.**

- 무료 Apple ID 제한: 직접 설치한 앱은 동시에 3개까지
- 매번 설치가 번거로우면 연 $99 Apple 개발자 계정 + TestFlight로 바꿀 수 있어요 (빌드 설정만 변경).

### 앱을 고친 뒤

`www/index.html`을 수정하고 GitHub Desktop에서 **Commit → Push** 하면 새 `.ipa`가 자동으로 빌드돼요. 2~3단계를 반복하세요.

---

## 아이폰 앱에서 동작 방식

| 앱 | 아이폰 |
|---|---|
| 일정 | 캘린더 앱 일정 |
| 할 일 | 미리알림 (체크하면 양쪽 모두 완료) |
| 카테고리 | 아이폰 캘린더 / 미리알림 목록 (같은 이름끼리 연결, 없으면 처음 쓸 때 만들어짐) |
| 반복·기간 일정 | 아이폰에서도 그대로 반복·기간 일정 |
| 다중 일정 | 날짜별 일정 여러 개로 저장, 앱에서는 하나로 묶어서 표시 |

- 아이폰 캘린더 앱에서 바꾼 내용은 앱으로 돌아올 때마다 반영돼요.
- **아이폰에서 만든 반복 일정**, 구독·공휴일·생일 캘린더는 앱에서 볼 수만 있어요. 누르면 아이폰 캘린더 앱으로 연결돼요.
  (캘린더 플러그인이 반복 규칙을 읽어오지 못해서, 앱에서 고치면 반복이 지워질 수 있기 때문이에요.)
- 반복 일정의 “이 날짜만 삭제”는 아이폰 앱에서 지원하지 않아요. 전체 삭제 또는 반복 규칙 수정은 돼요.
- 구글·노션 캘린더: 아이폰 **설정 → 앱 → 캘린더 → 캘린더 계정**에 구글 계정을 추가하면 자동으로 함께 보여요.
