# Kiro CLI 런타임 어댑터 (Kiro CLI Runtime Adapter)

> harness를 **Kiro CLI**(`kiro-cli`) 런타임에서 실행할 때의 적응 규칙.
> harness의 기본 런타임은 Claude Code이며, 본 어댑터는 **기능을 100% 보존**한 채
> Claude Code 전용 요소(멀티에이전트 도구 · 산출물 형식 · 포인터 위치 · 설치 방식)만
> Kiro CLI 대응물로 매핑한다. 6-Phase 워크플로우와 6 아키텍처 패턴은 런타임 독립적이므로 그대로 유지한다.

## 목차

1. 언제 이 문서를 적용하는가
2. 무엇이 바뀌고 무엇이 그대로인가
3. 도구 매핑 (Claude Code → Kiro CLI)
4. 산출물 형식 변환
5. 6 아키텍처 패턴의 Kiro 구현
6. 계층적 재귀 위임 우회
7. 설치 방식
8. 검증 체크리스트 (Kiro)

---

## 1. 언제 이 문서를 적용하는가

다음 중 하나라도 해당하면 SKILL.md 본문의 Claude Code 지시 대신 **본 어댑터의 매핑을 우선 적용**한다:

- 실행 환경이 `kiro-cli`임이 확인될 때 (사용자가 Kiro 사용을 명시, 또는 작업 트리에 `.kiro/`가 존재)
- 산출물을 `.kiro/agents/`, `.kiro/skills/`에 생성해야 할 때

호스트가 Claude Code이면 이 문서를 무시하고 SKILL.md 본문을 그대로 따른다.

## 2. 무엇이 바뀌고 무엇이 그대로인가

| 구분 | Claude Code (기본) | Kiro CLI | 변경 |
|------|--------------------|----------|:----:|
| 6-Phase 워크플로우 | 동일 | 동일 | 무변경 |
| 6 아키텍처 패턴 | 동일 | 동일 (구현 도구만 매핑) | 무변경 |
| 멀티에이전트 도구 | `TeamCreate`/`SendMessage`/`TaskCreate`/`Agent` | `subagent`/`session-management`/`/spawn` | **매핑** |
| 에이전트 정의 | `.claude/agents/{name}.md` | `.kiro/agents/{name}.json` | **변환** |
| 스킬 정의 | `.claude/skills/{name}/SKILL.md` | `.kiro/skills/{name}/SKILL.md` | 위치만 |
| 하네스 포인터 | `CLAUDE.md` | `.kiro/steering/{name}.md` | **변환** |
| 설치 | 플러그인 마켓플레이스 / `~/.claude/skills/` | `install.sh --host kiro` / `~/.kiro/skills/` | **매핑** |

## 3. 도구 매핑 (Claude Code → Kiro CLI)

| Claude Code | Kiro CLI | 의미 |
|-------------|----------|------|
| `TeamCreate(team, members)` | `session-management`의 `manage_group(action:"create")` + 멤버별 `spawn_session` | 팀 구성 |
| `SendMessage(target, message)` | `session-management`의 `send_message(target, message, priority)` | 팀원 간 통신(inbox) |
| `TaskCreate`/`TaskUpdate` (동적 작업) | `subagent`의 `stages[]` + `depends_on` (정적 DAG) | 작업 분배·의존성 |
| `Agent(subagent_type, run_in_background)` | `subagent` 병렬 `stages[]` 또는 `/spawn` | 서브에이전트 호출 |
| 결과 반환 | 서브에이전트의 `summary` 도구 | 결과 보고 |
| 빌트인 `general-purpose` | Kiro 기본 에이전트(`kiro_default`) 또는 커스텀 JSON | 범용 |
| 빌트인 `Explore` (읽기전용) | `tools`를 `read`/`grep`/`glob`로 제한한 에이전트 | 탐색 |
| 빌트인 `Plan` | `kiro_planner` (`/plan`) | 계획 |
| `model: "opus"` | 에이전트 JSON의 `"model": "<kiro-model-id>"` | 모델 지정 |

> **핵심 차이**: Claude Code의 `TaskCreate`는 런타임 중 동적으로 작업을 생성하지만, Kiro의 `subagent`는
> 호출 시점에 `stages` DAG가 정적으로 고정된다. 동적 작업 흐름이 필요하면 `session-management`의
> `spawn_session` + `send_message` + `interrupt`로 구성한다 (섹션 5의 Supervisor 패턴 참조).

## 4. 산출물 형식 변환

### 4-1. 에이전트: `.claude/agents/{name}.md` → `.kiro/agents/{name}.json`

Claude Code 에이전트는 마크다운(역할·원칙·프로토콜을 본문에 기술)이지만, Kiro 에이전트는 **JSON config**다.
마크다운 본문은 JSON의 `prompt` 필드로 옮긴다.

```json
{
  "name": "analyst",
  "description": "도메인 요구사항을 분석하고 작업 유형을 식별한다.",
  "prompt": "당신은 분석 전문가다. 핵심 역할/작업 원칙/입출력 프로토콜/에러 핸들링/협업 규칙은 다음과 같다: ...",
  "tools": ["read", "grep", "glob", "subagent"],
  "allowedTools": ["read", "grep", "glob"],
  "resources": ["skill://.kiro/skills/analyze/SKILL.md"],
  "model": "<kiro-model-id>"
}
```

변환 규칙:
- 마크다운의 `## 핵심 역할`, `## 작업 원칙`, `## 입출력 프로토콜`, `## 에러 핸들링`, `## 협업/팀 통신 프로토콜` → `prompt` 문자열로 통합
- 에이전트가 사용할 스킬 → `resources`에 `skill://` URI로 연결
- 오케스트레이터 역할 에이전트는 `tools`에 `subagent`를 포함해야 다른 에이전트를 파이프라인으로 호출 가능
- `kiro-cli agent validate --path .kiro/agents/{name}.json`으로 스키마 검증

### 4-2. 스킬: `.claude/skills/` → `.kiro/skills/` (형식 동일)

스킬은 양쪽 모두 `SKILL.md` + YAML frontmatter(`name`, `description`)로 동일하다. **위치만** `.kiro/skills/`로 바꾼다.
`references/`, `scripts/`, `assets/` 번들 구조도 그대로 유지한다. Progressive Disclosure도 동일하게 동작한다.

### 4-3. 포인터: `CLAUDE.md` → `.kiro/steering/{name}.md`

Kiro CLI는 `CLAUDE.md`를 읽지 않는다. 대신 `.kiro/steering/`의 마크다운을 컨텍스트로 로드한다.
하네스 포인터는 steering 파일로 작성하고 frontmatter로 로딩 시점을 제어한다.

```markdown
---
inclusion: always
---

# 하네스: {도메인명}

**트리거:** {도메인} 관련 작업 시 `{orchestrator-skill-name}` 스킬을 사용하라.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| {YYYY-MM-DD} | 초기 구성 | 전체 | - |
```

> `inclusion: always`는 매 세션 로드(CLAUDE.md와 동일 효과), `manual`은 `#파일명` 수동 로드, `fileMatch`는 특정 파일 작업 시 로드.

## 5. 6 아키텍처 패턴의 Kiro 구현

| 패턴 | Kiro 구현 |
|------|-----------|
| **파이프라인** | `subagent` `stages[]`를 `depends_on` 체인으로 연결 (A→B→C) |
| **팬아웃/팬인** | `subagent`에서 의존성 없는 stages를 병렬 배치 + fan-in stage가 `depends_on`으로 수집 |
| **전문가 풀** | 메인 에이전트가 상황에 따라 필요한 `role`의 stage만 선택 호출 |
| **생성-검증** | `subagent` 2-stage (producer → reviewer, `depends_on`) |
| **감독자** | `session-management`로 `spawn_session`(persistent) + `send_message`/`interrupt`/`inject_context`로 동적 조율 |
| **계층적 위임** | 섹션 6 참조 (Kiro 제약 우회 필요) |

**파이프라인 예시 (`subagent` 도구):**

```json
{
  "task": "도메인 하네스 구축",
  "stages": [
    {"name": "analyze", "role": "analyst", "prompt_template": "{task} 도메인 분석"},
    {"name": "build", "role": "builder", "prompt_template": "{task} 구현", "depends_on": ["analyze"]},
    {"name": "qa", "role": "qa", "prompt_template": "{task} 검증", "depends_on": ["build"]}
  ]
}
```

## 6. 계층적 재귀 위임 우회

**제약**: Kiro CLI의 `subagent`는 **서브에이전트가 다시 서브에이전트를 생성할 수 없다**
(공식 문서: "Subagents cannot spawn additional subagents" — 무한 재귀 방지).
따라서 harness의 "계층적 위임(상위가 하위에 재귀적 위임)" 패턴은 `subagent`만으로는 1단계로 제한된다.

**우회 전략 (택1):**

1. **평탄화 (권장)**: 재귀 계층을 메인 오케스트레이터가 중앙에서 관리하는 **감독자(Supervisor) 패턴**으로 재구성한다.
   상위 에이전트가 직접 하위를 재귀 호출하는 대신, 메인이 각 레벨을 순차/병렬 `subagent` 호출로 평탄화한다.
2. **세션 기반 위임**: `session-management`의 `spawn_session(persistent: true)`으로 지속 세션을 만들고,
   `send_message`로 하위 작업을 위임한다. (서브에이전트 재귀 금지는 `subagent` 도구에 적용되며,
   `session-management`는 오케스트레이션 레이어에서 동작한다. 실제 깊이 제한은 환경에서 검증할 것.)
3. **명시적 제한**: 위 둘이 부적합하면 "Kiro에서는 계층 깊이 N까지만 지원"을 오케스트레이터에 명시하고
   초과 깊이는 평탄화로 처리한다.

> harness가 계층적 위임 패턴을 생성할 때 Kiro 호스트이면, 기본값으로 **전략 1(평탄화)**을 적용하고
> 오케스트레이터 스킬에 그 사실을 기록한다.

## 7. 설치 / 삭제

Kiro CLI에는 플러그인 마켓플레이스가 없다. harness는 빌드가 없는 순수 마크다운 스킬이므로 **복사 설치**한다. Kiro는 user(전역)와 project(워크스페이스) 두 스코프를 지원하며, 워크스페이스가 전역보다 우선한다.

```bash
# user 스코프 (전역, 기본) -> ~/.kiro/skills/harness
./install.sh --host kiro

# project 스코프 (현재 워크스페이스) -> ./.kiro/skills/harness
./install.sh --host kiro --scope project

# 삭제 (--uninstall; 안전장치: SKILL.md 없는 디렉토리는 제거 거부)
./install.sh --host kiro --uninstall                 # user 스코프 제거
./install.sh --host kiro --scope project --uninstall # project 스코프 제거

# 수동 복사도 가능
cp -r skills/harness ~/.kiro/skills/harness
```

설치 후 새 `kiro-cli` 세션에서 해당 스코프의 `.kiro/skills/harness/`가 자동 발견되며,
"하네스 구성해줘" 자연어로 트리거된다. (`.claude-plugin/plugin.json`은 Claude Code 전용이며 Kiro는 무시한다.)

## 8. 검증 체크리스트 (Kiro)

생성 완료 후 확인:

- [ ] `.kiro/agents/{name}.json` — JSON 스키마 유효 (`kiro-cli agent validate`)
- [ ] `.kiro/skills/{name}/SKILL.md` — frontmatter `name`/`description` 존재
- [ ] 오케스트레이터 에이전트의 `tools`에 `subagent` 포함
- [ ] 팀 통신이 필요하면 `session-management` 사용 경로 명시
- [ ] 하네스 포인터를 `.kiro/steering/`에 작성 (`CLAUDE.md` 아님)
- [ ] 계층적 위임 패턴은 평탄화(또는 세션 기반)로 우회 처리
- [ ] `.claude/` 경로 산출물이 생성되지 않았는지 확인 (Kiro 호스트에서는 `.kiro/`만)
