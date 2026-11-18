import { AppShell } from "@/components/workspace/app-shell";
import { requireWorkspace } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function WorkspaceLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const member = await requireWorkspace();
  return <AppShell member={member}>{children}</AppShell>;
}
