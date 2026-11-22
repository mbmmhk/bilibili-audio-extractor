import clsx from "clsx";
import { useEffect, useState } from "react";
import { api, type Segment } from "../lib/api";
import { fmtTime } from "../lib/format";

/** Raw Whisper transcript, for checking a result by eye. */
export function Transcript({ jobId, time, onSeek }: { jobId: string; time: number; onSeek: (t: number) => void }) {
  const [segs, setSegs] = useState<Segment[] | null>(null);
  const [q, setQ] = useState("");

  useEffect(() => {
    api.transcript(jobId).then(setSegs);
  }, [jobId]);

  const shown = segs?.filter((s) => !q || s.text.includes(q)) ?? [];

  return (
    <section className="mt-8">
      <div className="mb-3 flex items-center justify-between gap-4">
        <h2 className="text-base font-semibold">
          语音转写 <span className="font-normal text-zinc-400">{segs?.length ?? "…"} 句</span>
        </h2>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="搜索转写内容"
          className="w-48 rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-sm outline-none focus:border-accent-400 dark:border-zinc-800 dark:bg-zinc-900"
        />
      </div>
      <div className="max-h-[28rem] overflow-y-auto rounded-xl border border-zinc-200 bg-white p-2 text-sm scroll-thin dark:border-zinc-800 dark:bg-zinc-900">
        {shown.map((s, i) => (
          <button
            key={i}
            onClick={() => onSeek(s.start)}
            className={clsx(
              "flex w-full gap-3 rounded-md px-2 py-1 text-left hover:bg-zinc-50 dark:hover:bg-zinc-800",
              time >= s.start && time < s.end && "bg-accent-50 dark:bg-accent-500/10",
            )}
          >
            <span className="tabular w-16 shrink-0 text-zinc-400">{fmtTime(s.start)}</span>
            <span>{s.text}</span>
          </button>
        ))}
        {segs && shown.length === 0 && <div className="p-4 text-center text-zinc-400">没有内容</div>}
      </div>
    </section>
  );
}
