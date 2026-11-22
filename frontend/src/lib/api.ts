export type Stage =
  | "queued"
  | "resolving"
  | "downloading"
  | "transcribing"
  | "matching"
  | "verifying"
  | "done"
  | "failed"
  | "cancelled";

export type Source = "lyrics" | "shazam" | "spoken";

export interface SongRef {
  title: string;
  artist: string;
  netease_id: number | null;
}

export interface TimelineEntry {
  start: number;
  end: number;
  song: SongRef | null;
  confidence: number;
  sources: Source[];
  evidence: string;
  alternatives: SongRef[];
}

export interface VideoInfo {
  bvid: string;
  aid: number;
  title: string;
  owner: string;
  cover: string;
  duration: number;
  page: number;
  pages: { page: number; cid: number; title: string; duration: number }[];
}

export interface Job {
  id: string;
  url: string;
  options: { shazam: boolean };
  stage: Stage;
  progress: number;
  message: string;
  error: string | null;
  video: VideoInfo | null;
  timeline: TimelineEntry[];
  created_at: number;
  updated_at: number;
}

export interface Segment {
  start: number;
  end: number;
  text: string;
}

export const isFinished = (j: Job) => j.stage === "done" || j.stage === "failed" || j.stage === "cancelled";

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const r = await fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  if (!r.ok) {
    let msg = `${r.status}`;
    try {
      msg = (await r.json()).detail ?? msg;
    } catch {
      /* not json */
    }
    throw new Error(msg);
  }
  return r.status === 204 ? (undefined as T) : r.json();
}

export const api = {
  list: () => req<Job[]>("/api/jobs"),
  get: (id: string) => req<Job>(`/api/jobs/${id}`),
  create: (url: string, shazam: boolean) =>
    req<Job>("/api/jobs", { method: "POST", body: JSON.stringify({ url, options: { shazam } }) }),
  cancel: (id: string) => req<Job>(`/api/jobs/${id}/cancel`, { method: "POST" }),
  remove: (id: string) => req<void>(`/api/jobs/${id}`, { method: "DELETE" }),
  transcript: (id: string) => req<Segment[]>(`/api/jobs/${id}/transcript`),
  audioUrl: (id: string) => `/api/jobs/${id}/audio`,
  /** Live updates; returns an unsubscribe function. */
  watch(id: string, onJob: (j: Job) => void): () => void {
    const es = new EventSource(`/api/jobs/${id}/events`);
    es.onmessage = (e) => {
      const job: Job = JSON.parse(e.data);
      onJob(job);
      if (isFinished(job)) es.close();
    };
    return () => es.close();
  },
};
