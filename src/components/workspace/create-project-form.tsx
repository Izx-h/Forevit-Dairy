"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/primitives";
import { Input, Textarea } from "@/components/ui/input";

export function CreateProjectForm() {
  const [open, setOpen] = useState(false);
  const [message, setMessage] = useState("");
  const [pending, setPending] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = Object.fromEntries(new FormData(form).entries());
    setPending(true); setMessage("");
    const response = await fetch("/api/v1/projects", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(values) });
    const result = await response.json().catch(() => ({}));
    setPending(false);
    if (!response.ok) { setMessage(result.error ?? "Project could not be created."); return; }
    form.reset(); setMessage("Project created."); window.location.reload();
  }
  return <div>
    <Button onClick={() => setOpen(!open)} aria-expanded={open} aria-controls="new-project"><Plus size={16} />New project</Button>
    {open && <Card id="new-project" className="mt-3 w-[min(92vw,420px)] p-5 shadow-soft sm:p-6"><h2 className="text-sm font-semibold text-ink">Create a project</h2><p className="mt-1 text-xs leading-5 text-muted">Project access remains limited to explicitly added members.</p><form onSubmit={submit} className="mt-4 space-y-4"><label className="block space-y-2"><span className="text-xs font-medium text-ink">Project name</span><Input name="name" required maxLength={120} /></label><label className="block space-y-2"><span className="text-xs font-medium text-ink">Description</span><Textarea name="description" maxLength={4000} /></label>{message && <p role="status" className="text-xs text-muted">{message}</p>}<div className="flex justify-end gap-2"><Button type="button" variant="ghost" onClick={() => setOpen(false)}>Cancel</Button><Button type="submit" disabled={pending}>{pending ? "Creating…" : "Create project"}</Button></div></form></Card>}
  </div>;
}
