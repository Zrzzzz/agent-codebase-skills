<!-- init-agents-md:begin v1 nested -->
## frontend 模块约定（由 init-agents-md 维护）

> 本文件是仓库根 [`AGENTS.md`](../AGENTS.md) 的子目录延伸——根约定全部继承，本文件只写本模块特有的 delta。

### 范围
本目录及其子目录的代码归本文件管。跨模块的规则（命名、提交、CI、依赖方向）不要写在这里，那些归根 memory 文件。

### 模块特征
- **职责**：面向买家的电商 SPA（商品列表 / 详情 / 购物车 / 结算）。
- **技术栈**：React 19 + Vite + TanStack Query；样式用 CSS Modules，禁止引入新的 UI 库。
- **启动 / 构建 / 测试命令**：
  ```bash
  pnpm --filter frontend dev        # 本地开发，代理 /api 到 localhost:8000
  pnpm --filter frontend test       # vitest
  pnpm --filter frontend build
  ```
- **目录边界**：只允许通过 `src/api/client.ts` 调后端 `/api/v1/*`；组件不得直接 fetch。
- **本模块特有约定**：页面级组件放 `src/pages/<route>/`，通用组件进 `src/components/` 且必须带 stories。

### 分层路由（本模块内）
- 本模块特有约定 → 本文件
- 仓库级通用约定 → 根 memory 文件
- 任务/进度 → 仓库根 `docs/TASKS.md`（用 `[frontend]` 前缀区分）
- 决策/踩坑 → 仓库根 `docs/session-notes.md`（hook 自动追加，无需手动）
- 本模块特有的可复用流程（如「本模块部署」「本模块种子数据重置」）→ `.claude/skills/frontend-<action>/`

<!-- init-agents-md:end -->
