import { Pause, Play, SkipBack, SkipForward } from "lucide-react";
import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import type { TimelineEntry } from "../lib/api";
import { fmtTime } from "../lib/format";

export interface PlayerHandle {
  playAt: (t: number) => void;
}

export const Player = forwardRef<
  PlayerHandle,
  { src: string; entries: TimelineEntry[]; duration: number; onTime: (t: number) => void }
>(function Player({ src, entries, duration, onTime }, ref) {
  const audio = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [t, setT] = useState(0);
  const [started, setStarted] = useState(false);

  useImperativeHandle(ref, () => ({
    playAt(sec) {
      const a = audio.current;
      if (!a) return;
      a.currentTime = Math.max(0, sec);
      setStarted(true);
      void a.play();
    },
  }));

  useEffect(() => {
    const a = audio.current;
    if (!a) return;
    const tick = () => {
      setT(a.currentTime);
      onTime(a.currentTime);
    };
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    a.addEventListener("timeupdate", tick);
    a.addEventListener("play", onPlay);
    a.addEventListener("pause", onPause);
    return () => {
      a.removeEventListener("timeupdate", tick);
      a.removeEventListener("play", onPlay);
      a.removeEventListener("pause", onPause);
    };
  }, [onTime]);

  const current = entries.find((e) => t >= e.start && t <= e.end);
  const idx = current ? entries.indexOf(current) : -1;
  const next = entries.find((e) => e.start > t + 1);
  const prev = [...entries].reverse().find((e) => e.start < t - 3);

  const seek = (sec: number) => {
    const a = audio.current;
    if (!a) return;
    a.currentTime = sec;
    setStarted(true);
    void a.play();
  };

  return (
    <>
      <audio ref={audio} src={src} preload="none" />
      <div
        className={`fixed right-0 bottom-0 left-0 z-10 border-t border-zinc-200 bg-white/90 backdrop-blur transition-transform md:left-72 dark:border-zinc-800 dark:bg-zinc-900/90 ${
          started ? "translate-y-0" : "translate-y-full"
        }`}
      >
        <div className="mx-auto flex max-w-4xl items-center gap-4 px-5 py-3">
          <div className="flex items-center gap-1">
            <IconBtn disabled={!prev && !current} onClick={() => seek((prev ?? current)!.start)} label="上一首">
              <SkipBack className="size-4" />
            </IconBtn>
            <button
              onClick={() => (playing ? audio.current?.pause() : audio.current?.play())}
              className="grid size-9 place-items-center rounded-full bg-accent-500 text-white transition hover:bg-accent-600"
              aria-label={playing ? "暂停" : "播放"}
            >
              {playing ? <Pause className="size-4 fill-current" /> : <Play className="size-4 translate-x-px fill-current" />}
            </button>
            <IconBtn disabled={!next} onClick={() => next && seek(next.start)} label="下一首">
              <SkipForward className="size-4" />
            </IconBtn>
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-medium">
              {current?.song ? `${idx + 1}. ${current.song.title}` : "—"}
              {current?.song && <span className="font-normal text-zinc-500"> · {current.song.artist}</span>}
            </div>
            <input
              type="range"
              min={0}
              max={duration || 1}
              step={1}
              value={t}
              onChange={(e) => {
                if (audio.current) audio.current.currentTime = Number(e.target.value);
              }}
              className="mt-1 h-1 w-full cursor-pointer accent-accent-500"
            />
          </div>
          <div className="tabular shrink-0 text-xs text-zinc-500">
            {fmtTime(t)} / {fmtTime(duration)}
          </div>
        </div>
      </div>
    </>
  );
});

function IconBtn({
  children,
  onClick,
  disabled,
  label,
}: {
  children: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
  label: string;
}) {
  return (
    <button
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="grid size-8 place-items-center rounded-full text-zinc-600 transition hover:bg-zinc-100 disabled:opacity-30 dark:text-zinc-300 dark:hover:bg-zinc-800"
    >
      {children}
    </button>
  );
}
