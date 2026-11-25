import { useCallback, useEffect, useRef, useState } from "react";
import { JobView } from "./components/JobView";
import { NewJob } from "./components/NewJob";
import { Sidebar } from "./components/Sidebar";
import { api, isFinished, type Job } from "./lib/api";

function useHashRoute(): [string | null, (id: string | null) => void] {
  const read = () => location.hash.match(/^#\/job\/(\w+)/)?.[1] ?? null;
  const [id, setId] = useState(read);
  useEffect(() => {
    const on = () => setId(read());
    addEventListener("hashchange", on);
    return () => removeEventListener("hashchange", on);
  }, []);
  const go = useCallback((next: string | null) => {
    location.hash = next ? `#/job/${next}` : "";
  }, []);
  return [id, go];
}

function sameVideo(url: string, bvid: string, page: number): boolean {
  if (!url.includes(bvid)) return false;
  const p = Number(url.match(/[?&]p=(\d+)/)?.[1] ?? 1);
  return p === page;
}

export default function App() {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [selected, select] = useHashRoute();

  const refresh = useCallback(async () => {
    try {
      setJobs(await api.list());
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  // Keep the history list fresh while anything is running.
  const busy = jobs.some((j) => !isFinished(j));
  useEffect(() => {
    if (!busy) return;
    const t = setInterval(refresh, 3000);
    return () => clearInterval(t);
  }, [busy, refresh]);

  const upsert = useCallback((job: Job) => {
    setJobs((prev) => {
      const i = prev.findIndex((j) => j.id === job.id);
      if (i === -1) return [job, ...prev];
      const next = prev.slice();
      next[i] = job;
      return next;
    });
  }, []);

  // "发送到 Songline" bookmark on a Bilibili page opens #/add?url=<that page>:
  // open the result if this video was already done, else start recognising it.
  const [prefill, setPrefill] = useState("");
  const adding = useRef(false);
  useEffect(() => {
    const m = location.hash.match(/^#\/add\?(.*)$/);
    if (!loaded || !m || adding.current) return;
    adding.current = true;
    const url = new URLSearchParams(m[1]).get("url") ?? "";
    const done = jobs.find((j) => j.stage === "done" && j.video && sameVideo(url, j.video.bvid, j.video.page));
    if (done) {
      select(done.id);
      return;
    }
    api
      .create(url, true)
      .then((j) => {
        upsert(j);
        select(j.id);
      })
      .catch(() => {
        setPrefill(url); // let the user retry from the form
        select(null);
      });
  }, [loaded, jobs, select, upsert]);

  const current = jobs.find((j) => j.id === selected) ?? null;

  return (
    <div className="flex h-full">
      <Sidebar jobs={jobs} selected={selected} onSelect={select} />
      <main className="min-w-0 flex-1 overflow-y-auto scroll-thin">
        {selected && current ? (
          <JobView
            key={current.id}
            job={current}
            onUpdate={upsert}
            onDeleted={() => {
              setJobs((p) => p.filter((j) => j.id !== current.id));
              select(null);
            }}
            onRerun={async () => {
              const j = await api.create(current.url, current.options.shazam);
              upsert(j);
              select(j.id);
            }}
          />
        ) : selected && loaded ? (
          <div className="p-10 text-zinc-500">找不到这个任务，可能已被删除。</div>
        ) : (
          <NewJob
            key={prefill}
            initialText={prefill}
            recent={jobs}
            onCreated={(j) => {
              upsert(j);
              select(j.id);
            }}
            onOpen={select}
          />
        )}
      </main>
    </div>
  );
}
