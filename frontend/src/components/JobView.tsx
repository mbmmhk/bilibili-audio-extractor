import { Check, ChevronLeft, Copy, Download, ExternalLink, FileText, RotateCw, Square, Trash2, TriangleAlert } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { api, isFinished, type Job } from "../lib/api";
import { biliLink, download, fmtDate, fmtTime, timelineText } from "../lib/format";
import { Player, type PlayerHandle } from "./Player";
import { ProgressPanel } from "./ProgressPanel";
import { SongList, TimelineStrip } from "./Timeline";
import { Transcript } from "./Transcript";

export function JobView({
  job,
  onUpdate,
  onDeleted,
  onRerun,
}: {
  job: Job;
  onUpdate: (j: Job) => void;
  onDeleted: () => void;
  onRerun: () => void;
}) {
  const finished = isFinished(job);
  const player = useRef<PlayerHandle>(null);
  const [time, setTime] = useState(0);
  const [showTranscript, setShowTranscript] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (finished) return;
    return api.watch(job.id, onUpdate);
  }, [job.id, finished, onUpdate]);

  const v = job.video;
  const duration = v?.duration ?? 0;
  const hasAudio = !!v && job.stage !== "resolving" && job.stage !== "downloading" && job.stage !== "queued";

  async function copy() {
    await navigator.clipboard.writeText(timelineText(job));
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <div className="mx-auto max-w-4xl px-5 pt-8 pb-32">
      <a href="#" className="mb-4 inline-flex items-center gap-1 text-sm text-zinc-500 md:hidden">
        <ChevronLeft className="size-4" /> 新建识别 / 历史
      </a>
      {/* Header */}
      <div className="flex gap-5">
        <a
          href={biliLink(job)}
          target="_blank"
          rel="noreferrer"
          className="relative hidden aspect-video w-48 shrink-0 overflow-hidden rounded-xl bg-zinc-200 sm:block dark:bg-zinc-800"
        >
          {v && <img src={`${v.cover}@480w_270h_1c.webp`} alt="" className="size-full object-cover" />}
          {v && (
            <span className="tabular absolute right-1.5 bottom-1.5 rounded bg-black/70 px-1.5 py-0.5 text-[11px] text-white">
              {fmtTime(v.duration)}
            </span>
          )}
        </a>
        <div className="min-w-0 flex-1">
          <h1 className="text-xl leading-snug font-semibold">{v?.title ?? "解析中…"}</h1>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-zinc-500">
            {v && <span>UP：{v.owner}</span>}
            {v && v.pages.length > 1 && <span>P{v.page} / {v.pages.length}</span>}
            <span>{fmtDate(job.created_at)}</span>
            <a href={biliLink(job)} target="_blank" rel="noreferrer" className="flex items-center gap-1 hover:text-accent-600">
              {v?.bvid ?? job.url} <ExternalLink className="size-3.5" />
            </a>
          </div>
          <div className="mt-4 flex flex-wrap gap-2">
            {job.timeline.length > 0 && (
              <>
                <Btn onClick={copy} primary>
                  {copied ? <Check className="size-4" /> : <Copy className="size-4" />}
                  {copied ? "已复制" : "复制时间轴"}
                </Btn>
                <Btn
                  onClick={() =>
                    download(`${v?.bvid ?? job.id}.json`, JSON.stringify({ video: v, timeline: job.timeline }, null, 2))
                  }
                >
                  <Download className="size-4" /> JSON
                </Btn>
              </>
            )}
            {finished && job.stage === "done" && (
              <Btn onClick={() => setShowTranscript((s) => !s)}>
                <FileText className="size-4" /> {showTranscript ? "隐藏转写" : "查看转写"}
              </Btn>
            )}
            {!finished && (
              <Btn onClick={() => api.cancel(job.id).then(onUpdate)}>
                <Square className="size-3.5" /> 取消
              </Btn>
            )}
            {finished && (
              <Btn onClick={onRerun}>
                <RotateCw className="size-4" /> 重新识别
              </Btn>
            )}
            <Btn
              onClick={async () => {
                if (confirm("删除这条记录？")) {
                  await api.remove(job.id);
                  onDeleted();
                }
              }}
              danger
            >
              <Trash2 className="size-4" />
            </Btn>
          </div>
        </div>
      </div>

      {!finished && <ProgressPanel job={job} />}

      {job.stage === "failed" && (
        <div className="mt-6 flex gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-500/10 dark:text-red-300">
          <TriangleAlert className="mt-0.5 size-4 shrink-0" />
          <div>
            <div className="font-medium">识别失败</div>
            <div className="mt-1 opacity-80">{job.error}</div>
          </div>
        </div>
      )}

      {duration > 0 && (job.timeline.length > 0 || hasAudio) && (
        <TimelineStrip
          entries={job.timeline}
          duration={duration}
          time={time}
          onSeek={(t) => player.current?.playAt(t)}
        />
      )}

      {job.timeline.length > 0 ? (
        <SongList
          job={job}
          time={time}
          canPlay={hasAudio}
          onPlay={(t) => player.current?.playAt(t)}
          live={!finished}
        />
      ) : (
        job.stage === "done" && (
          <div className="mt-8 rounded-xl border border-dashed border-zinc-300 p-10 text-center text-zinc-500 dark:border-zinc-700">
            没有识别到歌曲。可能是纯音乐、伴奏声太大，或者歌曲不在曲库里。
          </div>
        )
      )}

      {showTranscript && <Transcript jobId={job.id} time={time} onSeek={(t) => player.current?.playAt(t)} />}

      {hasAudio && (
        <Player ref={player} src={api.audioUrl(job.id)} entries={job.timeline} duration={duration} onTime={setTime} />
      )}
    </div>
  );
}

function Btn({
  children,
  onClick,
  primary,
  danger,
}: {
  children: React.ReactNode;
  onClick: () => void;
  primary?: boolean;
  danger?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={
        primary
          ? "flex items-center gap-1.5 rounded-lg bg-accent-500 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-accent-600"
          : danger
            ? "flex items-center gap-1.5 rounded-lg border border-zinc-200 px-2.5 py-1.5 text-sm text-zinc-500 transition hover:border-red-300 hover:text-red-600 dark:border-zinc-800"
            : "flex items-center gap-1.5 rounded-lg border border-zinc-200 px-3 py-1.5 text-sm text-zinc-700 transition hover:bg-zinc-100 dark:border-zinc-800 dark:text-zinc-300 dark:hover:bg-zinc-800"
      }
    >
      {children}
    </button>
  );
}
