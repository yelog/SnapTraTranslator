# SnapTra Translator

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

커서 아래 단어를 스크린 캡처 및 OCR 로 즉시 번역하는 경량 macOS 메뉴바 앱입니다. 단축키를 누르고 텍스트 위에 커서를 올리면 번역, 발음 기호, 사전 정의가 표시되는 아름다운 플로팅 풍선이 나타납니다.

## 미리보기

<p>
  <img src="docs/Xnip2026-01-19_10-55-57.png" alt="설정" width="64%" />
</p>

## 스크린샷

<p>
  <img src="docs/Xnip2026-01-19_00-02-09.png" alt="번역 풍선" width="49%" />
  <img src="docs/Xnip2026-01-19_00-06-14.png" alt="사전 정의" width="49%" />
</p>

## 기능

### 핵심 번역
- **즉시 OCR 번역** - 커서 주변의 화면 영역을 캡처하고 포인터에 가장 가까운 단어 감지
- **플로팅 풍선** - 번역 결과와 함께 커서 근처에 표시되는 현대적인 반투명 풍선
- **사전 정의** - 품사 (명사, 동사, 형용사 등) 별로 그룹화된 자세한 단어 정의
- **발음 기호** - 인식된 단어의 발음 기호 표시
- **음성 합성** - 번역 후 옵션으로 발음 재생

### 번역 모드
- **연속 번역** - 단축키를 누른 상태로 마우스를 이동하면 번역 계속
- **단일 조회 모드** - 단축키를 한 번 누를 때마다 한 번 조회, 풍선은 인터랙티브 (복사, 닫기 버튼)

### 지원 언어
중국어 (간체), 중국어 (번체), 영어, 일본어, 한국어, 프랑스어, 독일어, 스페인어, 이탈리아어, 포르투갈어, 러시아어, 아랍어, 태국어, 베트남어

### 사용자 정의
- **단일 키 단축키** - 수식 키 (Shift, Control, Option, Command, Fn) 에서 트리거 키 선택
- **언어 선택** - 번역 언어쌍 선택
- **로그인 시 시작** - 로그인 시 자동 시작
- **OCR 디버그 영역** - 문제 해결을 위해 캡처 영역과 감지된 단어 경계 상자 시각화

### 기타 기능
- **클립보드에 복사** - 단어 또는 번역 빠른 복사
- **학습 단어 내보내기** - 조회한 단어를 TXT, Anki TSV 또는 CSV로 저장
- **언어 팩 감지** - 누락된 언어 팩 자동 확인 및 알림
- **메뉴바 앱** - Dock 을 어지럽히지 않고 메뉴바에서 조용히 실행

## 다운로드

[Mac App Store](https://apps.apple.com/cn/app/snaptra-translator/id6757981764) 에서 이용 가능

## 요구사항

- macOS 14+ (번역 기능에는 macOS 15 의 시스템 번역 API 필요)
- 화면 기록 권한 (OCR 캡처에 필수)

## 빌드 및 실행

Xcode 에서 열기:
```bash
open "SnapTra Translator.xcodeproj"
```

명령줄에서 빌드:
```bash
# 디버그 빌드
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Debug build

# 릴리스 빌드
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" -configuration Release build

# 클린
xcodebuild -project "SnapTra Translator.xcodeproj" -scheme "SnapTra Translator" clean
```

## 사용 방법

1. **권한 부여** - 앱을 실행하고 화면 기록 권한 부여
2. **설정 구성** - 설정 창에서 선호하는 단축키 및 언어쌍 설정
3. **번역** - 단축키를 누른 상태로 텍스트 위에 커서를 올리면 번역, 발음 기호, 정의와 함께 풍선 표시
4. **닫기** - 단축키를 놓아 닫기 (단일 조회 모드에서는 X 클릭)

## 문제 해결

- **풍선이 나타나지 않음** - 시스템 설정 > 개인정보 및 보안 > 화면 기록에서 권한 확인
- **macOS 15 에서 번역 누락** - 시스템 설정 > 일반 > 언어 및 지역 > 번역 언어에서 언어 팩 설치
- **단축키가 작동하지 않음** - 다른 앱이 동일한 키를 사용하지 않는지 확인하고 다른 수식 키 시도
- **풍선이 화면 가장자리에서 잘림** - "OCR 디버그 영역"을 활성화하여 캡처 영역 확인 및 커서 위치 조정

## 라이선스

MIT License
