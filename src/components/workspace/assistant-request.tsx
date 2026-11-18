"use client";

import { useState } from "react";
import { Loader2, Send, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/primitives";
import { Textarea } from "@/components/ui/input";

export function AssistantRequest({ projectId }: { projectId?: string }) {
  const [question, setQuestion] = useState("");
  const [pending, setPending] = useState(false);
  const [status, setStatus] = useState<{ jobId?: string; message: string; error?: boolean } | null>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!projectId || !question.trim()) return;
    setPending(true); setStatus(null);
    const response = await fetch("/api/v1/ai/chat", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ project_id: projectId, question: question.trim() }) });
    const result = await response.json().catch(() => ({}));
    setPending(false);
    if (!response.ok) { setStatus({ message: result.error ?? "The request could not be queued.", error: true }); return; }
    setStatus({ jobId: result.id, message: "Request queued. Results will be available after the authorized worker completes evidence retrieval and review." });
    setQuestion("");
  }

  return <Card className="p-5 sm:p-7"><div className="flex items-start gap-3"><span className="grid h-10 w-10 place-items-center rounded-xl bg-pine-50 text-pine-700"><Sparkles size={19} /></span><div><h2 className="text-sm font-semibold text-ink">Ask across authorized project knowledge</h2><p className="mt-1 text-xs leading-5 text-muted">The assistant should cite source versions and page/section locations. It may abstain when evidence is insufficient.</p></div></div><form onSubmit={submit} className="mt-5 space-y-3"><label htmlFor="assistant-question" className="sr-only">Question</label><Textarea id="assistant-question" value={question} onChange={(event) => setQuestion(event.target.value)} maxLength={6000} placeholder="Ask about accessible documents or compare recorded work…" className="min-h-36" /><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><p className="max-w-lg text-[11px] leading-5 text-muted">AI output is an aid for research and coordination, not source data or validated food-safety guidance.</p><Button type="submit" disabled={pending || !projectId || !question.trim()}>{pending ? <Loader2 size={15} className="animate-spin" /> : <Send size={15} />}{pending ? "Queuing…" : "Submit for analysis"}</Button></div></form>{status && <div role="status" className={`mt-4 rounded-xl border px-4 py-3 text-xs leading-5 ${status.error ? "border-rose-100 bg-rose-50 text-rose-700" : "border-pine-100 bg-pine-50 text-pine-800"}`}>{status.message}{status.jobId && <span className="mt-1 block font-mono text-[10px]">Job: {status.jobId}</span>}</div>}</Card>;
}
