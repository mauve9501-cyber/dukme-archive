# 덕메 아카이브 · The Stage, Ours

덕메끼리만 보는 비공개 공연 사진 아카이브. 정적 사이트(Vercel) + Supabase(Auth·DB·Storage).

- 로그인: 이메일 매직링크. `dm_members`에 등록된(초대된) 이메일만 입장
- 공연 기록(날짜·공연장·좌석·셋리스트·메모), 사진 업로드(자동 압축, 드래그&드롭), 하이라이트·캡션·대표 사진, 사진별 실시간 코멘트
- 덕메 초대/내보내기는 앱 안에서(상단 이름 버튼)

## 구성
| 파일 | 역할 |
|---|---|
| `index.html` | 앱 전체 |
| `config.js` | Supabase URL + publishable 키(공개 안전, 보호는 RLS) |
| `supabase-schema.sql` | 테이블·RLS·스토리지 버킷(`dukme-photos`, 비공개). 재실행 안전 |
| `.github/workflows/keepalive.yml` | 무료 플랜 일시정지 방지 핑 |

Supabase 프로젝트는 `mydesignpark-branding`을 공유하므로 모든 객체에 `dm_` 접두어를 씁니다.
Supabase → Authentication → URL Configuration 의 Redirect URLs 에 배포 주소가 있어야 매직링크가 돌아옵니다.
