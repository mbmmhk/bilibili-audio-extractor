import clsx from "clsx";
import { AudioLines, LoaderCircle, Plus, TriangleAlert } from "lucide-react";
import { isFinished, type Job } from "../lib/api";
import { fmtDate } from "../lib/format";

export function Sidebar({
  jobs,
  selected,
  onSelect,
}: {
  jobs: Job[];
  selected: string | null;
  onSelect: (id: string | null) => void;
}) {
  return (
    <aside className="hidden w-72 shrink-0 flex-col border-r border-zinc-200 bg-white md:flex dark:border-zinc-800 dark:bg-zinc-900">
      <div className="flex items-center gap-2 px-5 pt-5 pb-4">
        <div className="grid size-8 place-items-center rounded-lg bg-accent-500 text-white">
          <AudioLines className="size-4.5" />
        </div>
        <div>
          <div className="text-[15px] font-semibold leading-tight">Songline</div>
          <div className="text-xs text-zinc-500">B 站歌单时间轴</div>
        </div>
      </div>

      <div className="px-3">
        <button
          onClick={() => onSelect(null)}
          className={clsx(
            "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition",
            selected === null
              ? "bg-accent-50 text-accent-600 dark:bg-accent-500/15 dark:text-accent-400"
              : "text-zinc-600 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800",
          )}
        >
          <Plus className="size-4" /> 新建识别
        </button>
      </div>

      <div className="mt-4 px-5 pb-2 text-xs font-medium text-zinc-400">历史记录</div>
      <nav className="min-h-0 flex-1 space-y-0.5 overflow-y-auto px-3 pb-4 scroll-thin">
        {jobs.length === 0 && <div className="px-3 py-2 text-sm text-zinc-400">还没有记录</div>}
        {jobs.map((j) => (
          <button
            key={j.id}
            onClick={() => onSelect(j.id)}
            className={clsx(
              "group flex w-full gap-3 rounded-lg p-2 text-left transition",
              selected === j.id ? "bg-zinc-100 dark:bg-zinc-800" : "hover:bg-zinc-50 dark:hover:bg-zinc-800/60",
            )}
          >
            <div className="relative h-11 w-[4.5rem] shrink-0 overflow-hidden rounded-md bg-zinc-200 dark:bg-zinc-800">
              {j.video && <img src={`${j.video.cover}@160w_100h_1c.webp`} alt="" className="size-full object-cover" />}
              {!isFinished(j) && (
                <div className="absolute inset-x-0 bottom-0 h-1 bg-black/30">
                  <div className="h-full bg-accent-500 transition-all" style={{ width: `${j.progress * 100}%` }} />
                </div>
              )}
            </div>
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-medium leading-snug">{j.video?.title ?? j.url}</div>
              <div className="mt-0.5 flex items-center gap-1 text-xs text-zinc-500">
                {j.stage === "done" ? (
                  <span>{j.timeline.length} 首 · {fmtDate(j.created_at)}</span>
                ) : j.stage === "failed" ? (
                  <span className="flex items-center gap-1 text-red-500">
                    <TriangleAlert className="size-3" /> 失败
                  </span>
                ) : j.stage === "cancelled" ? (
                  <span>已取消</span>
                ) : (
                  <span className="flex items-center gap-1 text-accent-600 dark:text-accent-400">
                    <LoaderCircle className="size-3 animate-spin" /> {Math.round(j.progress * 100)}%
                  </span>
                )}
              </div>
            </div>
          </button>
        ))}
      </nav>
    </aside>
  );
}
