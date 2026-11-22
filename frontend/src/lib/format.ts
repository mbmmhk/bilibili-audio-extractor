import type { Job, TimelineEntry } from "./api";

export function fmtTime(sec: number, forceHours = false): string {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h > 0 || forceHours ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${String(m).padStart(2, "0")}:${ss}`;
}

export function fmtDate(ts: number): string {
  const d = new Date(ts * 1000);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const hm = d.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
  return sameDay ? `今天 ${hm}` : `${d.getMonth() + 1}月${d.getDate()}日 ${hm}`;
}

export type Level = "high" | "mid" | "low";

export function level(e: TimelineEntry): Level {
  if (e.confidence >= 0.75 || e.sources.length >= 2) return "high";
  if (e.confidence >= 0.45) return "mid";
  return "low";
}

export const levelLabel: Record<Level, string> = { high: "可靠", mid: "较可能", low: "待确认" };

export const sourceLabel = { lyrics: "歌词", shazam: "指纹", spoken: "口播" } as const;

export function biliLink(job: Job, t?: number): string {
  const v = job.video;
  if (!v) return job.url;
  const params = new URLSearchParams();
  if (v.page > 1) params.set("p", String(v.page));
  if (t !== undefined) params.set("t", String(Math.floor(t)));
  const q = params.toString();
  return `https://www.bilibili.com/video/${v.bvid}${q ? `?${q}` : ""}`;
}

/** The format people post in Bilibili comments, e.g. `01:02:03 歌名 - 歌手`. */
export function timelineText(job: Job): string {
  const long = (job.video?.duration ?? 0) >= 3600;
  return job.timeline
    .map((e) => `${fmtTime(e.start, long)} ${e.song ? `${e.song.title} - ${e.song.artist}` : "未识别"}`)
    .join("\n");
}

export function download(filename: string, content: string, type = "application/json") {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const a = Object.assign(document.createElement("a"), { href: url, download: filename });
  a.click();
  URL.revokeObjectURL(url);
}
