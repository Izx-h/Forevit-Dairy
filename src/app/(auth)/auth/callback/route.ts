import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

function safeInternalTarget(value: string | null, origin: string) {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\") || /[\r\n]/.test(value)) return "/dashboard";
  try {
    const target = new URL(value, origin);
    if (target.origin !== origin) return "/dashboard";
    return `${target.pathname}${target.search}${target.hash}`;
  } catch {
    return "/dashboard";
  }
}

export async function GET(request: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const code = request.nextUrl.searchParams.get("code");
  const invitationToken = request.nextUrl.searchParams.get("invite_token");
  if (!supabase || !code) return NextResponse.redirect(new URL("/login?error=invalid", request.nextUrl));

  const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
  if (exchangeError) return NextResponse.redirect(new URL("/login?error=credentials", request.nextUrl));

  if (invitationToken !== null) {
    if (!/^[a-f0-9]{64}$/i.test(invitationToken)) {
      return NextResponse.redirect(new URL("/invite/accept?error=invalid", request.nextUrl));
    }
    const { error } = await supabase.rpc("accept_pending_invitation", { p_raw_token: invitationToken });
    if (error) return NextResponse.redirect(new URL("/invite/accept?error=unavailable", request.nextUrl));
    return NextResponse.redirect(new URL("/invite/accept?accepted=1", request.nextUrl));
  }

  const target = safeInternalTarget(request.nextUrl.searchParams.get("next"), request.nextUrl.origin);
  return NextResponse.redirect(new URL(target, request.nextUrl));
}
