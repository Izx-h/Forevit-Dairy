"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const loginSchema = z.object({ email: z.string().email().max(320), password: z.string().min(1).max(256) });

export async function signInAction(formData: FormData) {
  const parsed = loginSchema.safeParse({
    email: String(formData.get("email") ?? "").trim().toLowerCase(),
    password: String(formData.get("password") ?? "")
  });
  if (!parsed.success) redirect("/login?error=invalid");
  const supabase = await createSupabaseServerClient();
  if (!supabase) redirect("/login?reason=setup");
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) redirect("/login?error=credentials");
  redirect("/dashboard");
}

export async function signOutAction() {
  const supabase = await createSupabaseServerClient();
  if (supabase) await supabase.auth.signOut();
  redirect("/login");
}

export async function requestPasswordResetAction(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  if (!z.string().email().safeParse(email).success) redirect("/forgot-password?error=invalid");
  const supabase = await createSupabaseServerClient();
  if (!supabase) redirect("/forgot-password?reason=setup");
  const baseUrl = process.env.APP_BASE_URL;
  if (!baseUrl) redirect("/forgot-password?reason=setup");
  await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${baseUrl.replace(/\/$/, "")}/auth/callback?next=/reset-password` });
  redirect("/forgot-password?sent=1");
}

export async function completePasswordResetAction(formData: FormData) {
  const parsed = z.object({ password: z.string().min(12).max(256), confirmation: z.string().min(12).max(256) })
    .refine((value) => value.password === value.confirmation).safeParse({
      password: String(formData.get("password") ?? ""),
      confirmation: String(formData.get("confirmation") ?? "")
    });
  if (!parsed.success) redirect("/reset-password?error=invalid");
  const supabase = await createSupabaseServerClient();
  if (!supabase) redirect("/reset-password?reason=setup");
  const { data: { user }, error: sessionError } = await supabase.auth.getUser();
  if (sessionError || !user) redirect("/login?error=recovery");
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) redirect("/reset-password?error=update");
  redirect("/reset-password?success=1");
}
