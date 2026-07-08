# Session Notes（自动生成）

> 本文件由 `.claude/hooks/summarize-session.sh`（SessionEnd hook）在每次会话结束时自动追加。
> 内容是对话要点的 LLM 提炼，供今后开发参考；可随时手工编辑/裁剪。

---

## 2026-06-28 21:47

- 决定优惠券金额校验只在后端做，前端仅展示可用列表——防止金额被前端篡改。
- 确认后端本地起服命令为 `uv run fastapi dev backend/main.py`，端口 8000，前端 dev 代理已对齐。
- 踩坑：pnpm v9 workspace 协议要求 `workspace:*`，用 v8 的锁文件会解析失败；全员统一 pnpm ≥ 9。

## 2026-07-01 18:02

- T-plp-perf 商品列表首屏 LCP 从 3.4s 降到 1.6s：首屏 4 张图改 AVIF + preload，其余懒加载。
- 新约定：所有性能优化必须在本文件记录 baseline 前后数字，方便回归对照。
- dev 服 nginx 对 `/api` 有 10s proxy_read_timeout，长任务接口一律改异步任务队列。
