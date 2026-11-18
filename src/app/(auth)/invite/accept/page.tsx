import Link from "next/link";
import { Brand } from "@/components/brand";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/primitives";

type Search = { accepted?: string; error?: string };

export default async function AcceptInvitationPage({ searchParams }: { searchParams: Promise<Search> }) {
  const { accepted, error } = await searchParams;
  const complete = accepted === "1";
  const invalid = error === "invalid" || error === "unavailable";
  return <main className="flex min-h-screen flex-col bg-paper px-5 py-8 sm:px-10"><div className="mx-auto w-full max-w-5xl"><Brand href="/login" /></div><section className="mx-auto my-auto w-full max-w-[430px] py-14"><p className="text-[10px] font-semibold uppercase tracking-[0.2em] text-pine-700">Invitation</p><h1 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-ink">{complete ? "You’re in the research workspace" : "Join the research workspace"}</h1><p className="mt-2 text-sm leading-6 text-muted">Membership is activated only after Supabase verifies the invited email and the one-time invitation is accepted.</p><Card className="mt-7 p-5 sm:p-6">{complete ? <div className="space-y-4"><p className="rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm leading-6 text-emerald-800">Your verified invitation was accepted. Access is limited to the organization and project you were invited to.</p><Button asChild className="w-full"><Link href="/dashboard">Continue to workspace</Link></Button></div> : invalid ? <div className="space-y-4"><p role="alert" className="rounded-xl border border-amber-100 bg-amber-50 p-4 text-sm leading-6 text-amber-800">This invitation could not be activated. It may have expired, been revoked, or been issued to a different email address. Ask an administrator to send a new invitation.</p><Button asChild variant="secondary" className="w-full"><Link href="/login">Return to sign in</Link></Button></div> : <p className="rounded-xl border border-line bg-[#faf9f5] p-4 text-sm leading-6 text-muted">Open the invitation link from your email to verify your account and activate your membership.</p>}</Card></section><p className="mx-auto w-full max-w-5xl text-[10px] text-muted">Forevit Dairy · Private workspace</p></main>;
}
