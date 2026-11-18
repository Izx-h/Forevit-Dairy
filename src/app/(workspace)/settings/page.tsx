import { BellRing, Database, KeyRound, ShieldCheck } from "lucide-react";
import { SectionHeading } from "@/components/ui/empty-state";
import { Badge, Card } from "@/components/ui/primitives";
import { requireWorkspace } from "@/lib/auth/session";

function ConnectionCard({ icon: Icon, title, configured, detail }: { icon: typeof Database; title: string; configured: boolean; detail: string }) {
  return <Card className="flex items-start gap-3 p-5"><span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-pine-50 text-pine-700"><Icon size={17} /></span><div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><h2 className="text-sm font-semibold text-ink">{title}</h2><Badge variant={configured ? "default" : "amber"}>{configured ? "Configured" : "Needs setup"}</Badge></div><p className="mt-2 text-xs leading-5 text-muted">{detail}</p></div></Card>;
}

export default async function SettingsPage() {
  const member = await requireWorkspace();
  const supabaseReady = Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY && process.env.SUPABASE_SERVICE_ROLE_KEY);
  const deepseekReady = Boolean(process.env.DEEPSEEK_API_KEY);
  const whatsappReady = Boolean(process.env.WHATSAPP_ACCESS_TOKEN && process.env.WHATSAPP_PHONE_NUMBER_ID && process.env.WHATSAPP_VERIFY_TOKEN && process.env.WHATSAPP_APP_SECRET);
  return <div className="space-y-7"><SectionHeading eyebrow="Workspace governance" title="Settings" description="Review your account role and integration readiness. Secret values are never displayed in the application." /><Card className="flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between sm:p-6"><div className="flex items-start gap-3"><span className="grid h-10 w-10 place-items-center rounded-xl bg-pine-50 text-pine-700"><ShieldCheck size={18} /></span><div><h2 className="text-sm font-semibold text-ink">Your workspace role</h2><p className="mt-1 text-xs leading-5 text-muted">Role-based actions are enforced by server authorization and database policies.</p></div></div><Badge variant="muted">{member.role.replaceAll("_", " ")}</Badge></Card><section className="space-y-3"><h2 className="text-[10px] font-semibold uppercase tracking-[0.18em] text-muted">Service configuration</h2><ConnectionCard icon={Database} title="Supabase" configured={supabaseReady} detail="Auth, PostgreSQL, Row Level Security, private Storage and Realtime. This check reveals presence only, never values." /><ConnectionCard icon={KeyRound} title="DeepSeek AI" configured={deepseekReady} detail="Server-side AI requests remain disabled until the provider key and authorized worker are configured." /><ConnectionCard icon={BellRing} title="WhatsApp delivery" configured={whatsappReady} detail="Optional delivery requires member consent, event preferences, verified callbacks and provider credentials." /></section><Card className="border-amber-100 bg-amber-50/50 p-5"><p className="text-xs leading-5 text-amber-800">Credentials belong in the hosting provider’s protected secret manager, not in chat, Git or browser-visible settings. Configure development and production values separately.</p></Card></div>;
}
