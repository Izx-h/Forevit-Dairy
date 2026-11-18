"use client";

import { useState } from "react";
import { Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, FieldLabel } from "@/components/ui/primitives";
import { Input, Textarea } from "@/components/ui/input";

export type CreateKind = "task" | "sample" | "lab-test" | "document" | "formulation" | "meeting";

const config: Record<CreateKind, { title: string; endpoint: string; fields: { name: string; label: string; kind?: "textarea" | "date" | "select"; options?: string[]; required?: boolean }[] }> = {
  task: { title: "New task", endpoint: "tasks", fields: [{ name: "title", label: "Task title", required: true }, { name: "description", label: "Description", kind: "textarea" }, { name: "priority", label: "Priority", kind: "select", options: ["low", "normal", "high", "urgent"] }, { name: "due_at", label: "Due date", kind: "date" }] },
  sample: { title: "Register sample", endpoint: "lab/samples", fields: [{ name: "sample_code", label: "Sample code", required: true }, { name: "sample_type", label: "Sample type", required: true }, { name: "source_description", label: "Source / provenance", kind: "textarea" }, { name: "collected_at", label: "Collected on", kind: "date" }, { name: "storage_conditions", label: "Storage conditions", kind: "textarea" }] },
  "lab-test": { title: "Plan a test", endpoint: "lab/tests", fields: [{ name: "test_name", label: "Test name", required: true }, { name: "objective", label: "Objective", kind: "textarea" }, { name: "sample_id", label: "Sample ID", required: true }, { name: "planned_at", label: "Planned for", kind: "date" }] },
  document: { title: "Add document", endpoint: "documents", fields: [{ name: "title", label: "Document title", required: true }, { name: "category", label: "Category", kind: "select", options: ["paper", "procedure", "result", "formulation", "technical_report", "minutes", "manual", "presentation", "other"] }, { name: "description", label: "Description", kind: "textarea" }] },
  formulation: { title: "New formulation concept", endpoint: "formulations", fields: [{ name: "product_name", label: "Product concept", required: true }, { name: "description", label: "Description", kind: "textarea" }] },
  meeting: { title: "Schedule a meeting", endpoint: "meetings", fields: [{ name: "title", label: "Meeting title", required: true }, { name: "meeting_at", label: "Date and time", kind: "date", required: true }, { name: "location_or_link", label: "Location or link" }, { name: "agenda", label: "Agenda", kind: "textarea" }] }
};

export function CreateRecordForm({ kind, projectId, disabled = false }: { kind: CreateKind; projectId?: string; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const form = config[kind];

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!projectId) { setMessage("Select or create a project before adding records."); return; }
    setPending(true); setMessage("");
    const data = new FormData(event.currentTarget);
    const values: Record<string, unknown> = { project_id: projectId };
    for (const field of form.fields) {
      const value = String(data.get(field.name) ?? "").trim();
      if (value) values[field.name] = field.kind === "date" ? new Date(value).toISOString() : value;
    }
    const response = await fetch(`/api/v1/${form.endpoint}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(values) });
    const result = await response.json().catch(() => ({}));
    setPending(false);
    if (!response.ok) { setMessage(result.error ?? "This record could not be saved."); return; }
    setMessage("Record saved.");
    event.currentTarget.reset();
    window.location.reload();
  }

  return <div className="relative">
    <Button type="button" onClick={() => { setOpen(!open); setMessage(""); }} disabled={disabled || !projectId} aria-expanded={open} aria-controls={`create-${kind}`}><Plus size={16} />{form.title}</Button>
    {open && <div id={`create-${kind}`} className="absolute right-0 z-30 mt-2 w-[min(92vw,420px)] rounded-2xl border border-line bg-surface p-5 shadow-soft sm:p-6">
      <div className="mb-5 flex items-start justify-between gap-3"><div><h2 className="text-sm font-semibold text-ink">{form.title}</h2><p className="mt-1 text-xs leading-5 text-muted">Changes are recorded with your signed-in identity.</p></div><button type="button" aria-label="Close" onClick={() => setOpen(false)} className="rounded-lg p-1.5 text-muted hover:bg-paper"><X size={16} /></button></div>
      <form onSubmit={submit} className="space-y-4">
        {form.fields.map((field) => <Field key={field.name}><FieldLabel htmlFor={`${kind}-${field.name}`}>{field.label}{field.required && <span className="ml-1 text-rose-700">*</span>}</FieldLabel>{field.kind === "textarea" ? <Textarea id={`${kind}-${field.name}`} name={field.name} required={field.required} /> : field.kind === "select" ? <select id={`${kind}-${field.name}`} name={field.name} required={field.required} className="h-10 w-full rounded-xl border border-line bg-white px-3 text-sm text-ink"><option value="">Choose one</option>{field.options?.map((option) => <option key={option} value={option}>{option.replaceAll("_", " ")}</option>)}</select> : <Input id={`${kind}-${field.name}`} name={field.name} type={field.kind === "date" ? "datetime-local" : "text"} required={field.required} />}</Field>)}
        {message && <p role="status" className="rounded-xl bg-paper px-3 py-2 text-xs leading-5 text-muted">{message}</p>}
        <div className="flex justify-end gap-2 pt-1"><Button type="button" variant="ghost" onClick={() => setOpen(false)}>Cancel</Button><Button type="submit" disabled={pending}>{pending ? "Saving…" : "Save record"}</Button></div>
      </form>
    </div>}
  </div>;
}
