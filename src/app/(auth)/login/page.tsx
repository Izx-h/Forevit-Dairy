import Link from "next/link";
import { ArrowUpRight, CircleCheck, FlaskConical, LockKeyhole, ShieldCheck } from "lucide-react";
import { Brand, BrandMark } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/primitives";
import { signInAction } from "@/lib/auth/actions";

const messages: Record<string, string> = {
  credentials: "We could not sign you in with those details. Check your email and password, then try again.",
  invalid: "Enter a valid email address and password.",
  membership: "Your account is verified, but no active Forevit project membership is linked yet. Ask a project administrator to invite you.",
  setup: "Secure sign-in is not connected yet. An administrator must configure the Supabase project before members can access research records."
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; reason?: string }> }) {
  const params = await searchParams;
  const message = params.error ? messages[params.error] : params.reason ? messages[params.reason] : null;
  return (
    <main className="min-h-screen bg-paper">
      <div className="grid min-h-screen lg:grid-cols-[1.02fr_.98fr]">
        <section className="relative hidden overflow-hidden bg-[#173d34] px-10 py-10 text-white lg:flex lg:flex-col lg:justify-between xl:px-16 xl:py-14">
          <div className="absolute inset-0 opacity-[0.09] panel-grid" />
          <div className="absolute -right-32 top-28 h-96 w-96 rounded-full border border-white/20" />
          <div className="absolute -right-16 top-44 h-64 w-64 rounded-full border border-white/15" />
          <div className="relative z-10"><Brand href="/login" /><p className="mt-16 max-w-lg text-[10px] font-semibold uppercase tracking-[0.23em] text-emerald-100/75">Private research workspace</p><h1 className="mt-5 max-w-xl text-4xl font-medium leading-[1.12] tracking-[-0.05em] xl:text-[3.35rem]">Research that keeps its <span className="font-serif italic text-emerald-100">source.</span></h1><p className="mt-6 max-w-md text-sm leading-7 text-emerald-50/75">A shared place for laboratory work, project knowledge and decisions—with a clear record of who changed what, and when.</p></div>
          <div className="relative z-10 grid max-w-xl gap-3 sm:grid-cols-2">
            {[{ icon: FlaskConical, title: "Linked lab records", body: "Samples, procedures and result revisions stay connected." }, { icon: ShieldCheck, title: "Project-scoped access", body: "Only invited members can see their authorized work." }].map(({ icon: Icon, title, body }) => <div key={title} className="rounded-2xl border border-white/15 bg-white/[0.055] p-4 backdrop-blur-sm"><Icon size={18} className="text-emerald-100" /><p className="mt-3 text-sm font-medium">{title}</p><p className="mt-1 text-xs leading-5 text-emerald-50/65">{body}</p></div>)}
          </div>
          <div className="relative z-10 flex items-center justify-between text-[10px] text-emerald-50/50"><span>Forevit Dairy · Research group</span><span>Source records remain authoritative</span></div>
        </section>

        <section className="flex min-h-screen flex-col justify-between px-5 py-7 sm:px-10 sm:py-10 lg:px-14 xl:px-20">
          <div className="flex items-center justify-between"><div className="lg:hidden"><Brand compact href="/login" /></div><span className="hidden lg:block" /><span className="inline-flex items-center gap-2 text-[11px] text-muted"><LockKeyhole size={14} />Invite-only access</span></div>
          <div className="mx-auto w-full max-w-[420px] py-12">
            <div className="mb-8 grid h-12 w-12 place-items-center rounded-2xl bg-pine-50 lg:hidden"><BrandMark className="h-9 w-9" /></div>
            <p className="text-[10px] font-semibold uppercase tracking-[0.2em] text-pine-700">Member sign-in</p>
            <h2 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-ink">Your research, in context.</h2>
            <p className="mt-2 text-sm leading-6 text-muted">Use the email address associated with your Forevit invitation.</p>
            <Card className="mt-8 p-5 sm:p-7">
              <form action={signInAction} className="space-y-5">
                <label className="block space-y-2"><span className="text-xs font-medium text-ink">Email address</span><input name="email" type="email" autoComplete="email" required maxLength={320} className="h-11 w-full rounded-xl border border-line bg-white px-3.5 text-sm text-ink placeholder:text-muted/70 focus:border-pine-500 focus:outline-none focus:ring-2 focus:ring-pine-100" placeholder="name@organization.org" /></label>
                <label className="block space-y-2"><span className="flex items-center justify-between text-xs font-medium text-ink"><span>Password</span><Link href="/forgot-password" className="font-normal text-pine-700 hover:underline">Forgot password?</Link></span><input name="password" type="password" autoComplete="current-password" required maxLength={256} className="h-11 w-full rounded-xl border border-line bg-white px-3.5 text-sm text-ink focus:border-pine-500 focus:outline-none focus:ring-2 focus:ring-pine-100" placeholder="Enter your password" /></label>
                {message && <div role="status" className={`rounded-xl px-3.5 py-3 text-xs leading-5 ${params.reason === "setup" ? "border border-amber-100 bg-amber-50 text-amber-700" : "border border-line bg-paper text-muted"}`}>{message}</div>}
                <Button type="submit" className="h-11 w-full">Sign in <ArrowUpRight size={15} /></Button>
              </form>
              <div className="mt-5 flex items-start gap-2.5 rounded-xl border border-line bg-[#faf9f5] p-3"><CircleCheck size={15} className="mt-0.5 shrink-0 text-pine-700" /><p className="text-[11px] leading-5 text-muted">Access is granted by project membership. Having an account alone does not unlock research records.</p></div>
            </Card>
            <p className="mt-5 text-center text-xs text-muted">Need access? <span className="font-medium text-ink">Ask your project administrator for an invitation.</span></p>
          </div>
          <div className="flex items-center justify-between text-[10px] text-muted"><span>Private workspace</span><span>Forevit Dairy</span></div>
        </section>
      </div>
    </main>
  );
}
