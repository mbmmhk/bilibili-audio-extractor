import clsx from "clsx";
import { ArrowRight, AudioLines, Bookmark, Fingerprint, LoaderCircle } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { api, type Job } from "../lib/api";

/** Pull a link or BV id out of whatever was pasted (share text often wraps it). */
function extractLink(text: string): string {
  const url = text.match(/https?:\/\/[^\s，。]+/)?.[0];
  if (url) return url;
  return text.match(/BV[0-9A-Za-z]{10}/)?.[0] ?? text.trim();
}

export function NewJob({
  initialText = "",
  recent,
  onCreated,
  onOpen,
}: {
  initialText?: string;
  recent: Job[];
  onCreated: (j: Job) => void;
  onOpen: (id: string) => void;
}) {
  const [text, setText] = useState(initialText);
  const [shazam, setShazam] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const link = extractLink(text);
  const bv = link.match(/BV[0-9A-Za-z]{10}/)?.[0];
  const existing = bv ? recent.find((j) => j.video?.bvid === bv && j.stage === "done") : undefined;

  async function submit(e?: React.FormEvent) {
    e?.preventDefault();
    if (!link || busy) return;
    setBusy(true);
    setError(null);
    try {
      onCreated(await api.create(link, shazam));
      setText("");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto flex min-h-full max-w-2xl flex-col justify-center px-5 py-16">
      <div className="mb-8 flex items-center gap-3 md:hidden">
        <div className="grid size-9 place-items-center rounded-lg bg-accent-500 text-white">
          <AudioLines className="size-5" />
        </div>
        <div className="text-lg font-semibold">Songline</div>
      </div>
      <h1 className="text-3xl font-semibold tracking-tight">这个视频里唱了哪些歌？</h1>
      <p className="mt-2 text-zinc-500">
        粘贴 B 站视频链接，自动听歌词、查歌名，生成带时间点的歌单。翻唱、弹唱、直播回放都可以。
      </p>

      <form onSubmit={submit} className="mt-8">
        <div className="flex items-stretch gap-2 rounded-xl border border-zinc-200 bg-white p-1.5 shadow-sm transition focus-within:border-accent-400 focus-within:ring-4 focus-within:ring-accent-500/10 dark:border-zinc-800 dark:bg-zinc-900">
          <input
            autoFocus
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="https://www.bilibili.com/video/BV…  或 b23.tv 短链 / 分享文本"
            className="min-w-0 flex-1 bg-transparent px-3 text-[15px] outline-none placeholder:text-zinc-400"
          />
          <button
            type="submit"
            disabled={!text.trim() || busy}
            className="flex items-center gap-1.5 rounded-lg bg-accent-500 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-accent-600 disabled:cursor-not-allowed disabled:opacity-40"
          >
            {busy ? <LoaderCircle className="size-4 animate-spin" /> : <ArrowRight className="size-4" />}
            开始识别
          </button>
        </div>

        <label className="mt-3 flex w-fit cursor-pointer items-center gap-2 text-sm text-zinc-600 select-none dark:text-zinc-400">
          <button
            type="button"
            role="switch"
            aria-checked={shazam}
            onClick={() => setShazam((v) => !v)}
            className={clsx(
              "relative h-5 w-9 rounded-full transition",
              shazam ? "bg-accent-500" : "bg-zinc-300 dark:bg-zinc-700",
            )}
          >
            <span
              className={clsx(
                "absolute top-0.5 size-4 rounded-full bg-white shadow transition-all",
                shazam ? "left-[18px]" : "left-0.5",
              )}
            />
          </button>
          <Fingerprint className="size-4" />
          音频指纹交叉核对
          <span className="text-zinc-400">（更准，多花几分钟）</span>
        </label>

        {error && <div className="mt-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-600 dark:bg-red-500/10 dark:text-red-400">{error}</div>}
        {existing && (
          <div className="mt-4 rounded-lg bg-zinc-100 px-4 py-3 text-sm dark:bg-zinc-900">
            这个视频识别过了：
            <button type="button" onClick={() => onOpen(existing.id)} className="font-medium text-accent-600 hover:underline dark:text-accent-400">
              查看结果
            </button>
          </div>
        )}
      </form>

      {recent.length > 0 && (
        <div className="mt-10 md:hidden">
          <div className="mb-2 text-xs font-medium text-zinc-400">历史记录</div>
          <div className="divide-y divide-zinc-100 rounded-xl border border-zinc-200 dark:divide-zinc-800 dark:border-zinc-800">
            {recent.slice(0, 8).map((j) => (
              <button key={j.id} onClick={() => onOpen(j.id)} className="flex w-full justify-between gap-3 px-4 py-3 text-left text-sm">
                <span className="truncate">{j.video?.title ?? j.url}</span>
                <span className="shrink-0 text-zinc-400">{j.stage === "done" ? `${j.timeline.length} 首` : `${Math.round(j.progress * 100)}%`}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      <SendBookmark />

      <div className="mt-12 grid gap-4 text-sm sm:grid-cols-3">
        {[
          ["听", "本地语音识别转写歌词，1 小时音频约 2 分钟"],
          ["查", "用歌词搜索曲库，区分唱歌和聊天"],
          ["核", "音频指纹 + 主播口播交叉验证"],
        ].map(([k, v]) => (
          <div key={k} className="rounded-xl border border-zinc-200 p-4 dark:border-zinc-800">
            <div className="font-semibold text-accent-600 dark:text-accent-400">{k}</div>
            <div className="mt-1 text-zinc-500">{v}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

/** Bookmarklet for the browser's bookmarks bar: on a Bilibili video page it
 * opens Songline in a new tab and starts recognising that video. */
function SendBookmark() {
  const link = useRef<HTMLAnchorElement>(null);
  useEffect(() => {
    const target = `${location.origin}/#/add?url=`;
    // React refuses javascript: URLs in JSX, so set it on the element directly.
    link.current?.setAttribute(
      "href",
      `javascript:void(window.open(${JSON.stringify(target)}+encodeURIComponent(location.href),'_blank'))`,
    );
  }, []);
  return (
    <div className="mt-10 hidden rounded-xl border border-dashed border-zinc-300 p-4 text-sm text-zinc-500 md:block dark:border-zinc-700">
      <div className="flex flex-wrap items-center gap-3">
        <span>在 B 站一键识别：把这个按钮拖到浏览器的书签栏</span>
        <a
          ref={link}
          onClick={(e) => e.preventDefault()}
          title="拖到书签栏，不要点击"
          className="flex cursor-grab items-center gap-1.5 rounded-lg bg-accent-500 px-3 py-1.5 font-medium text-white active:cursor-grabbing"
        >
          <Bookmark className="size-4" /> 发送到 Songline
        </a>
      </div>
      <div className="mt-2 text-xs text-zinc-400">
        之后在 B 站看视频时点一下这个书签，就会在新标签页打开 Songline 并开始识别；识别过的视频会直接打开结果。Songline 需要开着。
      </div>
    </div>
  );
}
