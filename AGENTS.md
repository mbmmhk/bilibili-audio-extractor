# 仓库说明（给 AI 助手 / 开发者）

- `backend/`：Python 识别后端（FastAPI）。测试：`cd backend && uv run pytest`。
- `frontend/`：网页界面（React + Vite）。检查：`cd frontend && npm run build`。
- `mac/`：原生 Mac App。**做 Mac 界面前先读 [mac/AGENTS.md](mac/AGENTS.md)**，设计见 [mac/ARCHITECTURE.md](mac/ARCHITECTURE.md)。

约定：

- 回复和界面文案用简体中文。
- 提交信息里不要写 AI 工具的署名（不加 `Co-Authored-By` 之类的行）。
- 不要直接推 master：在分支上做，开 PR 合并。master 的每次推送都会给一键安装的用户发布新版。
