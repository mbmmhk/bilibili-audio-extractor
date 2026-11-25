import clsx from "clsx";
import { ChevronDown, ExternalLink, Fingerprint, Mic, Music2, Play, Quote } from "lucide-react";
import { useState } from "react";
import type { Job, TimelineEntry } from "../lib/api";
import { biliLink, fmtTime, level, levelLabel, sourceLabel, type Level } from "../lib/format";

const levelStyle: Record<Level, string> = {
  high: "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-400",
  mid: "bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-400",
  low: "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400",
};

const barStyle: Record<Level, string> = {
  high: "bg-accent-500",
  mid: "bg-accent-400/70",
  low: "bg-zinc-400/60",
};

const sourceIcon = { lyrics: Music2, shazam: Fingerprint, spoken: Mic };

export function TimelineStrip({
  entries,
  duration,
  time,
  onSeek,
}: {
  entries: TimelineEntry[];
  duration: number;
  time: number;
  onSeek: (t: number) => void;
}) {
  return (
    <div className="mt-8">
      <div
        className="relative h-8 cursor-pointer overflow-hidden rounded-lg bg-zinc-100 dark:bg-zinc-900"
        onClick={(e) => {
          const r = e.currentTarget.getBoundingClientRect();
          onSeek(((e.clientX - r.left) / r.width) * duration);
        }}
      >
        {entries.map((e, i) => (
          <div
            key={i}
            title={`${fmtTime(e.start)} ${e.song?.title ?? "未识别"}`}
            className={clsx("absolute inset-y-1 rounded-sm transition hover:brightness-110", barStyle[level(e)])}
            style={{
              left: `${(e.start / duration) * 100}%`,
              width: `max(3px, ${((e.end - e.start) / duration) * 100}%)`,
            }}
          />
        ))}
        {time > 0 && (
          <div className="absolute inset-y-0 w-0.5 bg-zinc-900 dark:bg-white" style={{ left: `${(time / duration) * 100}%` }} />
        )}
      </div>
      <div className="tabular mt-1 flex justify-between text-[11px] text-zinc-400">
        <span>0:00</span>
        <span>{fmtTime(duration / 2)}</span>
        <span>{fmtTime(duration)}</span>
      </div>
    </div>
  );
}

export function SongList({
  job,
  time,
  canPlay,
  onPlay,
  live,
}: {
  job: Job;
  time: number;
  canPlay: boolean;
  onPlay: (t: number) => void;
  live: boolean;
}) {
  const long = (job.video?.duration ?? 0) >= 3600;
  const counts = { high: 0, mid: 0, low: 0 };
  job.timeline.forEach((e) => counts[level(e)]++);

  return (
    <section className="mt-6">
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-base font-semibold">
          {live ? "已识别" : "歌单"} <span className="font-normal text-zinc-400">{job.timeline.length} 首</span>
        </h2>
        <div className="flex gap-3 text-xs text-zinc-500">
          {(Object.keys(counts) as Level[]).map((l) =>
            counts[l] ? (
              <span key={l} className="flex items-center gap-1">
                <span className={clsx("size-2 rounded-full", barStyle[l])} />
                {levelLabel[l]} {counts[l]}
              </span>
            ) : null,
          )}
        </div>
      </div>
      <ol className="divide-y divide-zinc-100 overflow-hidden rounded-xl border border-zinc-200 bg-white dark:divide-zinc-800 dark:border-zinc-800 dark:bg-zinc-900">
        {job.timeline.map((e, i) => (
          <Row
            key={`${e.start}-${i}`}
            index={i + 1}
            entry={e}
            long={long}
            active={time >= e.start && time <= e.end}
            canPlay={canPlay}
            onPlay={onPlay}
            jumpUrl={biliLink(job, e.start)}
          />
        ))}
      </ol>
    </section>
  );
}

function Row({
  index,
  entry: e,
  long,
  active,
  canPlay,
  onPlay,
  jumpUrl,
}: {
  index: number;
  entry: TimelineEntry;
  long: boolean;
  active: boolean;
  canPlay: boolean;
  onPlay: (t: number) => void;
  jumpUrl: string;
}) {
  const [open, setOpen] = useState(false);
  const lv = level(e);
  return (
    <li className={clsx("transition", active && "bg-accent-50/70 dark:bg-accent-500/10")}>
      <div className="flex items-center gap-3 px-4 py-3">
        <button
          disabled={!canPlay}
          onClick={() => onPlay(e.start)}
          title="从这里播放"
          className="group relative grid size-8 shrink-0 place-items-center rounded-full text-xs text-zinc-400 transition enabled:hover:bg-accent-500 enabled:hover:text-white"
        >
          <span className={clsx("tabular", canPlay && "group-hover:hidden", active && "text-accent-600")}>{index}</span>
          {canPlay && <Play className="absolute hidden size-3.5 fill-current group-hover:block" />}
        </button>

        <button onClick={() => onPlay(e.start)} disabled={!canPlay} className="tabular hidden w-[7.5rem] shrink-0 text-left text-sm text-zinc-500 enabled:hover:text-accent-600 sm:block">
          {fmtTime(e.start, long)}
          <span className="text-zinc-300 dark:text-zinc-600"> – </span>
          {fmtTime(e.end, long)}
        </button>

        <button
          type="button"
          className="min-w-0 flex-1 text-left enabled:cursor-pointer enabled:hover:text-accent-600"
          disabled={!canPlay}
          onClick={() => onPlay(e.start)}
        >
          <div className="truncate font-medium">{e.song?.title ?? "未识别"}</div>
          <div className="truncate text-sm text-zinc-500">
            <span className="tabular sm:hidden">{fmtTime(e.start, long)} · </span>
            {e.song?.artist}
          </div>
        </button>

        <div className="hidden items-center gap-1 sm:flex">
          {e.sources.map((s) => {
            const Icon = sourceIcon[s];
            return (
              <span key={s} title={sourceLabel[s]} className="flex items-center gap-1 rounded-md bg-zinc-100 px-1.5 py-0.5 text-[11px] text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400">
                <Icon className="size-3" /> {sourceLabel[s]}
              </span>
            );
          })}
        </div>
        <span className={clsx("shrink-0 rounded-md px-2 py-0.5 text-xs font-medium", levelStyle[lv])}>{levelLabel[lv]}</span>
        <a href={jumpUrl} target="_blank" rel="noreferrer" title="在 B 站打开到这个时间" className="text-zinc-400 hover:text-accent-600">
          <ExternalLink className="size-4" />
        </a>
        <button onClick={() => setOpen((o) => !o)} className="text-zinc-400 hover:text-zinc-700 dark:hover:text-zinc-200">
          <ChevronDown className={clsx("size-4 transition", open && "rotate-180")} />
        </button>
      </div>

      {open && (
        <div className="space-y-2 px-4 pb-4 pl-[3.75rem] text-sm">
          {e.evidence && (
            <div className="flex gap-2 text-zinc-600 dark:text-zinc-400">
              <Quote className="mt-0.5 size-3.5 shrink-0 text-zinc-400" />
              <span>听到的歌词：「{e.evidence}」</span>
            </div>
          )}
          <div className="text-zinc-500">
            可信度 {Math.round(e.confidence * 100)}% · 依据：{e.sources.map((s) => sourceLabel[s]).join(" + ")}
          </div>
          {e.alternatives.length > 0 && (
            <div className="text-zinc-500">
              也可能是：
              {e.alternatives.map((a, i) => (
                <span key={i} className="ml-1 rounded bg-zinc-100 px-1.5 py-0.5 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  {a.title} - {a.artist}
                </span>
              ))}
            </div>
          )}
          {e.song?.netease_id && (
            <a
              href={`https://music.163.com/#/song?id=${e.song.netease_id}`}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-accent-600 hover:underline dark:text-accent-400"
            >
              在网易云音乐查看 <ExternalLink className="size-3" />
            </a>
          )}
        </div>
      )}
    </li>
  );
}
