import clsx from "clsx";
import { Check, LoaderCircle } from "lucide-react";
import type { Job, Stage } from "../lib/api";

const STEPS: { stage: Stage; label: string }[] = [
  { stage: "resolving", label: "解析链接" },
  { stage: "downloading", label: "下载音频" },
  { stage: "transcribing", label: "转写歌词" },
  { stage: "matching", label: "匹配歌曲" },
  { stage: "verifying", label: "指纹核对" },
];

export function ProgressPanel({ job }: { job: Job }) {
  const steps = job.options.shazam ? STEPS : STEPS.slice(0, 4);
  const idx = job.stage === "queued" ? -1 : steps.findIndex((s) => s.stage === job.stage);

  return (
    <div className="mt-6 rounded-xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-900">
      <div className="flex items-center justify-between text-sm">
        <span className="font-medium">{job.message || "处理中…"}</span>
        <span className="tabular text-zinc-500">{Math.round(job.progress * 100)}%</span>
      </div>
      <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-zinc-100 dark:bg-zinc-800">
        <div className="h-full rounded-full bg-accent-500 transition-all duration-500" style={{ width: `${job.progress * 100}%` }} />
      </div>
      <ol className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-xs">
        {steps.map((s, i) => (
          <li
            key={s.stage}
            className={clsx(
              "flex items-center gap-1.5",
              i < idx ? "text-zinc-500" : i === idx ? "font-medium text-accent-600 dark:text-accent-400" : "text-zinc-400",
            )}
          >
            {i < idx ? (
              <Check className="size-3.5" />
            ) : i === idx ? (
              <LoaderCircle className="size-3.5 animate-spin" />
            ) : (
              <span className="grid size-3.5 place-items-center rounded-full border border-current text-[9px]">{i + 1}</span>
            )}
            {s.label}
          </li>
        ))}
      </ol>
      {job.stage === "transcribing" && job.timeline.length > 0 && (
        <p className="mt-3 text-xs text-zinc-500">已识别的歌会先显示在下方，转写完后会再整体校正一遍。</p>
      )}
    </div>
  );
}
